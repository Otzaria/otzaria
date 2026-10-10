import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart' as events;
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late PdfrxEntryFunctions originalBackend;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-retry-');
    originalBackend = PdfrxEntryFunctions.instance;
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
    PdfrxEntryFunctions.instance = originalBackend;
    Pdfrx.pdfiumModulePath = originalModulePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 40 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  for (final fails in [true, false]) {
    testWidgets(
      fails
          ? 'נסה שוב טוען מחדש אחרי כשל פתיחה אמיתי'
          : 'נסה שוב אחרי timeout משאיר את הפתיחה הממתינה ואת ה-viewer',
      (tester) async {
        final readyDocument = (await tester.runAsync(() async {
          await pdfrxFlutterInitialize();
          final pdf = pw.Document()
            ..addPage(pw.Page(build: (_) => pw.SizedBox()));
          return PdfDocument.openData(
            await pdf.save(),
            sourceName: '${directory.path}/ready.pdf',
          );
        }))!;
        final backend = _DelayedBackend();
        PdfrxEntryFunctions.instance = backend;
        final file = File('${directory.path}/book.pdf')
          ..writeAsStringSync('delayed');
        final tab = PdfBookTab(
          book: PdfBook(title: 'ספר בדיקה', path: file.path),
          pageNumber: 1,
        );
        final tabsBloc = TabsBloc(repository: _TabsRepository());
        // ignore: invalid_use_of_visible_for_testing_member
        tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
        final settings = _SettingsBloc();
        final tour = TourCubit();
        addTearDown(tab.dispose);
        addTearDown(tabsBloc.close);
        addTearDown(settings.close);
        addTearDown(tour.close);
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
        await pumpUntil(tester, () => backend.opens.length == 1);
        final viewer = find.byType(PdfViewer);
        final viewerState = tester.state(viewer);
        final bloc = tester.element(viewer).read<PdfBookBloc>();
        bloc.add(const events.DocumentLoadFailed('timeout'));
        await tester.pump();
        await tester.pump();
        expect(bloc.state, isA<PdfBookError>());
        expect(tester.state(viewer), same(viewerState));

        if (fails) {
          backend.opens.single.completeError(
            PdfException('failed open'),
            StackTrace.empty,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            tester
                .widget<PdfViewer>(viewer)
                .documentRef
                .resolveListenable()
                .error,
            isNotNull,
          );
        }
        await tester.tap(find.text('נסה שוב'));
        await pumpUntil(tester, () => bloc.state is PdfBookLoading);
        expect(tester.state(viewer), same(viewerState));
        if (fails) {
          await pumpUntil(tester, () => backend.opens.length == 2);
        } else {
          expect(backend.opens, hasLength(1));
        }
        backend.opens.last.complete(readyDocument);
        await pumpUntil(tester, () => bloc.state is PdfBookLoaded);
        expect(tester.state(viewer), same(viewerState));
        expect(backend.opens, hasLength(fails ? 2 : 1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  }
}

class _DelayedBackend implements PdfrxEntryFunctions {
  final opens = <Completer<PdfDocument>>[];

  @override
  Future<void> init() async {}

  @override
  Future<PdfDocument> openFile(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) {
    final opened = Completer<PdfDocument>();
    opens.add(opened);
    return opened.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  _SettingsBloc() : super(SettingsState.initial()) {
    on<SettingsEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
