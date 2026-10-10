import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

export 'package:otzaria/search/search_engine_gateway.dart'
    show SearchEngineRequest;

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

  /// ביטוי ליטרלי בסדר הקטלוג, ללא הרחבות של מילות השאילתה.
  Future<List<SearchResult>> searchLiteralPhrase(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    bool includeAdjacentLine = false,
  }) async {
    final engine = await _engine();
    final request = SearchEngineRequest(
      query: query,
      facets: facets,
      limit: limit,
      offset: offset,
      order: ResultsOrder.catalogue,
    );
    return includeAdjacentLine
        ? engine.searchExact(request)
        : engine.searchInlineExact(request);
  }

  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async =>
      _gateway.search(await _engine(), request);

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
    SearchEngineRequest request,
  ) async => _gateway.searchAndCount(await _engine(), request);

  /// חיפוש בזרם של chunks. האירוע הראשון נושא גם את הספירה הכוללת
  /// ואת הספירה לפי ספר — מחושבות באותו מעבר אינדקס של החיפוש עצמו, במקום
  /// שלוש ריצות נפרדות של אותה שאילתה.
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) async* {
    yield* _gateway.searchStreamWithCounts(
      await _engine(),
      request,
      chunkSize: chunkSize,
    );
  }
}
