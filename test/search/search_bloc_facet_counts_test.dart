import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  group('סינון צד-לקוח בלחיצת קטגוריה — פונקציות ההכלה', () {
    test('facetContains: שורש מכיל הכל, נתיב מכיל תת-נתיב ואת עצמו', () {
      expect(SearchBloc.facetContains('/', '/תנך/תורה'), isTrue);
      expect(SearchBloc.facetContains('/תנך', '/תנך/תורה'), isTrue);
      expect(SearchBloc.facetContains('/תנך', '/תנך'), isTrue);
      expect(SearchBloc.facetContains('/תנך', '/תנך-אחר'), isFalse);
      expect(SearchBloc.facetContains('/תנך/תורה', '/תנך'), isFalse);
    });

    test('isFacetNarrowing: צמצום בלבד מול הרחבה', () {
      expect(SearchBloc.isFacetNarrowing(['/'], ['/תנך']), isTrue);
      expect(SearchBloc.isFacetNarrowing(['/תנך'], ['/תנך/תורה']), isTrue);
      // הסרת facet מרשימה = תת-קבוצה של ההיקף הקודם
      expect(SearchBloc.isFacetNarrowing(['/תנך', '/הלכה'], ['/תנך']), isTrue);
      // הרחבה: facet מחוץ להיקף
      expect(SearchBloc.isFacetNarrowing(['/תנך'], ['/הלכה']), isFalse);
      expect(SearchBloc.isFacetNarrowing(['/תנך/תורה'], ['/תנך']), isFalse);
      expect(SearchBloc.isFacetNarrowing(['/'], []), isFalse);
    });
  });

  group('SearchBloc facet counts', () {
    blocTest<SearchBloc, SearchState>(
      'SetSearchMode מעדכן את מצב החיפוש ומפעיל ריענון שאילתה',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(SetSearchMode(SearchMode.fuzzy)),
      expect: () => [
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.fuzzy),
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.fuzzy),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מעביר ממתקדם למדויק',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.exact);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מעביר ממדויק למקורב',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(searchMode: SearchMode.exact),
      ),
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.fuzzy);
        expect(bloc.state.configuration.distance, 2);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מעביר ממקורב למתקדם',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(searchMode: SearchMode.fuzzy),
      ),
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.advanced);
        expect(bloc.state.configuration.distance, 0);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'SetSearchMode שומר מרחק ידני שהמשתמש בחר',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(
          searchMode: SearchMode.exact,
          distance: 6,
        ),
      ),
      act: (bloc) => bloc.add(SetSearchMode(SearchMode.fuzzy)),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.fuzzy);
        expect(bloc.state.configuration.distance, 6);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'ToggleSearchMode מחליף לברירת המחדל של fuzzy רק כשלא היה מרחק ידני',
      build: SearchBloc.new,
      seed: () => const SearchState(
        configuration: SearchConfiguration(
          searchMode: SearchMode.exact,
          distance: 0,
        ),
      ),
      act: (bloc) => bloc.add(ToggleSearchMode()),
      verify: (bloc) {
        expect(bloc.state.configuration.searchMode, SearchMode.fuzzy);
        expect(bloc.state.configuration.distance, 2);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'SetSearchMode יכול לעבור ממצב מתקדם למדויק באירוע יחיד',
      build: SearchBloc.new,
      seed: () => SearchState(
        configuration: const SearchConfiguration(
          searchMode: SearchMode.advanced,
        ),
      ),
      act: (bloc) => bloc.add(SetSearchMode(SearchMode.exact)),
      expect: () => [
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.exact),
        isA<SearchState>().having((state) => state.configuration.searchMode,
            'searchMode', SearchMode.exact),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetSearchModeWithoutSearch מעדכן מצב חיפוש בלי ריענון שאילתה',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(SetSearchModeWithoutSearch(SearchMode.fuzzy)),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.configuration.searchMode, 'searchMode',
                SearchMode.fuzzy)
            .having((state) => state.configuration.distance, 'distance', 2),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'UpdateDistanceWithoutSearch מעדכן מרחק בלי ריענון שאילתה',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(UpdateDistanceWithoutSearch(4)),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.configuration.distance, 'distance', 4),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'UpdateFacetCounts ממזג עדכונים נקודתיים לקאש',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/א': 1}));
        bloc.add(UpdateFacetCounts({'/ב': 2}));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 1)
            .having((state) => state.facetCounts['/א'], '/א', 1),
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 2)
            .having((state) => state.facetCounts['/א'], '/א', 1)
            .having((state) => state.facetCounts['/ב'], '/ב', 2),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ReplaceFacetCounts מחליף אגרגציה מלאה ומסיר מפתחות ישנים',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/ישן': 1, '/נשאר': 2}));
        bloc.add(ReplaceFacetCounts({'/נשאר': 3}, requestId: 0));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 2)
            .having((state) => state.facetCounts['/ישן'], '/ישן', 1)
            .having((state) => state.facetCounts['/נשאר'], '/נשאר', 2),
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 1)
            .having((state) => state.facetCounts['/ישן'], '/ישן', isNull)
            .having((state) => state.facetCounts['/נשאר'], '/נשאר', 3),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ReplaceFacetCounts עם requestId ישן (מחיפוש שהוחלף) נזרק ולא דורס',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/עדכני': 5}));
        // requestId שלא תואם את החיפוש הנוכחי (0) — מדמה ספירות שחושבו
        // עבור חיפוש קודם והגיעו באיחור.
        bloc.add(ReplaceFacetCounts({'/ישן': 1}, requestId: 99));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts['/עדכני'], '/עדכני', 5),
        // אין state נוסף — ה-ReplaceFacetCounts הישן לא גרם ל-emit.
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'ניקוי query מאפס גם את facetCounts',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(UpdateFacetCounts({'/א': 1}));
        bloc.add(UpdateSearchQuery(''));
      },
      expect: () => [
        isA<SearchState>()
            .having((state) => state.facetCounts.length, 'length', 1)
            .having((state) => state.facetCounts['/א'], '/א', 1),
        isA<SearchState>()
            .having((state) => state.searchQuery, 'searchQuery', '')
            .having((state) => state.facetCounts.isEmpty, 'facetCounts empty',
                true),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetFacetsWithoutSearch מעדכן גם currentFacets וגם searchScopeFacets',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(const SetFacetsWithoutSearch(['/תנ"ך'])),
      expect: () => [
        isA<SearchState>().having(
            (state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך'
        ]).having((state) => state.searchScopeFacets, 'searchScopeFacets', [
          '/תנ"ך'
        ]).having((state) => state.hasScopedFacetFilter, 'hasScopedFacetFilter',
            true),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetFacet משנה פילטר נוכחי אבל שומר על טווח החיפוש המקורי',
      build: SearchBloc.new,
      act: (bloc) {
        bloc.add(const SetFacetsWithoutSearch(['/תנ"ך']));
        bloc.add(SetFacet('/תנ"ך/ראשונים'));
      },
      expect: () => [
        isA<SearchState>().having(
            (state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך'
        ]).having(
            (state) => state.searchScopeFacets, 'searchScopeFacets', ['/תנ"ך']),
        isA<SearchState>().having(
            (state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך/ראשונים'
        ]).having(
            (state) => state.searchScopeFacets, 'searchScopeFacets', ['/תנ"ך']),
        isA<SearchState>()
            .having((state) => state.isLoading, 'isLoading', false)
            .having((state) => state.searchQuery, 'searchQuery', '')
            .having((state) => state.currentFacets, 'currentFacets', [
          '/תנ"ך/ראשונים'
        ]).having((state) => state.searchScopeFacets, 'searchScopeFacets',
                ['/תנ"ך']),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'SetFacetsWithoutSearch עם בחירה ריקה מסמן שלא נבחרו קטגוריות',
      build: SearchBloc.new,
      act: (bloc) => bloc.add(const SetFacetsWithoutSearch([])),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.currentFacets, 'currentFacets', []).having(
                (state) => state.searchScopeFacets,
                'searchScopeFacets',
                []).having((state) => state.hasNoSelectedFacets, 'hasNoSelectedFacets', true),
      ],
    );

    group('חתימת ספירת facets (דילוג על ספירה חוזרת)', () {
      test('חתימה זהה לאירועים שקולים ושונה כשמשתנה קלט שמשפיע על הספירה',
          () async {
        final bloc = SearchBloc();
        addTearDown(bloc.close);

        final base = UpdateSearchQuery('שלום', searchOptions: const {
          'שלום_0': {'קידומות': true},
        });
        final sameAsBase = UpdateSearchQuery('שלום', searchOptions: const {
          'שלום_0': {'קידומות': true},
        });

        expect(
          bloc.facetRecountSignatureForTesting(base),
          bloc.facetRecountSignatureForTesting(sameAsBase),
        );

        final differentQuery = UpdateSearchQuery('ברכה');
        final differentOptions =
            UpdateSearchQuery('שלום', searchOptions: const {
          'שלום_0': {'סיומות': true},
        });
        expect(
          bloc.facetRecountSignatureForTesting(base),
          isNot(bloc.facetRecountSignatureForTesting(differentQuery)),
        );
        expect(
          bloc.facetRecountSignatureForTesting(base),
          isNot(bloc.facetRecountSignatureForTesting(differentOptions)),
        );
      });

      test('שינוי scope או מצב חיפוש משנה את החתימה', () async {
        final bloc = SearchBloc();
        addTearDown(bloc.close);

        final event = UpdateSearchQuery('שלום');
        final before = bloc.facetRecountSignatureForTesting(event);

        bloc.add(const SetFacetsWithoutSearch(['/תנ"ך']));
        await Future<void>.delayed(Duration.zero);
        final afterScope = bloc.facetRecountSignatureForTesting(event);
        expect(afterScope, isNot(before));

        bloc.add(SetSearchModeWithoutSearch(SearchMode.fuzzy));
        await Future<void>.delayed(Duration.zero);
        expect(bloc.facetRecountSignatureForTesting(event), isNot(afterScope));
      });

      blocTest<SearchBloc, SearchState>(
        'ReplaceFacetCounts עדכני שומר את החתימה, ו-ResetSearch מנקה אותה',
        build: SearchBloc.new,
        act: (bloc) async {
          bloc.add(
              ReplaceFacetCounts({'/א': 1}, requestId: 0, signature: 'sig-a'));
          await Future<void>.delayed(Duration.zero);
          expect(bloc.facetCountsSignatureForTesting, 'sig-a');
          bloc.add(ResetSearch());
        },
        verify: (bloc) {
          expect(bloc.facetCountsSignatureForTesting, isNull);
        },
      );

      blocTest<SearchBloc, SearchState>(
        'ReplaceFacetCounts עם requestId ישן לא שומר חתימה',
        build: SearchBloc.new,
        act: (bloc) => bloc.add(
            ReplaceFacetCounts({'/א': 1}, requestId: 99, signature: 'sig-a')),
        verify: (bloc) {
          expect(bloc.facetCountsSignatureForTesting, isNull);
        },
      );
    });

    // blocTest אינו תומך בדילוג ישיר (skip שלו סופר states) — לכן העטיפה בקבוצה.
    group('דורש מנוע נייטיבי', () {
      blocTest<SearchBloc, SearchState>(
        'LoadMoreResults מבקש תוצאות מה-offset הנוכחי ומצרף אותן',
        build: () => SearchBloc(
          repository: _FakeSearchRepository(
            nextResults: [_searchResult(id: 2, text: 'תוצאה חדשה')],
          ),
        ),
        seed: () => SearchState(
          searchQuery: 'שלום, עולם',
          results: [_searchResult(id: 1, text: 'תוצאה קיימת')],
          totalResults: 2,
          configuration: const SearchConfiguration(
            currentFacets: ['/ספרים'],
            searchMode: SearchMode.advanced,
            distance: 4,
            sortBy: ResultsOrder.catalogue,
            numResults: 25,
          ),
        ),
        act: (bloc) => bloc.add(LoadMoreResults(
          customSpacing: const {'0-1': '3'},
          alternativeWords: const {
            0: ['ברכה'],
          },
          searchOptions: const {
            'שלום_0': {'קידומות': true},
          },
        )),
        expect: () => [
          isA<SearchState>()
              .having((state) => state.isLoading, 'isLoading', true),
          isA<SearchState>()
              .having((state) => state.isLoading, 'isLoading', false)
              .having((state) => state.results.length, 'results length', 2)
              .having(
                (state) => state.results.last.text,
                'last result text',
                'תוצאה חדשה',
              ),
        ],
        verify: (bloc) {
          final repository = bloc.repositoryForTesting as _FakeSearchRepository;
          expect(repository.searchCalls, 1);
          expect(repository.lastQuery, 'שלום עולם');
          expect(repository.lastFacets, ['/ספרים']);
          expect(repository.lastLimit, 25);
          expect(repository.lastOffset, 1);
          expect(repository.lastOrder, ResultsOrder.catalogue);
          expect(repository.lastSearchMode, SearchMode.advanced);
          expect(repository.lastDistance, 4);
          expect(repository.lastCustomSpacing, {'0-1': '3'});
          expect(repository.lastAlternativeWords, {
            0: ['ברכה'],
          });
          expect(repository.lastSearchOptions, {
            'שלום_0': {'קידומות': true},
          });
        },
      );
    }, skip: engineReady ? false : searchEngineSkipReason);

    blocTest<SearchBloc, SearchState>(
      'LoadMoreResults לא מחפש כשאין עוד תוצאות',
      build: () => SearchBloc(repository: _FakeSearchRepository()),
      seed: () => SearchState(
        searchQuery: 'שלום',
        results: [_searchResult(id: 1, text: 'יחידה')],
        totalResults: 1,
      ),
      act: (bloc) => bloc.add(LoadMoreResults()),
      expect: () => const <SearchState>[],
      verify: (bloc) {
        final repository = bloc.repositoryForTesting as _FakeSearchRepository;
        expect(repository.searchCalls, 0);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'LoadMoreResults מחזיר isLoading ל-false כאשר החיפוש נכשל',
      build: () => SearchBloc(
        repository: _FakeSearchRepository(throwOnSearch: true),
      ),
      seed: () => SearchState(
        searchQuery: 'שלום',
        results: [_searchResult(id: 1, text: 'קיימת')],
        totalResults: 2,
      ),
      act: (bloc) => bloc.add(LoadMoreResults()),
      expect: () => [
        isA<SearchState>()
            .having((state) => state.isLoading, 'isLoading', true),
        isA<SearchState>()
            .having((state) => state.isLoading, 'isLoading', false)
            .having((state) => state.results.length, 'results length', 1),
      ],
    );
  });
}

SearchResult _searchResult({required int id, required String text}) {
  return SearchResult(
      id: BigInt.from(id),
      title: 'ספר',
      reference: 'סימן',
      text: text,
      segment: BigInt.from(id),
      isPdf: false,
      filePath: 'book.txt',
      mergedCount: 1,
      merged: const []);
}

class _FakeSearchRepository extends SearchRepository {
  _FakeSearchRepository({
    this.nextResults = const [],
    this.throwOnSearch = false,
  });

  final List<SearchResult> nextResults;
  final bool throwOnSearch;

  int searchCalls = 0;
  String? lastQuery;
  List<String>? lastFacets;
  int? lastLimit;
  int? lastOffset;
  ResultsOrder? lastOrder;
  bool? lastFuzzy;
  int? lastDistance;
  SearchMode? lastSearchMode;
  Map<String, String>? lastCustomSpacing;
  Map<int, List<String>>? lastAlternativeWords;
  Map<String, Map<String, bool>>? lastSearchOptions;

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
    bool matchNikud = false,
    bool matchTaamim = false,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    searchCalls++;
    lastQuery = query;
    lastFacets = List<String>.from(facets);
    lastLimit = limit;
    lastOffset = offset;
    lastOrder = order;
    lastFuzzy = fuzzy;
    lastDistance = distance;
    lastSearchMode = searchMode;
    lastCustomSpacing = customSpacing;
    lastAlternativeWords = alternativeWords;
    lastSearchOptions = searchOptions;

    if (throwOnSearch) {
      throw StateError('search failed');
    }
    return nextResults;
  }
}
