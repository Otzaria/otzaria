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
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../helpers/memory_settings_cache.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// העמוד שהקורא מחזיק (כותרת, ניווט, מיקום שמור) הוא העמוד שעל המסך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  final originalModulePath = Pdfrx.pdfiumModulePath;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-position-');
    final moduleName = Platform.isWindows
        ? 'pdfium.dll'
        : Platform.isMacOS
        ? 'libpdfium_dart.dylib'
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
    directory.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester, int rounds) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String Function()? diagnostics,
  }) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await settle(tester, 1);
    }
    expect(condition(), isTrue, reason: diagnostics?.call());
  }

  Future<PdfBookTab> pumpReader(
    WidgetTester tester,
    List<PdfPageFormat> pages, {
    int initialPage = 1,
    bool openLeftPane = false,
    void Function(PdfBookTab)? configureTab,
    Future<void>? perBookSettingsBlockedUntil,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      await pdfrxFlutterInitialize();
      final pdf = pw.Document();
      for (var i = 0; i < pages.length; i++) {
        pdf.addPage(
          pw.Page(pageFormat: pages[i], build: (_) => pw.Text('${i + 1}')),
        );
      }
      await file.writeAsBytes(await pdf.save());
    });
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר בדיקה', path: file.path),
      pageNumber: initialPage,
      openLeftPane: openLeftPane,
    );
    configureTab?.call(tab);
    if (perBookSettingsBlockedUntil != null) {
      unawaited(
        PerBookSettings.runLockedForKey(
          PerBookSettings.bookKey(tab.book),
          () => perBookSettingsBlockedUntil,
        ),
      );
    }
    final tabsBloc = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabsBloc.emit(TabsState(tabs: [tab], currentTabIndex: 0));
    final settings = StubSettingsBloc();
    final tour = TourCubit();
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
    await pumpUntil(tester, () => tab.documentRef.value != null);
    return tab;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('גלילה לפני סיום הפתיחה אינה חוזרת לעמוד הפתיחה (#3261)', (
    tester,
  ) async {
    // קריאת ההגדרות לפי-ספר איטית (דיסק, אנטי-וירוס) ומסתיימת אחרי הגלילה.
    final slowSettings = Completer<void>();
    final tab = await pumpReader(
      tester,
      List.filled(30, PdfPageFormat.a4),
      perBookSettingsBlockedUntil: slowSettings.future,
    );
    final controller = tab.pdfViewerController;
    final bloc = tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();

    for (var i = 0; i < 6; i++) {
      await tester.drag(
        find.byType(PdfViewer),
        const Offset(0, -900),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scrolledTo = controller.pageNumber!;
    expect(scrolledTo, greaterThan(2));

    slowSettings.complete();
    await pumpUntil(tester, () => bloc.state is PdfBookLoaded);
    await settle(tester, 20);
    expect(controller.pageNumber, scrolledTo);

    await unmount(tester);
  });

  testWidgets('פתיחה בעמוד אינה מציגה את שולי העמוד הקודם (#5928)', (
    tester,
  ) async {
    const initialPage = 5;
    final tab = await pumpReader(
      tester,
      List.filled(12, PdfPageFormat.a4),
      initialPage: initialPage,
    );
    final controller = tab.pdfViewerController;
    await pumpUntil(
      tester,
      () {
        final pages = controller.layout.pageLayouts;
        if (pages.length < initialPage) return false;
        return (controller.visibleRect.top - pages[initialPage - 1].top).abs() <
                0.1 &&
            controller.pageNumber == initialPage &&
            tab.pageNumber == initialPage;
      },
      diagnostics: () {
        final pages = controller.layout.pageLayouts;
        final targetTop = pages.length >= initialPage
            ? pages[initialPage - 1].top
            : null;
        return 'layouts=${pages.length}, '
            'visibleTop=${controller.visibleRect.top}, '
            'targetTop=$targetTop, controllerPage=${controller.pageNumber}, '
            'tabPage=${tab.pageNumber}';
      },
    );

    final targetPage = controller.layout.pageLayouts[initialPage - 1];
    final previousPage = controller.layout.pageLayouts[initialPage - 2];
    expect(controller.visibleRect.top, closeTo(targetPage.top, 0.1));
    expect(controller.visibleRect.overlaps(previousPage), isFalse);
    expect(controller.pageNumber, initialPage);
    expect(tab.pageNumber, initialPage);

    await unmount(tester);
  });

  testWidgets('פתיחת PDF משוחזר מחזיקה את ראש העמוד בזום השמור', (
    tester,
  ) async {
    const initialPage = 5;
    const savedZoom = 2.4;
    final tab = await pumpReader(
      tester,
      [
        for (var index = 0; index < 12; index++)
          index == 3 ? const PdfPageFormat(700, 780) : PdfPageFormat.a4,
      ],
      initialPage: initialPage,
      configureTab: (tab) => tab.savedZoom = savedZoom,
    );
    final controller = tab.pdfViewerController;
    await pumpUntil(
      tester,
      () => (controller.currentZoom - savedZoom).abs() < 0.01,
    );
    await settle(tester, 20);

    final targetPage = controller.layout.pageLayouts[initialPage - 1];
    expect(controller.visibleRect.top, closeTo(targetPage.top, 0.1));
    expect(tab.pageNumber, initialPage);

    await unmount(tester);
  });

  testWidgets('פתיחה בעמוד שומרת את ראשו כשחלונית הניווט נפתחת', (
    tester,
  ) async {
    const initialPage = 5;
    double? widthAtPublication;
    final tab = await pumpReader(
      tester,
      List.filled(12, PdfPageFormat.a4),
      initialPage: initialPage,
      openLeftPane: true,
      configureTab: (tab) {
        tab.documentRef.addListener(() {
          if (tab.documentRef.value == null) return;
          widthAtPublication = tab.pdfViewerController.viewSize.width;
        });
      },
    );
    await settle(tester, 20);
    final controller = tab.pdfViewerController;
    final targetPage = controller.layout.pageLayouts[initialPage - 1];
    expect(controller.viewSize.width, lessThan(widthAtPublication!));
    expect(controller.visibleRect.top, closeTo(targetPage.top, 0.1));
    expect(tab.pageNumber, initialPage);

    final centerBeforeWindowResize = controller.centerPosition.dy;
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    await settle(tester, 20);
    expect(
      controller.centerPosition.dy,
      closeTo(centerBeforeWindowResize, 0.1),
    );

    await unmount(tester);
  });

  testWidgets('ניווט תכנותי אחרי isReady אינו נדרס בתיקון הפתיחה', (
    tester,
  ) async {
    const initialPage = 5;
    final tab = await pumpReader(
      tester,
      List.filled(12, PdfPageFormat.a4),
      initialPage: initialPage,
    );
    final controller = tab.pdfViewerController;
    await pumpUntil(
      tester,
      () => controller.layout.pageLayouts.length >= initialPage,
    );

    await controller.goToPage(
      pageNumber: initialPage,
      anchor: PdfPageAnchor.center,
      duration: Duration.zero,
    );
    await settle(tester, 20);

    final targetPage = controller.layout.pageLayouts[initialPage - 1];
    expect(controller.visibleRect.contains(targetPage.center), isTrue);
    expect(controller.pageNumber, initialPage);

    await unmount(tester);
  });

  testWidgets('ניווט מאזין המסמך נשמר בתצוגה ובטאב עם פתיחת חלונית', (
    tester,
  ) async {
    const laterPage = 8;
    Future<void>? navigation;
    final tab = await pumpReader(
      tester,
      List.filled(12, PdfPageFormat.a4),
      initialPage: 5,
      openLeftPane: true,
      configureTab: (tab) {
        tab.documentRef.addListener(() {
          if (tab.documentRef.value == null) return;
          navigation = tab.pdfViewerController.goToPage(
            pageNumber: laterPage,
            anchor: PdfPageAnchor.center,
            duration: Duration.zero,
          );
        });
      },
    );
    await navigation!;
    await settle(tester, 20);

    final controller = tab.pdfViewerController;
    final target = controller.layout.pageLayouts[laterPage - 1];
    expect(controller.visibleRect.center.dy, closeTo(target.center.dy, 0.1));
    expect(controller.pageNumber, laterPage);
    expect(tab.pageNumber, laterPage);

    await unmount(tester);
  });

  testWidgets('פתיחה בתצוגת ספר מציגה את הכפולה של עמוד היעד', (
    tester,
  ) async {
    await Settings.setValue(SettingsRepository.keyPdfBookViewByDefault, true);
    final tab = await pumpReader(
      tester,
      List.filled(12, PdfPageFormat.a4),
      initialPage: 5,
    );
    await settle(tester, 20);

    final controller = tab.pdfViewerController;
    final pages = controller.layout.pageLayouts;
    expect(pages[3].top, pages[4].top);
    expect(controller.visibleRect.overlaps(pages[3]), isTrue);
    expect(controller.visibleRect.overlaps(pages[4]), isTrue);

    await unmount(tester);
  });

  testWidgets('אחרי קפיצה רחוקה הטאב מחזיק את העמוד שעל המסך (#3248)', (
    tester,
  ) async {
    final tab = await pumpReader(tester, [
      for (var i = 0; i < 350; i++)
        i < 4 ? PdfPageFormat.a4 : const PdfPageFormat(700, 1000),
    ]);
    final controller = tab.pdfViewerController;
    await settle(tester, 30);
    int pageAtTop() {
      final top = controller.visibleRect.top + 1;
      return controller.layout.pageLayouts.indexWhere((r) => r.bottom > top) +
          1;
    }

    final jump = controller.goToPage(pageNumber: 246);
    await settle(tester, 60);
    await tester.runAsync(() => jump);
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.pageNumber, pageAtTop());
    expect(tab.pageNumber, pageAtTop());

    await unmount(tester);
  });

  testWidgets('דפדוף בחץ מעדכן את הטאב לעמוד החדש (#3250)', (tester) async {
    final tab = await pumpReader(tester, List.filled(20, PdfPageFormat.a4));
    final controller = tab.pdfViewerController;
    await settle(tester, 30);

    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester, 30);
      expect(controller.pageNumber, i + 2);
      expect(tab.pageNumber, controller.pageNumber);
    }

    await unmount(tester);
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
