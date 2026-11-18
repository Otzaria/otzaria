import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:material_ui/material_ui.dart' as mui;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../helpers/pdf_viewer_mounted.dart';
import '../test_helpers/pdf_document_dispose.dart';
import '../test_helpers/stub_settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;
  late String oldPath;
  late String activePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    dir = Directory.systemTemp.createTempSync('otzaria-pdf-review-');
    final activeLibrary = p.join(dir.path, 'new', 'books');
    Directory(activeLibrary).createSync(recursive: true);
    oldPath = p.join(dir.path, 'old', 'books', 'book.pdf');
    activePath = p.join(activeLibrary, 'book.pdf');
    final pdf = pw.Document()..addPage(pw.Page(build: (_) => pw.Text('page')));
    File(activePath).writeAsBytesSync(await pdf.save());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      activeLibrary,
    );
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
        : 'libpdfium.so';
    final originalModulePath = Pdfrx.pdfiumModulePath;
    addTearDown(() => Pdfrx.pdfiumModulePath = originalModulePath);
    Pdfrx.pdfiumModulePath = File(
      'build/native_assets/${Platform.operatingSystem}/$moduleName',
    ).absolute.path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    await pdfrxFlutterInitialize();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר אישי', path: oldPath),
      pageNumber: 1,
    );
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = StubSettingsBloc();
    final tour = TourCubit();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(tour.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          mui.DefaultMaterialLocalizations.delegate,
        ],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TabsBloc>.value(value: tabs),
              BlocProvider<TourCubit>.value(value: tour),
            ],
            child: PdfBookScreen(tab: tab),
          ),
        ),
      ),
    );
  }

  Future<void> withSlowOriginalPath(
    Future<void> Function(Completer<bool>) test,
  ) {
    final oldProbe = Completer<bool>();
    return IOOverrides.runZoned(
      () => test(oldProbe),
      createFile: (path) {
        if (path == oldPath) return _ProbedFile(path, oldProbe.future);
        if (path == activePath) return _ProbedFile(path, Future.value(true));
        return _RealFiles().createFile(path);
      },
    );
  }

  ActionButtonData printAction(WidgetTester tester) {
    final actions = tester.widget<ResponsiveActionBar>(
      find.byKey(const ValueKey('pdf_actions')),
    );
    return actions.alwaysInMenu!.singleWhere(
      (action) => action.tooltip == 'הדפס',
    );
  }

  testWidgets('הדפסה זמינה אחרי איתור הנתיב החדש של PDF שהועבר', (
    tester,
  ) async {
    await withSlowOriginalPath((oldProbe) async {
      await pumpReader(tester);
      expect(printAction(tester).onPressed, isNull);
      expect(find.byType(PdfViewer), findsNothing);

      oldProbe.complete(false);
      await tester.pump();
      final print = printAction(tester).onPressed;
      expect(print, isNotNull);
      print!.call();
      await tester.pump();

      final dialog = tester.widget<PrintingScreen>(find.byType(PrintingScreen));
      expect(dialog.pdfFilePath, activePath);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('נסה שוב טוען מחדש כשל שנשמר לאותו נתיב', (tester) async {
    final file = File(activePath);
    final validPdf = file.readAsBytesSync();
    file.writeAsStringSync('invalid PDF');

    Future<void> pumpUntil(bool Function() ready) async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(ready(), isTrue);
    }

    await withSlowOriginalPath((oldProbe) async {
      await pumpReader(tester);
      oldProbe.complete(false);
      final bloc = await pumpUntilPdfViewer(tester);
      await pumpUntil(() => find.text('נסה שוב').evaluate().isNotEmpty);

      file.writeAsBytesSync(validPdf);
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      final listenable = viewer.documentRef.resolveListenable();
      expect(listenable.error, isNotNull);
      await tester.tap(find.text('נסה שוב'));
      await tester.pump();
      expect(bloc.state, isA<PdfBookLoading>());
      await pumpUntil(() => bloc.state is PdfBookLoaded);

      final document = bloc.tab.pdfViewerController.document;
      await tester.pumpWidget(const SizedBox.shrink());
      await disposePdfDocument(tester, document);
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  testWidgets('יציאה לפני הרכבת הצפיין אינה משאירה הפניה למסך במטמון', (
    tester,
  ) async {
    await withSlowOriginalPath((oldProbe) async {
      await pumpReader(tester);
      final bloc = tester
          .element(find.byKey(const ValueKey('pdf_actions')))
          .read<PdfBookBloc>();
      oldProbe.complete(false);
      await tester.idle();
      expect(bloc.state, isA<PdfBookLoading>());
      expect(find.byType(PdfViewer), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      final reopenRef = PdfDocumentRefFile(activePath);
      final listenable = reopenRef.resolveListenable();
      addTearDown(listenable.addListener(() {}));
      expect(listenable.ref, same(reopenRef));
    });
  });
}

final class _RealFiles extends IOOverrides {}

class _ProbedFile implements File {
  _ProbedFile(this.path, this.result);

  @override
  final String path;
  final Future<bool> result;

  @override
  Future<bool> exists() => result;

  @override
  bool existsSync() => false;

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
