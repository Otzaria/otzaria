import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/search_pane_base.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/models/text_search_range.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

/// חלונית החיפוש בספר כשהשאילתה נושאת תוספות (מרווח בין מילים וכו'):
/// היא חייבת לרוץ במסלול המנוע ולא בחיפוש המחרוזת המקומי.
///
/// הצגת תוצאות מאצילה את ההדגשה למנוע הנייטיבי, ולכן טסטים שמציגים תוצאות
/// מדולגים כשאין build זמין.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });

  Future<_Harness> pumpSearchView(
    WidgetTester tester, {
    required SearchRepository searchRepository,
    String initialQuery = '',
    SearchMode searchMode = SearchMode.exact,
    int searchDistance = 0,
    SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
    List<String> content = const ['שורה א'],
    bool bookLoaded = true,
    Future<List<TextSearchResult>> Function(
      List<String>,
      String,
      TextSearchRange?,
    )?
    simpleSearchRunner,
    String bookTitle = 'ספר בדיקה',
  }) async {
    final textBookBloc = _TestTextBookBloc(
      bookLoaded
          ? _loadedState(content: content, bookTitle: bookTitle)
          : TextBookInitial.named(
              TextBook(title: bookTitle),
              0,
              true,
              const [],
            ),
    );
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final focusNode = FocusNode();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await textBookBloc.close();
      await settingsBloc.close();
      focusNode.dispose();
      await resetSectionSearchWorkerForTesting();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<TextBookBloc>.value(value: textBookBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(
            body: TextBookSearchView(
              contentLoader: () async => content,
              scrollControler: ItemScrollController(),
              focusNode: focusNode,
              closeLeftPaneCallback: () {},
              initialQuery: initialQuery,
              initialSearchMode: searchMode,
              initialSearchDistance: searchDistance,
              initialMatchPolicy: matchPolicy,
              simpleSearchRunner: simpleSearchRunner,
              searchRepository: searchRepository,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return _Harness(tester, textBookBloc);
  }

  testWidgets(
    'שאילתה עם מרווח בין מילים רצה במסלול המנוע ומציגה את התוצאות',
    (tester) async {
      // הרגרסיה: תוצאה שנפתחה מחיפוש "תדע זרעך" במרווח מילים הגיעה לספר
      // כשאילתה מדויקת במרווח 0, החיפוש המקומי חיפש מחרוזת רצופה, והחלונית
      // הציגה "אין תוצאות".
      final repository = _RecordingSearchRepository(
        results: [
          _result(title: 'בראשית', reference: 'בראשית, פרק טו', segment: 0),
        ],
      );
      var simpleRunnerCalls = 0;

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchDistance: 3,
        bookTitle: 'בראשית',
        content: const ['ויאמר לאברם ידע תדע כי־גר יהיה זרעך בארץ לא להם'],
        simpleSearchRunner: (content, query, range) async {
          simpleRunnerCalls++;
          return const [];
        },
      );

      await harness.settle();

      expect(simpleRunnerCalls, 0, reason: 'אסור ליפול למסלול המחרוזת המקומי');
      expect(repository.requests, hasLength(1));
      expect(repository.requests.single.query, 'תדע זרעך');
      expect(repository.requests.single.distance, 3);
      expect(find.text('אין תוצאות'), findsNothing);
      expect(find.text('בראשית, פרק טו'), findsOneWidget);
      expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);
    },
    skip: !engineReady,
  );

  testWidgets(
    'שאילתה בלי תוספות אינה פונה למנוע',
    (tester) async {
      final repository = _RecordingSearchRepository(results: const []);
      var simpleRunnerCalls = 0;

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע',
        simpleSearchRunner: (content, query, range) async {
          simpleRunnerCalls++;
          return const [];
        },
      );

      await harness.settle();

      expect(simpleRunnerCalls, greaterThan(0));
      expect(repository.requests, isEmpty);
    },
  );

  testWidgets(
    'חיפוש מנוע ממתין לזיהוי הספר במקום להציג "אין תוצאות"',
    (tester) async {
      // זיהוי הספר (facet) הוא אסינכרוני. חיפוש שנשלח לפני שהסתיים היה
      // מציג "אין תוצאות" ולא מנסה שוב.
      final libraryCompleter = Completer<Library>();
      DataRepository.instance.library = libraryCompleter.future;

      final repository = _RecordingSearchRepository(
        results: [
          _result(title: 'ספר בדיקה', reference: 'קטע ב', segment: 0),
        ],
      );

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchDistance: 2,
      );

      await harness.settle();
      expect(
        repository.requests,
        isEmpty,
        reason: 'הזיהוי עדיין לא הסתיים — אין עוד מה לשלוח למנוע',
      );

      libraryCompleter.complete(Library(categories: const []));
      await harness.settle();

      expect(repository.requests, hasLength(1));
      expect(find.text('קטע ב'), findsOneWidget);
      expect(find.text('אין תוצאות'), findsNothing);
    },
    skip: !engineReady,
  );

  testWidgets(
    'טווח "באותה פסקה" והתאמה חלקית עוברים אל בקשת המנוע',
    (tester) async {
      // בלי העברת מדיניות ההתאמה, חיפוש שנמצא "באותה פסקה" היה מתורגם בספר
      // לחיפוש מרווח-מילים ומחזיר תוצאות אחרות מאלה שהמשתמש ראה.
      final repository = _RecordingSearchRepository(
        results: [
          _result(title: 'ספר בדיקה', reference: 'קטע א', segment: 0),
        ],
      );

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchMode: SearchMode.advanced,
        matchPolicy: const SearchMatchPolicy(
          proximityScope: SearchScope.sameParagraph,
          wordMatchMode: WordMatchMode.atLeast,
          wordMatchCount: 2,
        ),
      );

      await harness.settle();

      expect(repository.requests, hasLength(1));
      final request = repository.requests.single;
      expect(request.scope, SearchScope.sameParagraph);
      expect(request.wordMatchMode, WordMatchMode.atLeast);
      expect(request.wordMatchCount, 2);
      expect(find.text('קטע א'), findsOneWidget);
    },
    skip: !engineReady,
  );

  testWidgets(
    'תוצאת מנוע מחוץ לחלון התוכן שנטען אינה נזרקת',
    (tester) async {
      // `state.content` הוא חלון חלקי סביב מקום הקריאה; תוצאה בשורה מאוחרת
      // ממנו נזרקה בעבר בהמרה והחלונית הציגה "אין תוצאות".
      final repository = _RecordingSearchRepository(
        results: [
          _result(title: 'ספר בדיקה', reference: 'קטע רחוק', segment: 500),
        ],
      );

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchDistance: 2,
        content: const ['שורה א'],
      );

      await harness.settle();

      expect(find.text('קטע רחוק'), findsOneWidget);
      expect(find.text('אין תוצאות'), findsNothing);
    },
    skip: !engineReady,
  );

  testWidgets(
    'החלונית משדרת ל-BLoC את שורות התוצאות (בסיס ההדגשה במדיניות)',
    (tester) async {
      // ההכרעה מי שורת תוצאה נשארת אצל המנוע: החלונית מדווחת את השורות,
      // והרינדור מדגיש מילה-מילה רק בהן.
      final repository = _RecordingSearchRepository(
        results: [
          _result(title: 'ספר בדיקה', reference: 'קטע א', segment: 3),
          _result(title: 'ספר בדיקה', reference: 'קטע ב', segment: 17),
        ],
      );

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchMode: SearchMode.advanced,
        matchPolicy: const SearchMatchPolicy(
          proximityScope: SearchScope.sameSection,
        ),
      );

      await harness.settle();

      final reported = harness.bloc.reportedResultLines;
      expect(reported, isNotEmpty);
      expect(reported.last, {3, 17});
    },
    skip: !engineReady,
  );

  testWidgets(
    'חיפוש בלי תוצאות משדר קבוצה ריקה, ולא משאיר שורות מאושרות ישנות',
    (tester) async {
      final repository = _RecordingSearchRepository(results: const []);

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchDistance: 2,
      );

      await harness.settle();

      expect(harness.bloc.reportedResultLines.last, isEmpty);
    },
    skip: !engineReady,
  );

  testWidgets(
    'כשל בזיהוי הספר מציג שגיאה, ואינו משאיר את החלונית במצב "מחפש"',
    (tester) async {
      // הספר עדיין נטען (ה-state אינו TextBookLoaded) ולכן אין ממה לבנות את
      // זיהוי הספר. לפני התיקון החלונית הציגה "אין תוצאות".
      final repository = _RecordingSearchRepository(
        results: [
          _result(title: 'ספר בדיקה', reference: 'קטע א', segment: 0),
        ],
      );

      final harness = await pumpSearchView(
        tester,
        searchRepository: repository,
        initialQuery: 'תדע זרעך',
        searchDistance: 2,
        bookLoaded: false,
      );

      await harness.settle();

      expect(repository.requests, isEmpty);
      expect(find.text(LibraryMessages.searchError), findsWidgets);
      expect(find.text('אין תוצאות'), findsNothing);
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'החלונית לא אמורה להישאר במצב "מחפש"',
      );

      // הספר נטען — חיפוש נוסף מנסה שוב ומצליח.
      harness.bloc.emitLoaded(_loadedState());
      await tester.pump();
      await harness.type('תדע זרעך ');
      await harness.settle();

      expect(repository.requests, hasLength(1));
      expect(find.text('קטע א'), findsOneWidget);
      expect(find.text(LibraryMessages.searchError), findsNothing);
    },
    skip: !engineReady,
  );
}

class _Harness {
  _Harness(this.tester, this.bloc);

  final WidgetTester tester;
  final _TestTextBookBloc bloc;

  /// מקליד שאילתה בשדה החיפוש.
  Future<void> type(String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
  }

  /// ממתין ל-debounce של שדה החיפוש, לזיהוי הספר ולסיום החיפוש. זיהוי הספר
  /// עובר דרך עבודה אסינכרונית אמיתית, ולכן נדרש [WidgetTester.runAsync].
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(
        kSearchFieldDebounce + const Duration(milliseconds: 50),
      );
    }
  }
}

SearchResult _result({
  required String title,
  required String reference,
  required int segment,
}) {
  return SearchResult(
    id: BigInt.from(segment + 1),
    title: title,
    reference: reference,
    text:
        'ידע <font color=red>תדע</font> כי־גר יהיה <font color=red>זרעך</font>',
    segment: BigInt.from(segment),
    isPdf: false,
    filePath: 'id:1',
    mergedCount: 1,
    merged: const [],
  );
}

/// בקשת חיפוש שנרשמה, לצורך אימות שהתוספות עברו למנוע.
class _SearchRequest {
  const _SearchRequest({
    required this.query,
    required this.facets,
    required this.distance,
    required this.searchMode,
    required this.fuzzy,
    required this.scope,
    required this.wordMatchMode,
    required this.wordMatchCount,
  });

  final String query;
  final List<String> facets;
  final int distance;
  final SearchMode searchMode;
  final bool fuzzy;
  final SearchScope scope;
  final WordMatchMode wordMatchMode;
  final int? wordMatchCount;
}

class _RecordingSearchRepository extends SearchRepository {
  _RecordingSearchRepository({required this.results});

  final List<SearchResult> results;
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
        facets: facets,
        distance: distance,
        searchMode: searchMode,
        fuzzy: fuzzy,
        scope: scope,
        wordMatchMode: wordMatchMode,
        wordMatchCount: wordMatchCount,
      ),
    );
    return results;
  }
}

TextBookLoaded _loadedState({
  List<String> content = const ['שורה א'],
  String bookTitle = 'ספר בדיקה',
}) {
  return TextBookLoaded(
    book: TextBook(title: bookTitle),
    showLeftPane: true,
    content: content,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {
      if (event is UpdateSearchResultLines) {
        reportedResultLines.add(event.lines);
      }
    });
  }

  /// מעבר לספר טעון, כמו סיום טעינת התוכן באפליקציה.
  void emitLoaded(TextBookLoaded state) => emit(state);

  final List<Set<int>> reportedResultLines = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
