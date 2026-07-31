import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

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
    this._gateway = const SearchEngineGateway(),
    this._engineProvider,
  });

  Future<SearchEngineOperations> _engine() async {
    final provider = _engineProvider;
    if (provider != null) return provider();

    return RustSearchEngineOperations(
      await TantivyDataProvider.instance.engine,
    );
  }

  Future<SemanticSearchEngineOperations> _semanticEngine() async {
    final engine = await _engine();
    if (engine case final SemanticSearchEngineOperations semanticEngine) {
      return semanticEngine;
    }
    throw StateError('מנוע החיפוש שסופק אינו תומך בפעולות סמנטיות');
  }

  /// מבצע חיפוש לקסיקלי, היברידי או סמנטי דרך חוזה המנוע המאוחד.
  Future<SemanticSearchResponse> searchSemantic(
    SemanticSearchRequest request,
  ) async {
    return _gateway.searchSemantic(await _semanticEngine(), request);
  }

  /// פותח session סמנטי. המודל נטען עצלנית בתחילת האינדוקס.
  Future<SemanticStatus> configureSemantic(SemanticConfigInput config) async {
    return _gateway.configureSemantic(await _semanticEngine(), config);
  }

  /// סוגר את ה-session הסמנטי ומאפשר להגדיר מודל או שורש אחרים.
  Future<void> disableSemantic() async {
    return _gateway.disableSemantic(await _semanticEngine());
  }

  /// מחזיר את זמינות ה-backend, מצב המודל ונתוני האינדקס הסמנטי.
  Future<SemanticStatus> semanticStatus() async {
    return _gateway.semanticStatus(await _semanticEngine());
  }

  /// מחשב אילו ספרים נוספו, השתנו או הוסרו מאז האינדוקס האחרון.
  Future<SemanticIndexDiff> semanticIndexDiff() async {
    return _gateway.semanticIndexDiff(await _semanticEngine());
  }

  /// מוסיף או מעדכן ספרים באינדקס הסמנטי.
  Future<SemanticIndexingSummary> semanticIndexBooks(
    List<SemanticBookInput> books,
  ) async {
    return _gateway.semanticIndexBooks(await _semanticEngine(), books);
  }

  /// מסיר ספרים מהאינדקס הסמנטי לפי מפתחות המקור שלהם.
  Future<SemanticRemoveResult> removeSemanticBooks(
    List<String> sourceBookKeys,
  ) async {
    return _gateway.removeSemanticBooks(
      await _semanticEngine(),
      sourceBookKeys,
    );
  }

  /// מוחק את כל הווקטורים וה-manifest של האינדקס הסמנטי.
  Future<SemanticResetResult> resetSemanticIndex() async {
    return _gateway.resetSemanticIndex(await _semanticEngine());
  }

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
        negativeQuery: negativeQuery,
        negativeDistance: negativeDistance ?? distance,
        scope: scope,
        negativeScope: negativeScope ?? scope,
        customSpacing: customSpacing ?? const {},
        negativeCustomSpacing: negativeCustomSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        negativeAlternativeWords: negativeAlternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
        negativeSearchOptions: negativeSearchOptions ?? const {},
        matchNikud: matchNikud,
        matchTaamim: matchTaamim,
        grouping: grouping,
        wordMatchMode: wordMatchMode,
        wordMatchCount: wordMatchCount,
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
        negativeQuery: negativeQuery,
        negativeDistance: negativeDistance ?? distance,
        scope: scope,
        negativeScope: negativeScope ?? scope,
        customSpacing: customSpacing ?? const {},
        negativeCustomSpacing: negativeCustomSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        negativeAlternativeWords: negativeAlternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
        negativeSearchOptions: negativeSearchOptions ?? const {},
        matchNikud: matchNikud,
        matchTaamim: matchTaamim,
        grouping: grouping,
        wordMatchMode: wordMatchMode,
        wordMatchCount: wordMatchCount,
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
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    int chunkSize = 50,
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
  }) async* {
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
        negativeQuery: negativeQuery,
        negativeDistance: negativeDistance ?? distance,
        scope: scope,
        negativeScope: negativeScope ?? scope,
        customSpacing: customSpacing ?? const {},
        negativeCustomSpacing: negativeCustomSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        negativeAlternativeWords: negativeAlternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
        negativeSearchOptions: negativeSearchOptions ?? const {},
        matchNikud: matchNikud,
        matchTaamim: matchTaamim,
        grouping: grouping,
        wordMatchMode: wordMatchMode,
        wordMatchCount: wordMatchCount,
      ),
      chunkSize: chunkSize,
    );
  }

  /// כמו [searchTextsStream], אבל האירוע הראשון נושא גם את הספירה הכוללת
  /// ואת הספירה לפי ספר — מחושבות באותו מעבר אינדקס של החיפוש עצמו, במקום
  /// שלוש ריצות נפרדות של אותה שאילתה.
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    int chunkSize = 50,
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
  }) async* {
    yield* _gateway.searchStreamWithCounts(
      await _engine(),
      SearchEngineRequest(
        query: query,
        facets: facets,
        limit: limit,
        offset: offset,
        order: order,
        searchMode: fuzzy ? SearchMode.fuzzy : searchMode,
        distance: distance,
        negativeQuery: negativeQuery,
        negativeDistance: negativeDistance ?? distance,
        scope: scope,
        negativeScope: negativeScope ?? scope,
        customSpacing: customSpacing ?? const {},
        negativeCustomSpacing: negativeCustomSpacing ?? const {},
        alternativeWords: alternativeWords ?? const {},
        negativeAlternativeWords: negativeAlternativeWords ?? const {},
        searchOptions: searchOptions ?? const {},
        negativeSearchOptions: negativeSearchOptions ?? const {},
        matchNikud: matchNikud,
        matchTaamim: matchTaamim,
        grouping: grouping,
        wordMatchMode: wordMatchMode,
        wordMatchCount: wordMatchCount,
      ),
      chunkSize: chunkSize,
    );
  }
}
