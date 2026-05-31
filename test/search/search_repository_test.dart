import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  group('SearchRepository', () {
    test('searchTexts מעביר בקשת חיפוש מתקדם עם כל הפרמטרים', () async {
      final engine = _RecordingSearchEngineOperations();
      final repository = SearchRepository(engineProvider: () async => engine);

      final results = await repository.searchTexts(
        'שלום עולם',
        const ['/תורה'],
        25,
        offset: 10,
        order: ResultsOrder.catalogue,
        searchMode: SearchMode.advanced,
        distance: 4,
        customSpacing: const {'0-1': '3'},
        alternativeWords: const {
          1: ['בריאה'],
        },
        searchOptions: const {
          'שלום_0': {'קידומות': true},
        },
      );

      expect(results.single.text, 'advanced result');
      expect(engine.calls, [_EngineCall.searchAdvanced]);

      final request = engine.lastRequest!;
      expect(request.query, 'שלום עולם');
      expect(request.facets, ['/תורה']);
      expect(request.limit, 25);
      expect(request.offset, 10);
      expect(request.order, ResultsOrder.catalogue);
      expect(request.searchMode, SearchMode.advanced);
      expect(request.distance, 4);
      expect(request.customSpacing, {'0-1': '3'});
      expect(request.alternativeWords, {
        1: ['בריאה'],
      });
      expect(request.searchOptions, {
        'שלום_0': {'קידומות': true},
      });
    });

    test('fuzzy=true גובר על searchMode ומנתב לחיפוש מקורב', () async {
      final engine = _RecordingSearchEngineOperations();
      final repository = SearchRepository(engineProvider: () async => engine);

      await repository.searchTexts(
        'שלום',
        const ['/'],
        10,
        fuzzy: true,
        searchMode: SearchMode.advanced,
        distance: 7,
      );

      expect(engine.calls, [_EngineCall.searchFuzzy]);
      expect(engine.lastRequest!.searchMode, SearchMode.fuzzy);
      expect(engine.lastRequest!.distance, 7);
    });

    test('searchTextsAndCount מחזיר תוצאות וספירה מאותו request', () async {
      final engine = _RecordingSearchEngineOperations();
      final repository = SearchRepository(engineProvider: () async => engine);

      final result = await repository.searchTextsAndCount(
        'בראשית',
        const ['/מקרא'],
        5,
        searchMode: SearchMode.exact,
        offset: 2,
      );

      expect(engine.calls, [_EngineCall.searchAndCountExact]);
      expect(result.totalCount, 42);
      expect(result.results.single.text, 'page result');
      expect(engine.lastRequest!.query, 'בראשית');
      expect(engine.lastRequest!.facets, ['/מקרא']);
      expect(engine.lastRequest!.limit, 5);
      expect(engine.lastRequest!.offset, 2);
    });

    test('searchTextsStream מעביר chunkSize ומחזיר chunks מהמנוע', () async {
      final first = _result(id: 1, text: 'ראשון');
      final second = _result(id: 2, text: 'שני');
      final engine = _RecordingSearchEngineOperations(
        streamChunks: [
          [first],
          [second],
        ],
      );
      final repository = SearchRepository(engineProvider: () async => engine);

      final chunks = await repository
          .searchTextsStream(
            'חכמה',
            const ['/ספרים'],
            100,
            chunkSize: 7,
            searchMode: SearchMode.fuzzy,
            distance: 2,
            order: ResultsOrder.catalogue,
          )
          .toList();

      expect(engine.calls, [_EngineCall.searchFuzzyStream]);
      expect(engine.lastChunkSize, 7);
      expect(engine.lastRequest!.limit, 100);
      expect(engine.lastRequest!.order, ResultsOrder.catalogue);
      expect(chunks, [
        [first],
        [second],
      ]);
    });
  });
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
  _RecordingSearchEngineOperations({
    List<List<SearchResult>>? streamChunks,
  }) : streamChunks = streamChunks ?? const [];

  final List<_EngineCall> calls = [];
  final List<List<SearchResult>> streamChunks;
  SearchEngineRequest? lastRequest;
  int? lastChunkSize;

  void _record(_EngineCall call, SearchEngineRequest request) {
    calls.add(call);
    lastRequest = request;
  }

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) async {
    _record(_EngineCall.searchExact, request);
    return [_result(id: 1, text: 'exact result')];
  }

  @override
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request) async {
    _record(_EngineCall.searchAdvanced, request);
    return [_result(id: 2, text: 'advanced result')];
  }

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) async {
    _record(_EngineCall.searchFuzzy, request);
    return [_result(id: 3, text: 'fuzzy result')];
  }

  @override
  Future<SearchPageResult> searchAndCountExact(
    SearchEngineRequest request,
  ) async {
    _record(_EngineCall.searchAndCountExact, request);
    return SearchPageResult(totalCount: 42, results: [
      _result(id: 4, text: 'page result'),
    ]);
  }

  @override
  Future<SearchPageResult> searchAndCountAdvanced(
    SearchEngineRequest request,
  ) async {
    _record(_EngineCall.searchAndCountAdvanced, request);
    return const SearchPageResult(totalCount: 0, results: []);
  }

  @override
  Future<SearchPageResult> searchAndCountFuzzy(
    SearchEngineRequest request,
  ) async {
    _record(_EngineCall.searchAndCountFuzzy, request);
    return const SearchPageResult(totalCount: 0, results: []);
  }

  @override
  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    _record(_EngineCall.searchExactStream, request);
    lastChunkSize = chunkSize;
    for (final chunk in streamChunks) {
      yield chunk;
    }
  }

  @override
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    _record(_EngineCall.searchAdvancedStream, request);
    lastChunkSize = chunkSize;
    for (final chunk in streamChunks) {
      yield chunk;
    }
  }

  @override
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    _record(_EngineCall.searchFuzzyStream, request);
    lastChunkSize = chunkSize;
    for (final chunk in streamChunks) {
      yield chunk;
    }
  }

  @override
  Future<int> countExact(SearchEngineRequest request) async {
    _record(_EngineCall.countExact, request);
    return 0;
  }

  @override
  Future<int> countAdvanced(SearchEngineRequest request) async {
    _record(_EngineCall.countAdvanced, request);
    return 0;
  }

  @override
  Future<int> countFuzzy(SearchEngineRequest request) async {
    _record(_EngineCall.countFuzzy, request);
    return 0;
  }

  @override
  Future<Map<String, int>> countByBookExact(
    SearchEngineRequest request,
  ) async {
    _record(_EngineCall.countByBookExact, request);
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookAdvanced(
    SearchEngineRequest request,
  ) async {
    _record(_EngineCall.countByBookAdvanced, request);
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookFuzzy(
    SearchEngineRequest request,
  ) async {
    _record(_EngineCall.countByBookFuzzy, request);
    return const {};
  }

  @override
  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    _record(_EngineCall.getFacetCountsExact, request);
    return const [];
  }

  @override
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    _record(_EngineCall.getFacetCountsAdvanced, request);
    return const [];
  }

  @override
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    _record(_EngineCall.getFacetCountsFuzzy, request);
    return const [];
  }
}

SearchResult _result({required int id, required String text}) {
  return SearchResult(
    id: BigInt.from(id),
    title: 'ספר',
    reference: 'סימן',
    text: text,
    segment: BigInt.from(id),
    isPdf: false,
    filePath: 'book.txt',
  );
}
