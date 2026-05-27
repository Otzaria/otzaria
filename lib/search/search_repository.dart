import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:search_engine/search_engine.dart';

/// Performs a search operation across indexed texts.
///
/// [query] The search query string
/// [facets] List of facets to search within
/// [limit] Maximum number of results to return
/// [order] Sort order for results
/// [fuzzy] Whether to perform fuzzy matching
/// [distance] Default distance between words (slop)
/// [customSpacing] Custom spacing between specific word pairs
/// [alternativeWords] Alternative words for each word position (OR queries)
/// [searchOptions] Search options for each word (prefixes, suffixes, etc.)
///
/// Returns a Future containing a list of search results
///
class SearchRepository {
  final SearchEngineGateway _gateway;
  final Future<SearchEngineOperations> Function()? _engineProvider;

  const SearchRepository({
    SearchEngineGateway gateway = const SearchEngineGateway(),
    Future<SearchEngineOperations> Function()? engineProvider,
  })  : _gateway = gateway,
        _engineProvider = engineProvider;

  Future<SearchEngineOperations> _engine() async {
    final provider = _engineProvider;
    if (provider != null) return provider();

    return RustSearchEngineOperations(
        await TantivyDataProvider.instance.engine);
  }

  Future<List<SearchResult>> searchTexts(
      String query, List<String> facets, int limit,
      {int offset = 0,
      ResultsOrder order = ResultsOrder.relevance,
      bool fuzzy = false,
      int distance = 0,
      SearchMode searchMode = SearchMode.exact,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions}) async {
    return _gateway.search(
      await _engine(),
      SearchEngineRequest(
        query: query,
        facets: facets,
        limit: limit,
        offset: offset,
        order: order,
        searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
        distance: distance,
        customSpacing: customSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
      ),
    );
  }

  /// Performs a combined search + count in a single engine pass.
  /// Returns total hit count alongside paged results, without streaming.
  /// Prefer this over separate search() + count() calls when streaming is not needed.
  ///
  /// [query] The search query string
  /// [facets] List of facets to search within
  /// [limit] Maximum number of results to return
  ///
  /// Returns a Future containing [SearchPageResult] with results and totalCount
  Future<SearchPageResult> searchTextsAndCount(
      String query, List<String> facets, int limit,
      {int offset = 0,
      ResultsOrder order = ResultsOrder.relevance,
      bool fuzzy = false,
      int distance = 0,
      SearchMode searchMode = SearchMode.exact,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions}) async {
    return _gateway.searchAndCount(
      await _engine(),
      SearchEngineRequest(
        query: query,
        facets: facets,
        limit: limit,
        offset: offset,
        order: order,
        searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
        distance: distance,
        customSpacing: customSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
      ),
    );
  }

  /// Performs a streaming search operation across indexed texts.
  /// Results are returned in chunks for better UX with large result sets.
  ///
  /// [query] The search query string
  /// [facets] List of facets to search within
  /// [limit] Maximum number of results to return
  /// [chunkSize] Number of results per chunk (default: 50)
  /// [order] Sort order for results
  /// [fuzzy] Whether to perform fuzzy matching
  /// [distance] Default distance between words (slop)
  /// [customSpacing] Custom spacing between specific word pairs
  /// [alternativeWords] Alternative words for each word position (OR queries)
  /// [searchOptions] Search options for each word (prefixes, suffixes, etc.)
  ///
  /// Returns a Stream of search result chunks
  ///
  Stream<List<SearchResult>> searchTextsStream(
      String query, List<String> facets, int limit,
      {int offset = 0,
      int chunkSize = 50,
      ResultsOrder order = ResultsOrder.relevance,
      bool fuzzy = false,
      int distance = 0,
      SearchMode searchMode = SearchMode.exact,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions}) async* {
    yield* _gateway.searchStream(
      await _engine(),
      SearchEngineRequest(
        query: query,
        facets: facets,
        limit: limit,
        offset: offset,
        order: order,
        searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
        distance: distance,
        customSpacing: customSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
      ),
      chunkSize: chunkSize,
    );
  }
}
