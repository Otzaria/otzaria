import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// ניתוב החיפוש בתוך ספר PDF: מרווח בין מילים (או כל תוספת אחרת) חייב לרוץ
/// במסלול המנוע, כי שכבת הטקסט של pdfrx מחפשת מחרוזת רצופה בלבד.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<_RecordingSearchRepository> pumpPdfSearch(
    WidgetTester tester, {
    required String query,
    required SearchMode searchMode,
    required int searchDistance,
    Map<String, Map<String, bool>> searchOptions = const {},
    SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
    ValueNotifier<ReadingTabSearchState?>? incomingSearchConfiguration,
    int? bookId,
    bool isUserBook = false,
    String? externalLibraryId,
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
      initialState: _loadedState(),
    );

    final searchController = TextEditingController(text: query);
    final focusNode = FocusNode();
    final textSearcher = PdfTextSearcher(_FakeReadyController());
    final repository = _RecordingSearchRepository();

    addTearDown(settingsBloc.close);
    addTearDown(pdfBookBloc.close);
    addTearDown(searchController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(textSearcher.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
          ],
          child: Scaffold(
            body: PdfBookSearchView(
              textSearcher: textSearcher,
              searchController: searchController,
              focusNode: focusNode,
              bookTitle: 'ספר בדיקה',
              bookTopics: 'תנך',
              bookId: bookId,
              isUserBook: isUserBook,
              externalLibraryId: externalLibraryId,
              pdfFilePath: '/nonexistent/test.pdf',
              initialSearchMode: searchMode,
              initialSearchDistance: searchDistance,
              initialSearchOptions: searchOptions,
              initialMatchPolicy: matchPolicy,
              incomingSearchConfiguration: incomingSearchConfiguration,
              searchRepository: repository,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return repository;
  }

  testWidgets('מרווח בין מילים במצב מדויק רץ במסלול המנוע', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
    );

    expect(repository.requests, isNotEmpty);
    expect(repository.requests.last.distance, 3);
    expect(repository.requests.last.query, 'תדע זרעך');

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  // הרגרסיה של issue #936: החלונית בנתה את ה-facet בלי מזהי הספר בעוד
  // האינדוקס משתמש בהם (id:/uid:/ext:) — מסלול המנוע החזיר תמיד "אין תוצאות"
  // לספר מזוהה, גם כשהחיפוש הגלובלי מצא בו התאמות.
  testWidgets('ה-facet של ספר עם מזהה נבנה עם מפתח id: כמו באינדוקס', (
    tester,
  ) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
      bookId: 12,
    );

    expect(repository.requests, isNotEmpty);
    expect(repository.requests.last.facets, ['/תנך/id:12']);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('ספר אישי עם מזהה מקבל מפתח uid:', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
      bookId: 7,
      isUserBook: true,
    );

    expect(repository.requests, isNotEmpty);
    expect(repository.requests.last.facets, ['/תנך/uid:7']);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('ספר מקטלוג חיצוני מקבל מפתח ext:', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
      externalLibraryId: 'HB_12345',
    );

    expect(repository.requests, isNotEmpty);
    expect(repository.requests.last.facets, ['/תנך/ext:HB_12345']);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('שאילתה בלי תוספות אינה פונה למנוע', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע',
      searchMode: SearchMode.exact,
      searchDistance: 0,
    );

    expect(repository.requests, isEmpty);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('אפשרות פר-מילה מעבירה למסלול המנוע', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע',
      searchMode: SearchMode.advanced,
      searchDistance: 0,
      searchOptions: const {
        'תדע_0': {'ראשי תיבות': true},
      },
    );

    expect(repository.requests, isNotEmpty);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('טווח קרבה ומצב התאמה עוברים אל בקשת המנוע', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.advanced,
      searchDistance: 0,
      matchPolicy: const SearchMatchPolicy(
        proximityScope: SearchScope.sameSection,
        wordMatchMode: WordMatchMode.mostWords,
      ),
    );

    expect(repository.requests, isNotEmpty);
    expect(repository.requests.last.scope, SearchScope.sameSection);
    expect(repository.requests.last.wordMatchMode, WordMatchMode.mostWords);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('איפוס החיפוש מחזיר את מדיניות ההתאמה לברירת המחדל', (
    tester,
  ) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.advanced,
      searchDistance: 0,
      matchPolicy: const SearchMatchPolicy(
        proximityScope: SearchScope.sameSection,
      ),
    );
    expect(repository.requests.last.scope, SearchScope.sameSection);

    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // אחרי איפוס, חיפוש חדש רץ במסלול הפשוט (בלי מדיניות) — כלומר
    // המדיניות אינה נשארת תלויה בטאב.
    final requestsAfterReset = repository.requests.length;
    await tester.enterText(find.byType(TextField).first, 'תדע');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repository.requests, hasLength(requestsAfterReset));

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('תצורה נכנסת לחלונית פתוחה רצה במסלול המנוע, לא בישן', (
    tester,
  ) async {
    // פתיחת תוצאת חיפוש גלובלי מורכב בספר PDF שכבר פתוח: החלונית קיימת
    // ומחזיקה תצורה פשוטה, ואסור שהשאילתה החדשה תרוץ איתה.
    final incoming = ValueNotifier<ReadingTabSearchState?>(null);
    addTearDown(incoming.dispose);

    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע',
      searchMode: SearchMode.exact,
      searchDistance: 0,
      incomingSearchConfiguration: incoming,
    );
    expect(repository.requests, isEmpty);

    incoming.value = const ReadingTabSearchState(
      searchText: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
      matchPolicy: SearchMatchPolicy(proximityScope: SearchScope.sameSection),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repository.requests, hasLength(1));
    expect(repository.requests.last.query, 'תדע זרעך');
    expect(repository.requests.last.distance, 3);
    expect(repository.requests.last.scope, SearchScope.sameSection);
    // ריקון המחוון מסמן לטאב שהחלונית קלטה את התצורה בעצמה.
    expect(incoming.value, isNull);

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);

  testWidgets('חזרה למצב מדויק בלי תוספות מחזירה למסלול הפשוט', (tester) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
    );
    expect(repository.requests, isNotEmpty);
    final requestsBeforeReset = repository.requests.length;

    tester
        .state<PdfBookSearchViewState>(find.byType(PdfBookSearchView))
        .applySearchDialogResult(
          const SearchDialogResult(
            query: 'תדע זרעך',
            searchOptions: {},
            alternativeWords: {},
            spacingValues: {},
            searchMode: SearchMode.exact,
            distance: 0,
          ),
          _MockPdfBookBloc(),
        );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      repository.requests,
      hasLength(requestsBeforeReset),
      reason: 'ללא תוספות אין לפנות למנוע שוב',
    );

    await tester.pump(const Duration(milliseconds: 800));
  }, skip: !engineReady);
}

class _SearchRequest {
  const _SearchRequest({
    required this.query,
    required this.distance,
    required this.scope,
    required this.wordMatchMode,
    required this.facets,
  });

  final String query;
  final int distance;
  final SearchScope scope;
  final WordMatchMode wordMatchMode;
  final List<String> facets;
}

class _RecordingSearchRepository extends SearchRepository {
  final List<_SearchRequest> requests = [];

  @override
  Future<List<SearchResult>> searchTexts(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    ResultsOrder order = ResultsOrder.relevance,
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    requests.add(
      _SearchRequest(
        query: query,
        distance: distance,
        scope: scope,
        wordMatchMode: wordMatchMode,
        facets: facets,
      ),
    );
    return const [];
  }
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPdfBookBloc extends MockBloc<PdfBookEvent, PdfBookState>
    implements PdfBookBloc {}

class _FakeDocument extends Fake implements PdfDocument {
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

/// קונטרולר "מוכן" בלי PdfViewer אמיתי — [PdfTextSearcher] דורש מסמך חי
/// בבנייה, ו-useDocument מוחזר null כדי שהחיפוש הפשוט לא יגע ב-pdfium.
class _FakeReadyController extends PdfViewerController {
  @override
  bool get isReady => true;

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

PdfBookLoaded _loadedState() => PdfBookLoaded(
  book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
  currentPageNumber: 1,
  totalPages: 10,
  isLoading: false,
);
