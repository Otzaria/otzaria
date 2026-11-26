import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPdfBookBloc extends MockBloc<PdfBookEvent, PdfBookState>
    implements PdfBookBloc {}

class _FakeDocument extends Fake implements PdfDocument {
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _FakeReadyController extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  int? get pageNumber => null;

  @override
  PdfDocument get document => _FakeDocument();

  @override
  void invalidate() {}

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => null;
}

/// מצב סריקה והתאמות נשלטים מהבדיקה; פעולות הניווט נרשמות.
class _ControlledSearcher extends PdfTextSearchSession {
  _ControlledSearcher(super.controller);

  List<PdfTextSearchResult> current = const [];
  bool scanning = false;
  double progress = 1;
  int? index;
  final actions = <String>[];

  @override
  List<PdfTextSearchResult> get matches => current;

  @override
  bool get isSearching => scanning;

  @override
  double get searchProgress => scanning ? 0.5 : progress;

  @override
  int? get currentIndex => index;

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
    int? startPageNumber,
  }) {}

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => PdfPageText(
    pageNumber: pageNumber,
    fullText: 'שלום עולם',
    charRects: const [],
    fragments: const [],
  );

  @override
  Future<int> goToNextMatch() async {
    actions.add('next');
    return 0;
  }

  @override
  Future<int> goToPrevMatch() async {
    actions.add('prev');
    return 0;
  }

  @override
  Future<int> goToMatchOfIndex(int index) async {
    actions.add('match:$index');
    this.index = index;
    return index;
  }

  @override
  void stopTextSearch() {
    actions.add('stop');
    progress = searchProgress;
    scanning = false;
    notifyListeners();
  }
}

class _CountedMatch extends Fake implements PdfTextSearchResult {
  _CountedMatch(this.pageNumber, this.text, {this.start = 0});

  @override
  final int pageNumber;
  @override
  final String text;
  int snippetReads = 0;

  @override
  final int start;
  @override
  int get end => start + 4;
  @override
  int get contextStart => start;
  @override
  int get pageTextLength => start + text.length;
  @override
  String get contextText {
    snippetReads++;
    return text;
  }
}

class _InvalidCountedMatch extends _CountedMatch {
  _InvalidCountedMatch(super.pageNumber, super.text);

  @override
  int get end => 10000;
}

PdfTextSearchResult _match(int page) => PdfTextSearchResult.fromRange(
  PdfPageTextRange(
    pageText: PdfPageText(
      pageNumber: page,
      fullText: 'שלום עולם',
      charRects: List.filled(9, const PdfRect(0, 1, 1, 0)),
      fragments: const [],
    ),
    start: 0,
    end: 4,
  ),
);

Future<_ControlledSearcher> _pump(
  WidgetTester tester, {
  ValueChanged<int>? onNavigationStarted,
}) async {
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final pdfBookBloc = _MockPdfBookBloc();
  whenListen(
    pdfBookBloc,
    const Stream<PdfBookState>.empty(),
    initialState: PdfBookLoaded(
      book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
      currentPageNumber: 1,
      totalPages: 12,
      isLoading: false,
    ),
  );
  final searchController = TextEditingController(text: 'שלום');
  final focusNode = FocusNode();
  final searcher = _ControlledSearcher(_FakeReadyController());
  addTearDown(settingsBloc.close);
  addTearDown(pdfBookBloc.close);
  addTearDown(searchController.dispose);
  addTearDown(focusNode.dispose);
  addTearDown(searcher.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
        ],
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: PdfBookSearchView(
              textSearcher: searcher,
              searchController: searchController,
              focusNode: focusNode,
              pdfFilePath: '/nonexistent/test.pdf',
              onNavigationStarted: onNavigationStarted,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return searcher;
}

Future<void> _notify(WidgetTester tester, _ControlledSearcher s) async {
  s.notifyListeners();
  await tester.pump();
  await tester.pump();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('סרגל התוצאות בחיפוש הפשוט', () {
    testWidgets('התקדמות חיפוש ישן בזמן debounce שומרת את שאילתת ההקשר שלו', (
      tester,
    ) async {
      final searcher = await _pump(tester);
      searcher
        ..scanning = true
        ..current = [_match(1)];
      await _notify(tester, searcher);
      await tester.enterText(find.byType(EditableText), 'שאילתה חדשה');
      await tester.pump(const Duration(milliseconds: 100));
      searcher.current = [...searcher.current, _InvalidCountedMatch(2, 'קצר')];
      await _notify(tester, searcher);
      final tile = tester
          .widgetList<SearchResultTile>(find.byType(SearchResultTile))
          .singleWhere((tile) => tile.result.segment == BigInt.one);
      expect(tile.result.text, 'שלום');
      await tester.pump(const Duration(milliseconds: 300));
      searcher.current = [_InvalidCountedMatch(2, 'קצר')];
      await _notify(tester, searcher);
      final updated = tester.widget<SearchResultTile>(
        find.byType(SearchResultTile),
      );
      expect(updated.result.text, 'שאילתה חדשה');
    });

    testWidgets('wrap משמר קטעי הקשר וכרטיסים ומנווט לאינדקס העדכני', (
      tester,
    ) async {
      final searcher = await _pump(tester);
      final page5 = _CountedMatch(5, 'שלום בעמוד החמישי');
      final page5b = _CountedMatch(5, 'שלום נוסף בעמוד החמישי', start: 30);
      searcher
        ..scanning = true
        ..current = [page5, page5b];
      await _notify(tester, searcher);
      final original = tester
          .widgetList<SearchResultTile>(find.byType(SearchResultTile))
          .toList();
      expect(original, hasLength(2));
      expect(page5.snippetReads, 1);
      expect(page5b.snippetReads, 1);

      final page1 = _CountedMatch(1, 'שלום בעמוד הראשון');
      searcher.current = [page1, page5, page5b];
      await _notify(tester, searcher);
      final afterWrap = tester
          .widgetList<SearchResultTile>(find.byType(SearchResultTile))
          .toList();
      expect(afterWrap, hasLength(3));
      expect(afterWrap[1].result, same(original[0].result));
      expect(afterWrap[2].result, same(original[1].result));
      expect(page5.snippetReads, 1);
      expect(page5b.snippetReads, 1);

      // ה-searcher יכול להתקדם בין הודעות ה-progress ובין build ללחיצה.
      searcher.current = [
        page1,
        _CountedMatch(3, 'שלום בשלישי'),
        page5,
        page5b,
      ];
      afterWrap[2].onTap();
      await tester.pump();
      expect(searcher.actions, ['match:3']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('פרסום אלפי התאמות בונה הקשרים רק לכרטיסים שנדרשים', (
      tester,
    ) async {
      final searcher = await _pump(tester);
      final matches = List.generate(
        1000,
        (i) => _CountedMatch(i + 1, 'שלום בעמוד ${i + 1}'),
      );
      searcher
        ..scanning = true
        ..current = matches;
      await _notify(tester, searcher);
      final reads = matches.fold<int>(
        0,
        (sum, match) => sum + match.snippetReads,
      );
      expect(reads, greaterThan(0));
      expect(reads, lessThan(100));
      expect(
        find.text(PdfMessages.partialSearchResultCount(1000)),
        findsOneWidget,
      );
      searcher.scanning = false;
      await _notify(tester, searcher);
      expect(
        matches.fold<int>(0, (sum, match) => sum + match.snippetReads),
        lessThan(100),
      );
    });

    testWidgets('נקודת החזרה נשמרת לפני ניווט לתוצאה הבאה', (tester) async {
      late _ControlledSearcher searcher;
      final targets = <int>[];
      searcher = await _pump(
        tester,
        onNavigationStarted: (page) {
          expect(searcher.actions, isEmpty);
          targets.add(page);
        },
      );
      searcher
        ..current = [_match(2), _match(3), _match(5)]
        ..index = 0;
      await _notify(tester, searcher);
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      expect(targets, [3]);
      expect(searcher.actions, ['next']);
    });

    testWidgets('בזמן סריקה — כפתור עצירה שעוצר את ה-searcher', (tester) async {
      final searcher = await _pump(tester);
      searcher
        ..scanning = true
        ..current = [_match(2)];
      await _notify(tester, searcher);

      await tester.tap(find.byTooltip('עצור את החיפוש'));
      expect(searcher.actions, ['stop']);
    });

    testWidgets('תוצאות חלקיות נשארות זמינות לניווט אחרי עצירה', (
      tester,
    ) async {
      final searcher = await _pump(tester);
      searcher
        ..scanning = true
        ..current = [_match(2), _match(3)]
        ..index = 0;
      await _notify(tester, searcher);
      expect(
        find.text(PdfMessages.currentPartialSearchResult(1, 2)),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('עצור את החיפוש'));
      await tester.pump();
      expect(
        find.text(PdfMessages.currentPartialSearchResult(1, 2)),
        findsOneWidget,
      );
      expect(find.byTooltip('עצור את החיפוש'), findsNothing);
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      expect(searcher.actions, ['stop', 'next']);
    });

    testWidgets('אחרי הסריקה — אין עצירה; הבאה/הקודמת לפי המיקום', (
      tester,
    ) async {
      final searcher = await _pump(tester);
      searcher
        ..current = [_match(2), _match(3), _match(5)]
        ..index = 0;
      await _notify(tester, searcher);

      expect(find.byTooltip('עצור את החיפוש'), findsNothing);
      expect(find.text('תוצאה 1 מתוך 3'), findsOneWidget);

      await tester.tap(find.byTooltip('התוצאה הקודמת'));
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      expect(searcher.actions, ['next']);
    });

    testWidgets('בלי תוצאות ובלי סריקה — אין סרגל', (tester) async {
      final searcher = await _pump(tester);
      await _notify(tester, searcher);
      expect(find.byTooltip('התוצאה הבאה'), findsNothing);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  testWidgets('טעינה חוזרת מעבירה את מאזין התוצאות ל-searcher החדש', (
    tester,
  ) async {
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    final pdfBookBloc = _MockPdfBookBloc();
    whenListen(
      pdfBookBloc,
      const Stream<PdfBookState>.empty(),
      initialState: PdfBookLoaded(
        book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
        currentPageNumber: 1,
        totalPages: 12,
        isLoading: false,
      ),
    );
    final searchController = TextEditingController();
    final focusNode = FocusNode();
    final controller = _FakeReadyController();
    final first = _ControlledSearcher(controller);
    final second = _ControlledSearcher(controller);
    addTearDown(settingsBloc.close);
    addTearDown(pdfBookBloc.close);
    addTearDown(searchController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget view(
      _ControlledSearcher searcher, {
      List<PdfOutlineNode>? outline,
      String? bookTitle,
    }) => MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
        ],
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: PdfBookSearchView(
              textSearcher: searcher,
              searchController: searchController,
              focusNode: focusNode,
              outline: outline,
              bookTitle: bookTitle,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(first));
    first.current = [_match(2)];
    await _notify(tester, first);
    expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);

    await tester.pumpWidget(view(second));
    final page3 = _match(3);
    second.current = [page3];
    await _notify(tester, second);
    expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);

    second.current = [page3, _match(4)];
    await _notify(tester, second);
    expect(find.text('נמצאו 2 תוצאות'), findsOneWidget);
    expect(find.text('עמוד 3'), findsOneWidget);
    expect(find.text('עמוד 4'), findsOneWidget);

    final outline = [
      PdfOutlineNode(
        title: ' שער ',
        dest: PdfDest(4, PdfDestCommand.fit, null),
        children: const [],
      ),
    ];
    await tester.pumpWidget(view(second, outline: outline));
    expect(find.text('עמוד 3'), findsOneWidget);
    expect(find.text('שער'), findsOneWidget);
    expect(find.text('עמוד 4'), findsNothing);

    await tester.pumpWidget(view(second, outline: outline, bookTitle: 'שער'));
    expect(find.text('שער'), findsNothing);
    expect(find.text('עמוד 4'), findsOneWidget);

    await tester.pumpWidget(view(second));
    expect(find.text('עמוד 4'), findsOneWidget);
  });
}
