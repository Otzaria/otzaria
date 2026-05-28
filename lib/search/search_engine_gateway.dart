import 'package:otzaria/search/models/search_configuration.dart';
import 'package:search_engine/search_engine.dart';

/// בקשת חיפוש אחידה שמגיעה משכבת האפליקציה אל מנוע החיפוש.
///
/// המחלקה מכילה את בחירות ה-UI והניווט בלבד. מנוע החיפוש אחראי לכל
/// המשמעות האלגוריתמית של סוגי החיפוש.
class SearchEngineRequest {
  final String query;
  final List<String> facets;
  final int limit;
  final int offset;
  final ResultsOrder order;
  final SearchMode searchMode;
  final int distance;
  final Map<String, String> customSpacing;
  final Map<int, List<String>> alternativeWords;
  final Map<String, Map<String, bool>> searchOptions;

  const SearchEngineRequest({
    required this.query,
    required this.facets,
    this.limit = 0,
    this.offset = 0,
    this.order = ResultsOrder.relevance,
    this.searchMode = SearchMode.exact,
    this.distance = 0,
    this.customSpacing = const {},
    this.alternativeWords = const {},
    this.searchOptions = const {},
  });

  SearchEngineRequest copyWith({
    String? query,
    List<String>? facets,
    int? limit,
    int? offset,
    ResultsOrder? order,
    SearchMode? searchMode,
    int? distance,
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
  }) {
    return SearchEngineRequest(
      query: query ?? this.query,
      facets: facets ?? this.facets,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
      order: order ?? this.order,
      searchMode: searchMode ?? this.searchMode,
      distance: distance ?? this.distance,
      customSpacing: customSpacing ?? this.customSpacing,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      searchOptions: searchOptions ?? this.searchOptions,
    );
  }
}

/// ממשק קטן וניתן לבדיקה מעל ה-API של `search_engine`.
abstract class SearchEngineOperations {
  Future<List<SearchResult>> searchExact(SearchEngineRequest request);
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request);
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request);

  Future<SearchPageResult> searchAndCountExact(SearchEngineRequest request);
  Future<SearchPageResult> searchAndCountAdvanced(SearchEngineRequest request);
  Future<SearchPageResult> searchAndCountFuzzy(SearchEngineRequest request);

  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  });
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  });
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  });

  Future<int> countExact(SearchEngineRequest request);
  Future<int> countAdvanced(SearchEngineRequest request);
  Future<int> countFuzzy(SearchEngineRequest request);

  Future<Map<String, int>> countByBookExact(SearchEngineRequest request);
  Future<Map<String, int>> countByBookAdvanced(SearchEngineRequest request);
  Future<Map<String, int>> countByBookFuzzy(SearchEngineRequest request);

  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  });
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  });
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  });
}

class RustSearchEngineOperations implements SearchEngineOperations {
  final SearchEngine _engine;

  const RustSearchEngineOperations(this._engine);

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) {
    return _engine.searchExact(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      order: request.order,
    );
  }

  @override
  Future<List<SearchResult>> searchAdvanced(SearchEngineRequest request) {
    return _engine.searchAdvanced(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      distance: request.distance,
      customSpacing: request.customSpacing,
      alternativeWords: request.alternativeWords,
      searchOptions: request.searchOptions,
      order: request.order,
    );
  }

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) {
    return _engine.searchFuzzy(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      maxDistance: _fuzzyDistance(request.distance),
      order: request.order,
    );
  }

  @override
  Future<SearchPageResult> searchAndCountExact(SearchEngineRequest request) {
    return _engine.searchAndCountExact(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      order: request.order,
    );
  }

  @override
  Future<SearchPageResult> searchAndCountAdvanced(
    SearchEngineRequest request,
  ) {
    return _engine.searchAndCountAdvanced(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      distance: request.distance,
      customSpacing: request.customSpacing,
      alternativeWords: request.alternativeWords,
      searchOptions: request.searchOptions,
      order: request.order,
    );
  }

  @override
  Future<SearchPageResult> searchAndCountFuzzy(SearchEngineRequest request) {
    return _engine.searchAndCountFuzzy(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      maxDistance: _fuzzyDistance(request.distance),
      order: request.order,
    );
  }

  @override
  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    return _engine.searchExactStream(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      order: request.order,
      chunkSize: chunkSize,
    );
  }

  @override
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    return _engine.searchAdvancedStream(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      distance: request.distance,
      customSpacing: request.customSpacing,
      alternativeWords: request.alternativeWords,
      searchOptions: request.searchOptions,
      order: request.order,
      chunkSize: chunkSize,
    );
  }

  @override
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    return _engine.searchFuzzyStream(
      query: request.query,
      facets: request.facets,
      limit: request.limit,
      offset: request.offset,
      maxDistance: _fuzzyDistance(request.distance),
      order: request.order,
      chunkSize: chunkSize,
    );
  }

  @override
  Future<int> countExact(SearchEngineRequest request) {
    return _engine.countExact(
      query: request.query,
      facets: request.facets,
    );
  }

  @override
  Future<int> countAdvanced(SearchEngineRequest request) {
    return _engine.countAdvanced(
      query: request.query,
      facets: request.facets,
      distance: request.distance,
      customSpacing: request.customSpacing,
      alternativeWords: request.alternativeWords,
      searchOptions: request.searchOptions,
    );
  }

  @override
  Future<int> countFuzzy(SearchEngineRequest request) {
    return _engine.countFuzzy(
      query: request.query,
      facets: request.facets,
      maxDistance: _fuzzyDistance(request.distance),
    );
  }

  @override
  Future<Map<String, int>> countByBookExact(SearchEngineRequest request) {
    return _engine.countByBookExact(
      query: request.query,
      facets: request.facets,
    );
  }

  @override
  Future<Map<String, int>> countByBookAdvanced(SearchEngineRequest request) {
    return _engine.countByBookAdvanced(
      query: request.query,
      facets: request.facets,
      distance: request.distance,
      customSpacing: request.customSpacing,
      alternativeWords: request.alternativeWords,
      searchOptions: request.searchOptions,
    );
  }

  @override
  Future<Map<String, int>> countByBookFuzzy(SearchEngineRequest request) {
    return _engine.countByBookFuzzy(
      query: request.query,
      facets: request.facets,
      maxDistance: _fuzzyDistance(request.distance),
    );
  }

  @override
  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) {
    return _engine.getFacetCountsExact(
      query: request.query,
      facets: request.facets,
      facetPrefix: facetPrefix,
    );
  }

  @override
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) {
    return _engine.getFacetCountsAdvanced(
      query: request.query,
      facets: request.facets,
      facetPrefix: facetPrefix,
      distance: request.distance,
      customSpacing: request.customSpacing,
      alternativeWords: request.alternativeWords,
      searchOptions: request.searchOptions,
    );
  }

  @override
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) {
    return _engine.getFacetCountsFuzzy(
      query: request.query,
      facets: request.facets,
      facetPrefix: facetPrefix,
      maxDistance: _fuzzyDistance(request.distance),
    );
  }

  static int _fuzzyDistance(int distance) {
    return distance.clamp(0, 2).toInt();
  }
}

class SearchEngineGateway {
  const SearchEngineGateway();

  Future<List<SearchResult>> search(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.searchExact(request);
      case SearchMode.advanced:
        return engine.searchAdvanced(request);
      case SearchMode.fuzzy:
        return engine.searchFuzzy(request);
    }
  }

  Future<SearchPageResult> searchAndCount(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.searchAndCountExact(request);
      case SearchMode.advanced:
        return engine.searchAndCountAdvanced(request);
      case SearchMode.fuzzy:
        return engine.searchAndCountFuzzy(request);
    }
  }

  Stream<List<SearchResult>> searchStream(
    SearchEngineOperations engine,
    SearchEngineRequest request, {
    required int chunkSize,
  }) {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.searchExactStream(request, chunkSize: chunkSize);
      case SearchMode.advanced:
        return engine.searchAdvancedStream(request, chunkSize: chunkSize);
      case SearchMode.fuzzy:
        return engine.searchFuzzyStream(request, chunkSize: chunkSize);
    }
  }

  Future<int> count(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.countExact(request);
      case SearchMode.advanced:
        return engine.countAdvanced(request);
      case SearchMode.fuzzy:
        return engine.countFuzzy(request);
    }
  }

  Future<Map<String, int>> countByBook(
    SearchEngineOperations engine,
    SearchEngineRequest request,
  ) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.countByBookExact(request);
      case SearchMode.advanced:
        return engine.countByBookAdvanced(request);
      case SearchMode.fuzzy:
        return engine.countByBookFuzzy(request);
    }
  }

  Future<List<FacetCount>> getFacetCounts(
    SearchEngineOperations engine,
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async {
    switch (request.searchMode) {
      case SearchMode.exact:
        return engine.getFacetCountsExact(
          request,
          facetPrefix: facetPrefix,
        );
      case SearchMode.advanced:
        return engine.getFacetCountsAdvanced(
          request,
          facetPrefix: facetPrefix,
        );
      case SearchMode.fuzzy:
        return engine.getFacetCountsFuzzy(
          request,
          facetPrefix: facetPrefix,
        );
    }
  }
}
