import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdfdoc;
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../helpers/memory_settings_cache.dart';

/// issue #3355 — החלקה בשתי אצבעות על לוח המגע לא עברה מכרטיסיית PDF
/// לכרטיסייה הסמוכה. נבדק על ReadingScreen האמיתי עם PDF אמיתי.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final originalModulePath = Pdfrx.pdfiumModulePath;
  late Directory directory;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    directory = Directory.systemTemp.createTempSync('otzaria-pdf-swipe-');
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
    directory.deleteSync(recursive: true);
  });

  Future<void> frames(WidgetTester tester, [int count = 30]) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  PdfBookBloc pdfBloc(WidgetTester tester) =>
      tester.element(find.byType(PdfViewer)).read<PdfBookBloc>();

  /// כרטיסיית מפרשים בטאב 0 ו-PDF בטאב 1.
  Future<({TabsBloc tabs, PdfBookTab pdf})> pumpReader(
    WidgetTester tester, {
    required int currentTabIndex,
    List<Size>? pageSizes,
    bool edgeText = false,
  }) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final file = File('${directory.path}/book.pdf');
    await tester.runAsync(() async {
      final source = pw.Document();
      for (var page = 0; page < 8; page++) {
        source.addPage(
          pw.Page(
            pageFormat: pageSizes == null
                ? pdfdoc.PdfPageFormat.a4
                : pdfdoc.PdfPageFormat(
                    pageSizes[page % pageSizes.length].width,
                    pageSizes[page % pageSizes.length].height,
                  ),
            margin: edgeText ? pw.EdgeInsets.zero : null,
            build: (_) => edgeText
                ? pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'LEFT EDGE TEXT',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        'RIGHT EDGE TEXT',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  )
                : pw.SizedBox(),
          ),
        );
      }
      await file.writeAsBytes(await source.save());
    });
    final pdf = PdfBookTab(
      book: PdfBook(title: 'ספר PDF', path: file.path),
      pageNumber: 2,
    );
    final neighbor = _neighborTab();
    final tabs = TabsBloc(repository: _TabsRepository());
    // ignore: invalid_use_of_visible_for_testing_member
    tabs.emit(
      TabsState(
        tabs: <OpenedTab>[neighbor, pdf],
        currentTabIndex: currentTabIndex,
      ),
    );
    final settings = _SettingsBloc();
    final tour = TourCubit();
    final notes = _PersonalNotesBloc();
    final history = _HistoryBloc();
    addTearDown(tabs.close);
    addTearDown(settings.close);
    addTearDown(tour.close);
    addTearDown(notes.close);
    addTearDown(history.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<PersonalNotesBloc>.value(value: notes),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<HistoryBloc>.value(value: history),
            BlocProvider<TourCubit>.value(value: tour),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: const ReadingScreen(),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    });
    if (currentTabIndex == 1) await waitForPdf(tester, pdf);
    return (tabs: tabs, pdf: pdf);
  }

  /// החלקה אופקית בשתי אצבעות, עד [distance] (חיובי = ימינה).
  Future<void> swipe(WidgetTester tester, double distance) async {
    final center = tester.getCenter(find.byType(PageView));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    // צעדים של 10px כמו אירועי לוח מגע אמיתיים, ולא קפיצה אחת מעל כל הספים.
    const steps = 90;
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    for (var i = 1; i <= steps; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(distance * i / steps, 0),
        timeStamp: Duration(milliseconds: 8 * i),
      );
      await tester.pump();
    }
    await gesture.panZoomEnd(
      timeStamp: const Duration(milliseconds: 8 * (steps + 1)),
    );
    await frames(tester);
  }

  Future<void> toggleFit(WidgetTester tester) async {
    await tester.tap(find.byTooltip('התאם לרוחב / לעמוד שלם'));
    await frames(tester);
  }

  /// גלילה באלכסון, שמזיזה את התצוגה לרוחב עד קצה השוליים.
  Future<void> scrollDiagonally(WidgetTester tester, double dx) async {
    final center = tester.getCenter(find.byType(PageView));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    for (var i = 1; i <= 20; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(dx * i / 20, -150.0 * i / 20),
        timeStamp: Duration(milliseconds: 8 * i),
      );
      await tester.pump();
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 200));
    await frames(tester);
  }

  Future<void> touchSwipe(WidgetTester tester, double dx) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
      kind: PointerDeviceKind.touch,
    );
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(Offset(dx / 30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await frames(tester);
  }

  testWidgets('מסך מגע: התאמה לרוחב אחרי גלילה באלכסון עוברת כרטיסייה', (
    tester,
  ) async {
    final reader = await pumpReader(tester, currentTabIndex: 1);
    await toggleFit(tester);
    await scrollDiagonally(tester, 80);
    expect(reader.pdf.canPanHorizontally, isFalse);
    await touchSwipe(tester, 900);
    expect(reader.tabs.state.currentTabIndex, 0);
  });

  testWidgets('מסך מגע: PDF מוגדל נשאר ניתן להזזה', (tester) async {
    final reader = await pumpReader(tester, currentTabIndex: 1);
    final controller = reader.pdf.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    final before = controller.visibleRect.left;
    expect(reader.pdf.canPanHorizontally, isTrue);
    await touchSwipe(tester, 300);
    expect(reader.tabs.state.currentTabIndex, 1);
    expect(controller.visibleRect.left, isNot(closeTo(before, 1)));
  });

  testWidgets('כפולה מוגדלת: החלקה מזיזה את הדפים', (tester) async {
    final reader = await pumpReader(tester, currentTabIndex: 1);
    pdfBloc(tester).add(const SetLayoutMode(PdfLayoutMode.bookView));
    await frames(tester, 60);
    final controller = reader.pdf.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    final before = controller.visibleRect.left;
    expect(reader.pdf.canPanHorizontally, isTrue);
    await swipe(tester, 300);
    expect(reader.tabs.state.currentTabIndex, 1);
    expect(controller.visibleRect.left, isNot(closeTo(before, 1)));
  });

  testWidgets('עמוד צר נראה אינו נחסם בידי עמודים רחבים מחוץ לתצוגה', (
    tester,
  ) async {
    final reader = await pumpReader(
      tester,
      currentTabIndex: 1,
      pageSizes: const [
        Size(900, 800),
        Size(300, 800),
        Size(900, 800),
        Size(900, 800),
      ],
    );
    await toggleFit(tester);
    final controller = reader.pdf.pdfViewerController;
    expect(controller.pageNumber, 2);
    expect(reader.pdf.canPanHorizontally, isFalse);
    await swipe(tester, 900);
    expect(reader.tabs.state.currentTabIndex, 0);
  });

  testWidgets('עמוד רחב נראה נשאר ניתן להזזה', (tester) async {
    final reader = await pumpReader(
      tester,
      currentTabIndex: 1,
      pageSizes: const [
        Size(900, 800),
        Size(300, 800),
        Size(900, 800),
        Size(900, 800),
      ],
    );
    await toggleFit(tester);
    final controller = reader.pdf.pdfViewerController;
    await controller.goToPage(pageNumber: 3, duration: Duration.zero);
    await frames(tester);
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    expect(reader.pdf.canPanHorizontally, isTrue);
    final before = controller.visibleRect.left;
    await swipe(tester, 300);
    expect(reader.tabs.state.currentTabIndex, 1);
    expect(controller.visibleRect.left, isNot(closeTo(before, 1)));
  });

  testWidgets('הגדלה קטנה מעבר להתאמה לרוחב משאירה טקסט חתוך ניתן להזזה', (
    tester,
  ) async {
    final reader = await pumpReader(tester, currentTabIndex: 1, edgeText: true);
    await toggleFit(tester);
    final controller = reader.pdf.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 1.04,
      duration: Duration.zero,
    );
    await tester.pump();
    final view = controller.visibleRect;
    final page = controller.layout.pageLayouts[1];
    final clippedLeft = view.left - page.left;
    final clippedRight = page.right - view.right;
    expect(clippedLeft, greaterThan(0));
    expect(clippedRight, greaterThan(0));
    final text = await tester.runAsync(
      () => controller.document.pages[1].loadText(),
    );
    final minTextLeft =
        text!.charRects
            .map((rect) => rect.left)
            .reduce((a, b) => a < b ? a : b) +
        page.left;
    final maxTextRight =
        text.charRects
            .map((rect) => rect.right)
            .reduce((a, b) => a > b ? a : b) +
        page.left;
    expect(maxTextRight, greaterThan(view.right));
    expect(minTextLeft, lessThan(view.left));
    final canPan = reader.pdf.canPanHorizontally;
    await swipe(tester, 300);
    expect(
      canPan,
      isTrue,
      reason: 'טקסט בקצות העמוד חתוך, ולכן צריך לאפשר הזזה אופקית',
    );
    expect(reader.tabs.state.currentTabIndex, 1);
    expect(controller.visibleRect.left, lessThan(view.left));
  });

  final modes = <String, Future<void> Function(WidgetTester)>{
    'זום הפתיחה': (_) async {},
    'התאמה לרוחב': toggleFit,
    'התאמה לרוחב, אחרי גלילה באלכסון ימינה': (tester) async {
      await toggleFit(tester);
      await scrollDiagonally(tester, 80);
    },
    'התאמה לרוחב, אחרי גלילה באלכסון שמאלה': (tester) async {
      await toggleFit(tester);
      await scrollDiagonally(tester, -80);
    },
    'התאמה לעמוד שלם': (tester) async {
      await toggleFit(tester);
      await toggleFit(tester);
    },
    'תצוגת ספר': (tester) async {
      pdfBloc(tester).add(const SetLayoutMode(PdfLayoutMode.bookView));
      await frames(tester, 60);
    },
    'תצוגת ספר, התאמה לרוחב': (tester) async {
      pdfBloc(tester).add(const SetLayoutMode(PdfLayoutMode.bookView));
      await frames(tester, 60);
      await toggleFit(tester);
    },
  };

  for (final MapEntry(key: mode, value: apply) in modes.entries) {
    testWidgets('החלקה בלוח מגע עוברת מ-PDF לטאב הסמוך (issue #3355), $mode', (
      tester,
    ) async {
      final reader = await pumpReader(tester, currentTabIndex: 1);
      await apply(tester);
      await swipe(tester, 900);
      expect(reader.tabs.state.currentTabIndex, 0);
    });
  }

  testWidgets('PDF מוגדל: החלקה אופקית מזיזה את הדף ולא מעבירה טאב', (
    tester,
  ) async {
    final reader = await pumpReader(tester, currentTabIndex: 1);
    final controller = reader.pdf.pdfViewerController;
    await controller.setZoom(
      controller.centerPosition,
      controller.currentZoom * 2,
      duration: Duration.zero,
    );
    await tester.pump();
    final left = controller.visibleRect.left;
    await swipe(tester, 300);
    expect(reader.tabs.state.currentTabIndex, 1);
    expect(controller.visibleRect.left, isNot(closeTo(left, 1)));
  });

  testWidgets('החלקה בלוח מגע עוברת מטאב סמוך אל ה-PDF (issue #3355)', (
    tester,
  ) async {
    final reader = await pumpReader(tester, currentTabIndex: 0);
    await swipe(tester, -900);
    expect(reader.tabs.state.currentTabIndex, 1);
  });
}

Future<void> waitForPdf(WidgetTester tester, PdfBookTab tab) async {
  for (var i = 0; i < 150; i++) {
    final viewer = find.byType(PdfViewer);
    if (viewer.evaluate().isNotEmpty && tab.pdfViewerController.isReady) {
      final bloc = tester.element(viewer).read<PdfBookBloc>();
      if (bloc.state is PdfBookLoaded) break;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(tab.pdfViewerController.isReady, isTrue);
  await tester.pump(const Duration(milliseconds: 300));
}

/// כרטיסיית מפרשים קלה שנטענת סינכרונית — טאב אמיתי לכל דבר.
PdfCommentatorsTab _neighborTab() {
  final sourceTab = PdfBookTab(
    book: PdfBook(title: 'שכן', path: '/tmp/שכן.pdf'),
    pageNumber: 1,
  );
  sourceTab.pdfHeadings = PdfHeadings(
    bookTitle: 'שכן',
    headingsMap: {'פרק א': 1},
  );
  sourceTab.currentTitle.value = 'פרק א';
  sourceTab.currentTextLineNumber = 1;
  sourceTab.currentTextLineNumberEnd = 9;
  return PdfCommentatorsTab(sourceTab: sourceTab);
}

class _TabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #loadTabs) return <OpenedTab>[];
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

class _HistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _HistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc()
    : super(
        const PersonalNotesState(
          isLoading: false,
          bookId: '',
          locatedNotes: [],
          missingNotes: [],
          errorMessage: null,
          filteredLocatedNotes: [],
          filteredMissingNotes: [],
        ),
      ) {
    on<PersonalNotesEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
