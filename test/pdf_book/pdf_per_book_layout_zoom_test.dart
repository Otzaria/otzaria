import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-layout-zoom-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium.dylib'
        : 'libpdfium.so';
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
  });

  tearDown(() {
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    // כישלון באמצע הבדיקה לא ייתקע על קובץ שעוד פתוח ב-pdfium.
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException catch (_) {}
  });

  testWidgets('הגדרת פר-ספר שנקראה אחרי הטעינה לא נדרסת בהתאמה לרוחב', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await Settings.setValue<bool>(
      SettingsRepository.keyEnablePerBookSettings,
      true,
    );
    await Settings.setValue<bool>(
      SettingsRepository.keyPdfBookViewByDefault,
      false,
    );

    final file = File('${directory.path}/book.pdf');
    final book = PdfBook(title: 'ספר בדיקה', path: file.path);
    final gate = Completer<void>();
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < 4; i++) {
        pdf.addPage(
          pw.Page(
            pageFormat: pdf_lib.PdfPageFormat.a4,
            build: (_) => pw.SizedBox(),
          ),
        );
      }
      await file.writeAsBytes(await pdf.save());
      await PdfBookPerBookSettings(
        zoom: 2.5,
        layoutMode: PdfLayoutMode.bookView,
      ).save(book);
    });
    // קריאת ההגדרות במסך ובבלוק ממתינה עד שהמסמך כבר נטען.
    unawaited(
      PerBookSettings.runLockedForKey(
        PerBookSettings.bookKey(book),
        () => gate.future,
      ),
    );

    final tab = PdfBookTab(book: book, pageNumber: 1);
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = _SettingsBloc();
    final tour = TourCubit();
    addTearDown(tab.dispose);
    addTearDown(tabsBloc.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    try {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            mui.DefaultMaterialLocalizations.delegate,
          ],
          home: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<TourCubit>.value(value: tour),
            ],
            child: PdfBookScreen(tab: tab),
          ),
        ),
      );
      final bloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();
      for (var i = 0; i < 100 && bloc.state is! PdfBookLoaded; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(bloc.state, isA<PdfBookLoaded>());

      gate.complete();
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect((bloc.state as PdfBookLoaded).layoutMode, PdfLayoutMode.bookView);
      expect(tab.pdfViewerController.currentZoom, closeTo(2.5, 0.001));
      final stored = await tester.runAsync(
        () => PdfBookPerBookSettings.load(book),
      );
      expect(stored?.zoom, closeTo(2.5, 0.001));
    } finally {
      // בלי שחרור הנעילה וסגירת המסך, ה-tearDown נכשל ומסתיר את הכישלון האמיתי.
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(PerBookSettings.settle);
    }
  });
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return [];
    if (invocation.memberName == #loadCurrentTabIndex) return 0;
    return Future<void>.value();
  }
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc()
    : super(SettingsState.initial().copyWith(enablePerBookSettings: true)) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
