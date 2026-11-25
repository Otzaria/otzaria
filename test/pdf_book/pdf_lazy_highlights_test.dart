import 'dart:async';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_page_highlight_anchor.dart';
import 'package:otzaria/pdf_book/utils/centered_text_search_session.dart';
import 'package:otzaria/pdf_book/utils/pdf_search_index_restorer.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _Page extends Fake implements PdfPage {
  _Page(this.pageNumber);
  @override
  final int pageNumber;
  bool loaded = true;
  @override
  bool get isLoaded => loaded;
  @override
  double get width => 100;
  @override
  double get height => 100;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
}

class _Document extends Fake implements PdfDocument {
  _Document(int count) : pages = [for (var i = 1; i <= count; i++) _Page(i)];
  final changes = StreamController<PdfDocumentEvent>.broadcast();
  @override
  Stream<PdfDocumentEvent> get events => changes.stream;
  @override
  final List<PdfPage> pages;
}

class _Controller extends PdfViewerController {
  _Controller(int pageCount) : pdf = _Document(pageCount);
  _Document pdf;
  final selections = <int>[];
  final centers = <Offset>[];
  int currentPage = 1;
  int? _plannedPage;
  Completer<void>? navigationGate;
  @override
  bool get isReady => true;
  @override
  PdfDocument get document => pdf;
  @override
  int? get pageNumber => currentPage;
  @override
  PdfViewerParams get params => const PdfViewerParams(
    matchTextColor: Colors.yellow,
    activeMatchTextColor: Colors.orange,
  );
  @override
  Size get viewSize => const Size(100, 100);
  @override
  Matrix4 get value => Matrix4.identity();
  @override
  PdfPageLayout get layout => PdfPageLayout(
    pageLayouts: [
      for (var i = 0; i < pdf.pages.length; i++)
        Rect.fromLTWH(0, i * 100, 100, 100),
    ],
    documentSize: Size(100, pdf.pages.length * 100),
  );
  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => task(pdf);
  @override
  Rect calcRectForRectInsidePage({
    required int pageNumber,
    required PdfRect rect,
  }) => Rect.fromLTRB(
    rect.left,
    pageNumber * 100 - rect.top,
    rect.right,
    pageNumber * 100 - rect.bottom,
  );
  @override
  Matrix4 calcMatrixFor(Offset position, {double? zoom, Size? viewSize}) {
    centers.add(position);
    _plannedPage = (position.dy / 100).floor() + 1;
    return Matrix4.identity();
  }

  @override
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    currentPage = _plannedPage ?? currentPage;
    await navigationGate?.future;
  }

  @override
  void setCurrentPageNumber(int pageNumber) {
    currentPage = pageNumber;
    selections.add(pageNumber);
  }

  @override
  void invalidate() {}
}

class _Session extends CenteredTextSearchSession {
  _Session(super.controller, {super.initialPageHighlight});
  final loadedPages = <int>[];
  final textByPage = <int, String>{};
  final gates = <int, Completer<PdfPageText?>>{};
  void Function(int)? onLoad;
  String defaultText = 'שלום עולם';

  PdfPageText text(int page) {
    final content = textByPage[page] ?? defaultText;
    return PdfPageText(
      pageNumber: page,
      fullText: content,
      charRects: [
        for (var i = 0; i < content.length; i++)
          PdfRect(i * 10.0, 100, (i + 1) * 10.0, 90),
      ],
      fragments: const [],
    );
  }

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    loadedPages.add(pageNumber);
    onLoad?.call(pageNumber);
    return gates[pageNumber]?.future ?? text(pageNumber);
  }
}

Future<void> _scanCompleted(PdfTextSearchSession session) async {
  final done = Completer<void>();
  void check() {
    if (!session.isSearching && !done.isCompleted) done.complete();
  }

  session.addListener(check);
  try {
    check();
    await done.future.timeout(const Duration(seconds: 30));
  } finally {
    session.removeListener(check);
  }
}

void _paint(_Session session, _Controller controller, int page) {
  final recorder = ui.PictureRecorder();
  session.pageTextMatchPaintCallback(
    Canvas(recorder),
    const Rect.fromLTWH(0, 0, 100, 100),
    controller.pdf.pages[page - 1],
  );
  recorder.endRecording().dispose();
}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _PdfBloc extends MockBloc<PdfBookEvent, PdfBookState>
    implements PdfBookBloc {}

class _Results extends SearchRepository {
  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async => [
    for (final page in [100, 5000, 9999])
      SearchResult(
        id: BigInt.from(page),
        title: 'ספר בדיקה',
        reference: 'עמוד $page',
        text: '<font>שלום</font> עולם',
        segment: BigInt.from(page - 1),
        isPdf: true,
        filePath: '/test.pdf',
        mergedCount: 1,
        merged: const [],
        textStatus: TextStatus.ok,
        continuesToNextLine: false,
      ),
  ];
}

Future<void> _pumpSearch(WidgetTester tester, _Session session) async {
  final settings = _SettingsBloc();
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final pdf = _PdfBloc();
  whenListen(
    pdf,
    const Stream<PdfBookState>.empty(),
    initialState: PdfBookLoaded(
      book: PdfBook(title: 'ספר בדיקה', path: '/test.pdf'),
      currentPageNumber: 1,
      totalPages: session.controller!.document.pages.length,
      isLoading: false,
    ),
  );
  when(() => pdf.state).thenAnswer(
    (_) => PdfBookLoaded(
      book: PdfBook(title: 'ספר בדיקה', path: '/test.pdf'),
      currentPageNumber: session.controller!.pageNumber!,
      totalPages: session.controller!.document.pages.length,
      isLoading: false,
    ),
  );
  final query = TextEditingController(text: 'שלום');
  final focus = FocusNode();
  addTearDown(settings.close);
  addTearDown(pdf.close);
  addTearDown(query.dispose);
  addTearDown(focus.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PdfBookBloc>.value(value: pdf),
        ],
        child: Scaffold(
          body: PdfBookSearchView(
            textSearcher: session,
            searchController: query,
            focusNode: focus,
            bookTitle: 'ספר בדיקה',
            bookTopics: 'תנך',
            pdfFilePath: '/test.pdf',
            initialSearchMode: SearchMode.fuzzy,
            initialSearchDistance: 2,
            searchRepository: _Results(),
          ),
        ),
      ),
    ),
  );
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();
  setUp(() async => Settings.init(cacheProvider: MemoryCacheProvider()));

  (_Controller, _Session) create([
    int count = 10,
    PdfPageHighlightAnchor? restore,
  ]) {
    final controller = _Controller(count);
    final session = _Session(controller, initialPageHighlight: restore);
    addTearDown(session.dispose);
    addTearDown(controller.pdf.changes.close);
    return (controller, session);
  }

  test('10,000 עמודים: חילוץ מלא קודם מול חילוץ עמוד נדרש אחד', () async {
    final (_, full) = create(10000);
    full.startTextSearch(
      RegExp('שלום'),
      goToFirstMatch: false,
      searchImmediately: true,
    );
    await _scanCompleted(full);
    final (_, lazy) = create(10000);
    lazy.startPageHighlights(RegExp('שלום'));
    final matches = await lazy.ensurePageHighlights(1);
    expect(full.loadedPages, hasLength(10000));
    expect(lazy.loadedPages, [1]);
    expect(matches!.single.text, full.matches.first.text);
    expect(matches.single.bounds, full.matches.first.bounds);
    // ignore: avoid_print
    print(
      'S12: text/geometry extractions 10000 -> ${lazy.loadedPages.length}; '
      'simple search retains ${full.matches.length} matches',
    );
  });

  test('עמוד שהאינדקס לא החזיר מודגש כשמציירים אותו', () async {
    final (controller, session) = create();
    session.startPageHighlights(RegExp('שלום'));
    await session.ensurePageHighlights(1);
    _paint(session, controller, 7);
    await session.ensurePageHighlights(7);
    expect(session.loadedPages, [1, 7]);
    expect(session.pageHighlights(7)!.single.pageNumber, 7);
    _paint(session, controller, 7);
    expect(session.loadedPages, [1, 7]);
  });

  test('הבא/הקודם מחוץ לחלונית סורקים רק עד ההתאמה הבאה', () async {
    final (controller, session) = create();
    session.defaultText = 'אין התאמה';
    session.textByPage[1] = 'שלום אחד';
    session.textByPage[4] = 'שלום ארבע';
    session.startPageHighlights(RegExp('שלום'));
    await session.ensurePageHighlights(1);
    final prepared = <int>[];
    await session.navigatePageHighlight(
      forward: true,
      beforeNavigate: prepared.add,
    );
    await session.navigatePageHighlight(
      forward: true,
      beforeNavigate: prepared.add,
    );
    expect(controller.selections, [1, 4]);
    expect(prepared, [1, 4]);
    expect(session.loadedPages, [1, 2, 3, 4]);
    await session.navigatePageHighlight(
      forward: false,
      beforeNavigate: prepared.add,
    );
    expect(controller.selections, [1, 4, 1]);
    expect(session.loadedPages, [1, 2, 3, 4]);
  });

  test('שאילתה חדשה בזמן אנימציה אינה מחזירה בחירה של ההדגשה הישנה', () async {
    final (controller, session) = create();
    session.startPageHighlights(RegExp('שלום'));
    final matches = (await session.ensurePageHighlights(1))!;
    controller.navigationGate = Completer();
    final navigation = session.goToPageHighlight(matches.single);
    await pumpEventQueue();
    session.startPageHighlights(RegExp('עולם'));
    controller.navigationGate!.complete();
    await navigation;
    expect(controller.selections, isEmpty);
  });

  test('לפני הבחירה הראשונה הבא/הקודם מתחילים בראש/בסוף הספר', () async {
    for (final forward in [true, false]) {
      final (controller, session) = create();
      controller.currentPage = 5;
      session.startPageHighlights(RegExp('שלום'));
      await session.ensurePageHighlights(5);
      await session.navigatePageHighlight(forward: forward);
      expect(controller.selections, [forward ? 1 : 10]);
      expect(session.loadedPages, [5, forward ? 1 : 10]);
    }
  });

  test('כשל חילוץ אינו מדלג מעל עמוד כאילו אין בו התאמה', () async {
    final (controller, session) = create();
    session.onLoad = (page) {
      if (page == 2) throw StateError('text extraction failed');
    };
    session.startPageHighlights(RegExp('שלום'));
    await session.navigatePageHighlight(forward: true);
    await session.navigatePageHighlight(forward: true);
    expect(controller.selections, [1]);
    expect(session.loadedPages, [1, 2]);
    session.onLoad = null;
    await session.navigatePageHighlight(forward: true);
    expect(controller.selections, [1, 2]);
  });

  test('שאילתה חדשה עוצרת ניווט שממתין לחילוץ, לפני העמוד הבא', () async {
    final (controller, session) = create();
    session.startPageHighlights(RegExp('שלום'));
    await session.navigatePageHighlight(forward: true);
    final gate = session.gates[2] = Completer();
    final navigation = session.navigatePageHighlight(forward: true);
    await pumpEventQueue();
    session.startPageHighlights(RegExp('עולם'));
    await navigation;
    gate.complete(session.text(2));
    await session.ensurePageHighlights(1);
    expect(controller.selections, [1]);
    expect(session.loadedPages, [1, 2, 1]);
  });

  test('טאב מוסתר אינו מחלץ טקסט, וגם תוצאה שהסתיימה באיחור נזרקת', () async {
    final (_, session) = create();
    final gate = session.gates[1] = Completer();
    session.startPageHighlights(RegExp('שלום'));
    final pending = session.ensurePageHighlights(1);
    await pumpEventQueue();
    session.isActive = false;
    expect(await pending, isNull);
    gate.complete(session.text(1));
    await pumpEventQueue();
    expect(session.pageHighlights(1), isNull);
    expect(await session.ensurePageHighlights(2), isNull);
    expect(session.loadedPages, [1]);
    session.isActive = true;
    expect(await session.ensurePageHighlights(2), isNotEmpty);
    expect(session.loadedPages, [1, 2]);
  });

  test('החלפת תוכן מסמך אינה מציירת הדגשות ישנות', () async {
    final (controller, session) = create();
    session.startPageHighlights(RegExp('שלום'));
    await session.ensurePageHighlights(1);
    session.textByPage[1] = 'תוכן חדש';
    controller.pdf.changes.add(
      PdfDocumentPageStatusChangedEvent(
        controller.pdf,
        changes: {
          1: PdfPageStatusChange.modified(page: controller.pdf.pages.first),
        },
      ),
    );
    await pumpEventQueue();
    expect(session.pageHighlights(1), isNull);
    expect(await session.ensurePageHighlights(1), isEmpty);
    expect(session.loadedPages, [1, 1]);
  });

  test('metadata של עמוד שטרם נטען אינו מבטל הדגשה שממתינה לו', () async {
    final (controller, session) = create();
    final page = controller.pdf.pages.first as _Page;
    page.loaded = false;
    session.onLoad = (_) {
      page.loaded = true;
      controller.pdf.changes.add(
        PdfDocumentPageStatusChangedEvent(
          controller.pdf,
          changes: {1: PdfPageStatusChange.modified(page: page)},
        ),
      );
    };
    session.startPageHighlights(RegExp('שלום'));
    expect(await session.ensurePageHighlights(1), isNotEmpty);
    expect(session.loadedPages, [1]);
  });

  test('שינוי תוכן פוסל בחירה גם אחרי פינוי הטקסט מהמטמון', () async {
    final (controller, session) = create();
    session.startPageHighlights('שלום');
    final matches = (await session.ensurePageHighlights(1))!;
    await session.goToPageHighlight(matches.single);
    session.releaseCachedText();
    expect(session.pageHighlightAnchor, isNotNull);
    controller.pdf.changes.add(
      PdfDocumentPageStatusChangedEvent(
        controller.pdf,
        changes: {
          1: PdfPageStatusChange.modified(page: controller.pdf.pages.first),
        },
      ),
    );
    await pumpEventQueue();
    expect(session.pageHighlightAnchor, isNull);
  });

  test('שחזור בעמוד שטרם נטען שורד metadata ראשונית בלבד', () async {
    final (controller, session) = create(
      10,
      const PdfPageHighlightAnchor(
        pageNumber: 1,
        start: 0,
        end: 4,
        query: 'שלום',
      ),
    );
    final page = controller.pdf.pages.first as _Page;
    page.loaded = false;
    session.onLoad = (_) {
      page.loaded = true;
      controller.pdf.changes.add(
        PdfDocumentPageStatusChangedEvent(
          controller.pdf,
          changes: {1: PdfPageStatusChange.modified(page: page)},
        ),
      );
    };
    session.startPageHighlights('שלום', query: 'שלום');
    await session.ensurePageHighlights(1);
    expect(session.pageHighlightAnchor!.start, 0);
    expect(session.loadedPages, [1]);
    controller.pdf.changes.add(
      PdfDocumentPageStatusChangedEvent(
        controller.pdf,
        changes: {1: PdfPageStatusChange.modified(page: page)},
      ),
    );
    await pumpEventQueue();
    expect(session.pageHighlightAnchor, isNull);
  });

  test(
    'שחזור חיפוש מתקדם שומר מיקום בלי לפרש אינדקס ישן כאינדקס מטמון',
    () async {
      final (controller, session) = create(10000);
      controller.currentPage = 7000;
      final restorer = PdfSearchIndexRestorer(5);
      session.addListener(() {
        final index = restorer.onSearcherUpdate(
          session: session.searchSession,
          isSearching: session.isSearching,
          matchCount: session.matches.length,
          hasCurrentMatch: session.currentIndex != null,
        );
        if (index != null) unawaited(session.goToMatchOfIndex(index));
      });
      session.startPageHighlights(RegExp('שלום'));
      await session.ensurePageHighlights(7000);
      expect(controller.currentPage, 7000);
      expect(controller.centers, isEmpty);
      expect(session.loadedPages, [7000]);
      expect(restorer.isPending, isFalse);
    },
  );

  test('חיפוש פשוט אחרי מתקדם ממשיך לסרוק את הספר כולו', () async {
    final (_, session) = create(30);
    session.startPageHighlights(RegExp('שלום'));
    await session.ensurePageHighlights(1);
    session.loadedPages.clear();
    session.startTextSearch(
      'עולם',
      goToFirstMatch: false,
      searchImmediately: true,
    );
    await _scanCompleted(session);
    expect(session.isPageHighlighting, isFalse);
    expect(session.loadedPages, hasLength(30));
    expect(session.matches, hasLength(30));
    expect(session.matches.every((match) => match.text == 'עולם'), isTrue);
  });

  test(
    'session חדש משחזר עוגן באותו עמוד וממשיך ממנו בלי סריקה מלאה',
    () async {
      final (firstController, first) = create(10000);
      firstController.currentPage = 7000;
      first.defaultText = 'שלום שלום';
      first.startPageHighlights('שלום', query: 'שלום');
      final matches = (await first.ensurePageHighlights(7000))!;
      await first.goToPageHighlight(matches.last);
      final anchor = first.pageHighlightAnchor!;
      first.releaseCachedText();
      expect(first.pageHighlightAnchor, same(anchor));
      final (controller, restored) = create(10000, anchor);
      controller.currentPage = 7000;
      restored.defaultText = 'שלום שלום';
      restored.startPageHighlights(null, query: 'שלום');
      restored.startPageHighlights('שלום', query: 'שלום');
      await restored.navigatePageHighlight(forward: true);
      expect(restored.loadedPages, [7000, 7001]);
      expect(controller.selections, [7001]);
      expect(restored.pageHighlightAnchor!.start, 0);
    },
  );

  test('שאילתה חדשה מבטלת עוגן משוחזר שעדיין ממתין לטקסט', () async {
    final (controller, session) = create(
      10000,
      const PdfPageHighlightAnchor(
        pageNumber: 7000,
        start: 0,
        end: 4,
        query: 'שלום',
      ),
    );
    final gate = session.gates[7000] = Completer();
    session.startPageHighlights('שלום', query: 'שלום');
    await pumpEventQueue();
    session.startPageHighlights(null, query: 'עולם');
    session.startPageHighlights('עולם', query: 'עולם');
    gate.complete(session.text(7000));
    await session.ensurePageHighlights(1);
    expect(session.pageHighlightAnchor, isNull);
    expect(session.loadedPages, [7000, 1]);
    expect(controller.selections, isEmpty);
  });

  testWidgets('חיפוש מתקדם בן שלוש תוצאות אינו מחלץ שוב 10,000 עמודים', (
    tester,
  ) async {
    final (controller, session) = create(10000);
    await _pumpSearch(tester, session);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.byType(SearchResultTile), findsNWidgets(3));
    expect(session.loadedPages, [1]);
    await tester.tap(find.byType(SearchResultTile).first);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(session.loadedPages, [1, 100]);
    expect(session.pageHighlights(100), isNotEmpty);
    expect(controller.selections, [100]);
  }, skip: !engineReady);

  testWidgets('שינוי תוכן בזמן הצגת תוצאה אינו בוחר הדגשה ישנה', (
    tester,
  ) async {
    final (controller, session) = create(100);
    await _pumpSearch(tester, session);
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
    }

    await settle();
    final gate = controller.navigationGate = Completer<void>();
    await tester.tap(find.byType(SearchResultTile).first);
    await settle();
    expect(session.pageHighlights(100), isNotEmpty);
    expect(controller.selections, isEmpty);
    session.textByPage[100] = 'תוכן מוחלף';
    controller.pdf.changes.add(
      PdfDocumentPageStatusChangedEvent(
        controller.pdf,
        changes: {
          100: PdfPageStatusChange.modified(page: controller.pdf.pages[99]),
        },
      ),
    );
    await settle();
    expect(session.pageHighlights(100), isNull);
    gate.complete();
    await settle();
    expect(controller.selections, isEmpty);
    expect(session.pageHighlightAnchor, isNull);
  }, skip: !engineReady);

  testWidgets('מעבר ממתקדם לפשוט אינו מפעיל בדיקת שכבת טקסט מוקדמת', (
    tester,
  ) async {
    final (_, session) = create(30);
    final oldPage = session.gates[1] = Completer();
    await _pumpSearch(tester, session);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(session.isPageHighlighting, isTrue);
    expect(session.loadedPages, [1]);
    session.loadedPages.clear();
    await tester.enterText(find.byType(EditableText), '/עולם/');
    oldPage.complete(session.text(1));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() => _scanCompleted(session));
    await tester.pump();
    expect(session.isPageHighlighting, isFalse);
    expect(session.loadedPages, hasLength(30));
    expect(session.matches, hasLength(30));
  }, skip: !engineReady);
}
