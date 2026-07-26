import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// מנוע מזויף שלוכד את הבקשה האחרונה שהגיעה אליו.
class RecordingSearchEngine extends SearchEngineOperations {
  SearchEngineRequest? lastRequest;

  SearchPageResult _page(SearchEngineRequest request) {
    lastRequest = request;
    return const SearchPageResult(totalCount: 0, results: [], truncated: false);
  }

  @override
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    lastRequest = request;
    yield const SearchStreamUpdate(
      totalCount: 0,
      bookCounts: {},
      results: [],
      truncated: false,
    );
  }

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) async {
    lastRequest = request;
    return const [];
  }

  @override
  Future<List<SearchResult>> searchAdvanced(
    SearchEngineRequest request,
  ) async {
    lastRequest = request;
    return const [];
  }

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) async {
    lastRequest = request;
    return const [];
  }

  @override
  Future<SearchPageResult> searchAndCountExact(SearchEngineRequest r) async =>
      _page(r);

  @override
  Future<SearchPageResult> searchAndCountAdvanced(
    SearchEngineRequest r,
  ) async => _page(r);

  @override
  Future<SearchPageResult> searchAndCountFuzzy(SearchEngineRequest r) async =>
      _page(r);

  @override
  Stream<List<SearchResult>> searchExactStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    lastRequest = request;
  }

  @override
  Stream<List<SearchResult>> searchAdvancedStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    lastRequest = request;
  }

  @override
  Stream<List<SearchResult>> searchFuzzyStream(
    SearchEngineRequest request, {
    required int chunkSize,
  }) async* {
    lastRequest = request;
  }

  @override
  Future<int> countExact(SearchEngineRequest request) async => 0;

  @override
  Future<int> countAdvanced(SearchEngineRequest request) async => 0;

  @override
  Future<int> countFuzzy(SearchEngineRequest request) async => 0;

  @override
  Future<Map<String, int>> countByBookExact(SearchEngineRequest r) async {
    lastRequest = r;
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookAdvanced(SearchEngineRequest r) async {
    lastRequest = r;
    return const {};
  }

  @override
  Future<Map<String, int>> countByBookFuzzy(SearchEngineRequest r) async {
    lastRequest = r;
    return const {};
  }

  @override
  Future<List<FacetCount>> getFacetCountsExact(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async => const [];

  @override
  Future<List<FacetCount>> getFacetCountsAdvanced(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async => const [];

  @override
  Future<List<FacetCount>> getFacetCountsFuzzy(
    SearchEngineRequest request, {
    required String facetPrefix,
  }) async => const [];

  @override
  void primeHighlightPattern(SearchEngineRequest request) {}
}
