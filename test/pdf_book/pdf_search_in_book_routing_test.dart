import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
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
    registerFallbackValue(const UpdateSearchOptions());
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
    BookSource source = BookSource.official,
    String? externalLibraryId,
    PdfBookTab? tab,
    PdfBookBloc? persistenceBloc,
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
      persistenceBloc?.stream ?? const Stream<PdfBookState>.empty(),
      initialState: persistenceBloc?.state ?? _loadedState(),
    );

    if (persistenceBloc != null) {
      when(() => pdfBookBloc.add(any())).thenAnswer((invocation) {
        persistenceBloc.add(
          invocation.positionalArguments.single as PdfBookEvent,
        );
      });
    }
    final searchController =
        tab?.searchController ?? TextEditingController(text: query);
    final focusNode = FocusNode();
    final textSearcher = PdfTextSearcher(_FakeReadyController());
    final repository = _RecordingSearchRepository()
      ..bloc = pdfBookBloc
      ..textSearcher = textSearcher;

    addTearDown(settingsBloc.close);
    addTearDown(pdfBookBloc.close);
    if (tab == null) addTearDown(searchController.dispose);
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
              source: source,
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

  testWidgets(
    'איפוס במסכת PDF מצורפת משמר חיפוש מקומי עם ברירות מחדל מתקדמות',
    (tester) async {
      SearchDefaults.saveModeDefault(SearchMode.advanced);
      SearchDefaults.saveDistanceDefault(3);
      SearchDefaults.saveDefaults({'קידומות': true, 'ראשי תיבות': true});
      addTearDown(() {
        SearchDefaults.saveModeDefault(SearchMode.exact);
        SearchDefaults.saveDistanceDefault(0);
        SearchDefaults.saveDefaults({});
      });
      final repository = await pumpPdfSearch(
        tester,
        query: 'תדע',
        searchMode: SearchMode.exact,
        searchDistance: 0,
        externalLibraryId: 'talmud-pdf:ברכות',
      );
      expect(repository.textSearcher.pattern, isA<RegExp>());
      expect(
        find.text(PdfMessages.advancedSearchUnavailableInTalmudPdf),
        findsNothing,
      );

      await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
      await tester.pump(const Duration(milliseconds: 800));
      final reset = verify(
        () => repository.bloc.add(captureAny(that: isA<UpdateSearchOptions>())),
      ).captured.cast<UpdateSearchOptions>().last;
      expect(reset.searchMode, SearchMode.exact);
      expect(reset.searchDistance, 0);
      expect(reset.searchOptions, isEmpty);
      expect(reset.matchPolicy, SearchMatchPolicy.standard);

      await tester.enterText(find.byType(TextField).first, 'זרעך');
      await tester.pump(const Duration(milliseconds: 800));
      expect(repository.requests, isEmpty);
      expect(
        find.text(PdfMessages.advancedSearchUnavailableInTalmudPdf),
        findsNothing,
      );
      expect(repository.textSearcher.pattern, isA<RegExp>());
      expect(
        (repository.textSearcher.pattern as RegExp).hasMatch('זרעך'),
        isTrue,
      );
    },
  );

  testWidgets('ברירות מחדל ומפות המילים נשמרות בטאב PDF ובחלונית משוחזרת', (
    tester,
  ) async {
    SearchDefaults.saveModeDefault(SearchMode.advanced);
    SearchDefaults.saveDistanceDefault(3);
    const wordOptions = {'קידומות': true, 'ראשי תיבות': true};
    SearchDefaults.saveDefaults(wordOptions);
    addTearDown(() {
      SearchDefaults.saveModeDefault(SearchMode.exact);
      SearchDefaults.saveDistanceDefault(0);
      SearchDefaults.saveDefaults({});
    });
    final tab = PdfBookTab(book: _loadedState().book, pageNumber: 1);
    final persistenceBloc = PdfBookBloc(
      tab: tab,
      initialState: PdfBookInitial(book: tab.book, initialPageNumber: 1),
      pdfrxInit: () async {},
    );
    // המצב הטעון מבודד את שמירת החיפוש מטעינת מסמך PDF אמיתי.
    // ignore: invalid_use_of_visible_for_testing_member
    persistenceBloc.emit(_loadedState());
    addTearDown(persistenceBloc.close);
    addTearDown(tab.dispose);
    final repository = await pumpPdfSearch(
      tester,
      query: '',
      searchMode: SearchMode.exact,
      searchDistance: 0,
      tab: tab,
      persistenceBloc: persistenceBloc,
    );
    expect(tab.searchMode, SearchMode.advanced);
    expect(tab.searchDistance, 3);
    expect(repository.requests, isEmpty);

    await tester.enterText(find.byType(TextField).first, 'תדע זרעך');
    await tester.pump(const Duration(milliseconds: 800));
    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.searchMode, SearchMode.advanced);
    expect(repository.requests.single.distance, 3);
    expect(repository.requests.single.searchOptions, {
      'תדע_0': wordOptions,
      'זרעך_1': wordOptions,
    });
    expect(tab.searchOptions, repository.requests.single.searchOptions);

    await tester.enterText(find.byType(TextField).first, 'זרעך אחריך');
    await tester.pump(const Duration(milliseconds: 800));
    expect(repository.requests, hasLength(2));
    const expectedOptions = {'זרעך_0': wordOptions, 'אחריך_1': wordOptions};
    expect(repository.requests.last.searchOptions, expectedOptions);
    expect(tab.searchOptions, expectedOptions);
    final updates = verify(
      () => repository.bloc.add(captureAny(that: isA<UpdateSearchOptions>())),
    ).captured.cast<UpdateSearchOptions>();
    expect(updates, hasLength(3));
    expect(updates.last.searchOptions, expectedOptions);

    final restored = PdfBookTab.fromJson(tab.toJson());
    addTearDown(restored.dispose);
    expect(restored.searchController.text, 'זרעך אחריך');
    expect(restored.searchMode, SearchMode.advanced);
    expect(restored.searchDistance, 3);
    expect(restored.searchOptions, expectedOptions);
    SearchDefaults.saveModeDefault(SearchMode.exact);
    SearchDefaults.saveDistanceDefault(0);
    SearchDefaults.saveDefaults({});
    await tester.pumpWidget(const SizedBox.shrink());
    final reopened = await pumpPdfSearch(
      tester,
      query: restored.searchController.text,
      searchMode: restored.searchMode,
      searchDistance: restored.searchDistance,
      searchOptions: restored.searchOptions,
      tab: restored,
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(reopened.requests, hasLength(1));
    expect(reopened.requests.single.query, 'זרעך אחריך');
    expect(reopened.requests.single.searchMode, SearchMode.advanced);
    expect(reopened.requests.single.distance, 3);
    expect(reopened.requests.single.searchOptions, expectedOptions);
  }, skip: !engineReady);

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

  // issue #1937: ברירת מחדל שנשמרה מחלון החיפוש לא חלה על חיפוש בספר.
  testWidgets('מרווח שנקבע כברירת מחדל חל על הקלדה בספר PDF', (tester) async {
    SearchDefaults.saveDistanceDefault(3);
    addTearDown(() => SearchDefaults.saveDistanceDefault(0));
    final repository = await pumpPdfSearch(
      tester,
      query: '',
      searchMode: SearchMode.exact,
      searchDistance: 0,
    );

    await tester.enterText(find.byType(TextField).first, 'תדע זרעך');
    await tester.pump(const Duration(milliseconds: 800));

    expect(repository.requests, isNotEmpty);
    expect(repository.requests.last.distance, 3);
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
      source: BookSource.user,
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

  // מסכת PDF מצורפת מוחרגת מהאינדוקס בכוונה, ולכן מסלול המנוע בה החזיר
  // "אין תוצאות" גנרי במקום להסביר שהחיפוש המתקדם אינו זמין במהדורה הזו.
  testWidgets('מסכת PDF מצורפת: מסלול המנוע מציג הודעה במקום ריק', (
    tester,
  ) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'תדע זרעך',
      searchMode: SearchMode.exact,
      searchDistance: 3,
      externalLibraryId: 'talmud-pdf:ברכות',
    );

    expect(repository.requests, isEmpty);
    expect(
      find.text(PdfMessages.advancedSearchUnavailableInTalmudPdf),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('תוצאה מחיפוש חכם במסכת מצורפת מחפשת בשכבת הטקסט', (
    tester,
  ) async {
    final repository = await pumpPdfSearch(
      tester,
      query: 'מאימתי',
      searchMode: SearchMode.fuzzy,
      searchDistance: 0,
      matchPolicy: SearchMatchPolicy.smart,
      externalLibraryId: 'talmud-pdf:ברכות',
    );
    expect(repository.requests, isEmpty);
    expect(
      find.text(PdfMessages.advancedSearchUnavailableInTalmudPdf),
      findsNothing,
    );
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
    required this.searchMode,
    required this.searchOptions,
  });

  final String query;
  final int distance;
  final SearchScope scope;
  final WordMatchMode wordMatchMode;
  final List<String> facets;
  final SearchMode searchMode;
  final Map<String, Map<String, bool>>? searchOptions;
}

class _RecordingSearchRepository extends SearchRepository {
  final List<_SearchRequest> requests = [];
  late PdfBookBloc bloc;
  late PdfTextSearcher textSearcher;

  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async {
    requests.add(
      _SearchRequest(
        query: request.query,
        distance: request.distance,
        scope: request.scope,
        wordMatchMode: request.wordMatchMode,
        facets: request.facets,
        searchMode: request.searchMode,
        searchOptions: request.searchOptions,
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

  // קונטרולר אמיתי מוכן תמיד מחזיר עמוד; זה אינו מחובר לצפיין.
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

PdfBookLoaded _loadedState() => PdfBookLoaded(
  book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
  currentPageNumber: 1,
  totalPages: 10,
  isLoading: false,
);
