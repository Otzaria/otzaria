import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  group('SearchQueryBuilder - אחריות UI בלבד', () {
    test('sanitizeQuery מנקה תווים שמגיעים מהקלט בלי לבנות שאילתת מנוע', () {
      expect(SearchQueryBuilder.sanitizeQuery('תורה, ומצוות'), 'תורה ומצוות');
      expect(SearchQueryBuilder.sanitizeQuery('אל־משה'), 'אל משה');
      expect(SearchQueryBuilder.sanitizeQuery('!?.,*'), '');
    });

    test('splitQueryWords שומר תאימות לטוקנייזר עבור ראשי תיבות', () {
      expect(SearchQueryBuilder.splitQueryWords('רמב"ם משה'), [
        'רמב',
        'ם',
        'משה',
      ]);
      expect(SearchQueryBuilder.splitQueryWords("ה'"), ["ה'"]);
    });

    test('effectiveSearchOptions מרחיב אפשרויות גלובליות לפי מילים', () {
      final options = SearchQueryBuilder.effectiveSearchOptions(
        query: 'חכמה בינה',
        useGlobalOptions: true,
        globalOptions: const {'קידומות': true},
        perWordOptions: const {},
      );

      expect(options, {
        'חכמה_0': {'קידומות': true},
        'בינה_1': {'קידומות': true},
      });
    });

    test('normalizeParametersForMode משאיר פרמטרים ידניים רק במצב מתקדם', () {
      final advanced = SearchQueryBuilder.normalizeParametersForMode(
        SearchMode.advanced,
        customSpacing: const {'0-1': ' 5 ', '1-2': ' '},
        alternativeWords: const {
          0: [' שלום ', ''],
        },
        searchOptions: const {
          'חכמה_0': {'קידומות': true, 'סיומות': false},
        },
      );

      expect(advanced.customSpacing, {'0-1': '5'});
      expect(advanced.alternativeWords, {
        0: ['שלום'],
      });
      expect(advanced.searchOptions, {
        'חכמה_0': {'קידומות': true},
      });

      final exact = SearchQueryBuilder.normalizeParametersForMode(
        SearchMode.exact,
        customSpacing: advanced.customSpacing,
        alternativeWords: advanced.alternativeWords,
        searchOptions: advanced.searchOptions,
      );

      expect(exact.customSpacing, isEmpty);
      expect(exact.alternativeWords, isEmpty);
      expect(exact.searchOptions, isEmpty);
    });
  });

  group('SearchEngineGateway', () {
    test('search מפנה לפונקציה המתאימה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.search(engine, _request(SearchMode.exact));
      await gateway.search(engine, _request(SearchMode.advanced));
      await gateway.search(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.searchExact,
        _EngineCall.searchAdvanced,
        _EngineCall.searchFuzzy,
      ]);
    });

    test('searchStream מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway
          .searchStream(engine, _request(SearchMode.exact), chunkSize: 10)
          .drain<void>();
      await gateway
          .searchStream(engine, _request(SearchMode.advanced), chunkSize: 10)
          .drain<void>();
      await gateway
          .searchStream(engine, _request(SearchMode.fuzzy), chunkSize: 10)
          .drain<void>();

      expect(engine.calls, [
        _EngineCall.searchExactStream,
        _EngineCall.searchAdvancedStream,
        _EngineCall.searchFuzzyStream,
      ]);
    });

    test('searchAndCount מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.searchAndCount(engine, _request(SearchMode.exact));
      await gateway.searchAndCount(engine, _request(SearchMode.advanced));
      await gateway.searchAndCount(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.searchAndCountExact,
        _EngineCall.searchAndCountAdvanced,
        _EngineCall.searchAndCountFuzzy,
      ]);
    });

    test('count מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.count(engine, _request(SearchMode.exact));
      await gateway.count(engine, _request(SearchMode.advanced));
      await gateway.count(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.countExact,
        _EngineCall.countAdvanced,
        _EngineCall.countFuzzy,
      ]);
    });

    test('countByBook מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.countByBook(engine, _request(SearchMode.exact));
      await gateway.countByBook(engine, _request(SearchMode.advanced));
      await gateway.countByBook(engine, _request(SearchMode.fuzzy));

      expect(engine.calls, [
        _EngineCall.countByBookExact,
        _EngineCall.countByBookAdvanced,
        _EngineCall.countByBookFuzzy,
      ]);
    });

    test('getFacetCounts מפנה לפי מצב החיפוש', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.exact),
        facetPrefix: '/',
      );
      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.advanced),
        facetPrefix: '/',
      );
      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.fuzzy),
        facetPrefix: '/',
      );

      expect(engine.calls, [
        _EngineCall.getFacetCountsExact,
        _EngineCall.getFacetCountsAdvanced,
        _EngineCall.getFacetCountsFuzzy,
      ]);
    });

    test('count/countByBook/getFacetCounts משתמשים באותו dispatch', () async {
      final engine = _RecordingSearchEngineOperations();
      const gateway = SearchEngineGateway();

      await gateway.count(engine, _request(SearchMode.exact));
      await gateway.countByBook(engine, _request(SearchMode.advanced));
      await gateway.getFacetCounts(
        engine,
        _request(SearchMode.fuzzy),
        facetPrefix: '/',
      );

      expect(engine.calls, [
        _EngineCall.countExact,
        _EngineCall.countByBookAdvanced,
        _EngineCall.getFacetCountsFuzzy,
      ]);
    });
  });
}

SearchEngineRequest _request(SearchMode mode) {
  return SearchEngineRequest(
    query: 'שלום עולם',
    facets: const ['/'],
    limit: 20,
    offset: 0,
    order: ResultsOrder.relevance,
    searchMode: mode,
    distance: 2,
  );
}

enum _EngineCall {
  searchExact,
  searchAdvanced,
  searchFuzzy,
  searchAndCountExact,
  searchAndCountAdvanced,
  searchAndCountFuzzy,
  searchExactStream,
  searchAdvancedStream,
  searchFuzzyStream,
  countExact,
  countAdvanced,
  countFuzzy,
  countByBookExact,
  countByBookAdvanced,
  countByBookFuzzy,
  getFacetCountsExact,
  getFacetCountsAdvanced,
  getFacetCountsFuzzy,
}

class _RecordingSearchEngineOperations implements SearchEngineOperations {
  final List<_EngineCall> calls = [];

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) async {
    calls.add(_EngineCall.searchExact);
    return const [];
  }

  @override
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request) async {
    calls.add(_EngineCall.searchAdvanced);
    return const [];
  }

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) async {
    calls.add(_EngineCall.searchFuzzy);
    return const [];
  }

  @override
  Future<SearchPageResult> searchAndCountExact(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.searchAndCountExact);
    return const SearchPageResult(totalCount: 0, results: []);
  }

  @override
  Future<SearchPageResult> searchAndCountAdvanced(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.searchAndCountAdvanced);
    return const SearchPageResult(totalCount: 0, results: []);
  }

  @override
  Future<SearchPageResult> searchAndCountFuzzy(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.searchAndCountFuzzy);
    return const SearchPageResult(totalCount: 0, results: []);
  }

  @override
  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    calls.add(_EngineCall.searchExactStream);
    yield const [];
  }

  @override
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    calls.add(_EngineCall.searchAdvancedStream);
    yield const [];
  }

  @override
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    calls.add(_EngineCall.searchFuzzyStream);
    yield const [];
  }

  @override
  Future<int> countExact(SearchEngineRequest request) async {
    calls.add(_EngineCall.countExact);
    return 0;
  }

  @override
  Future<int> countAdvanced(SearchEngineRequest request) async {
    calls.add(_EngineCall.countAdvanced);
    return 0;
  }

  @override
  Future<int> countFuzzy(SearchEngineRequest request) async {
    calls.add(_EngineCall.countFuzzy);
    return 0;
  }

  @override
  Future<Map<String, int>> countByBookExact(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.countByBookExact);
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookAdvanced(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.countByBookAdvanced);
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookFuzzy(
    SearchEngineRequest request,
  ) async {
    calls.add(_EngineCall.countByBookFuzzy);
    return const {};
  }

  @override
  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    calls.add(_EngineCall.getFacetCountsExact);
    return const [];
  }

  @override
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    calls.add(_EngineCall.getFacetCountsAdvanced);
    return const [];
  }

  @override
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    calls.add(_EngineCall.getFacetCountsFuzzy);
    return const [];
  }
}
