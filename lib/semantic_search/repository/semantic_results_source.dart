import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/search_engine_gateway.dart'
    show SemanticSearchRequest;
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultGrouping, SemanticGroupingMode, SemanticRetrievalMode;

/// מקור עמודי התוצאות של מסך החיפוש הסמנטי.
abstract interface class SemanticResultsSource {
  /// תצוגה מקדימה בפיתוח (חיפוש מילולי בתחפושת), לא המנוע.
  bool get isDebugPreview;

  /// הדירוג שנשלח למנוע; `null` = ברירות המחדל שלו.
  SemanticRankingConfig? get ranking;

  /// `null` כשחיפוש חדש יותר החליף את זה. זורק `SemanticFailure` בכשל.
  Future<SemanticResultsPage?> fetch(
    SemanticQueryOptions options, {
    required int offset,
    required int limit,
  });

  void cancel();

  Future<SemanticEngineSnapshot> engineSnapshot();
}

/// בוחר מקור לפי הזמינות הנוכחית; `null` = המצב אינו שמיש.
typedef SemanticSourceResolver = Future<SemanticResultsSource?> Function();

/// מקור ברירת המחדל: המנוע כשהוא מוכן, תצוגה מקדימה בפיתוח כשחסרים נתונים.
Future<SemanticResultsSource?> resolveSemanticResultsSource({
  SemanticSearchRepository? repository,
  bool debug = kDebugMode,
}) async {
  final repo = repository ?? SemanticSearchRepository.instance;
  final availability = await repo.refresh();
  if (availability.isUsable) return EngineSemanticResultsSource(repo);
  if (isSemanticDebugPreview(availability, debug: debug)) {
    return DebugLexicalPreviewSource(engineSnapshot: repo.engineSnapshot);
  }
  return null;
}

/// חיפוש דרך [SemanticSearchRepository].
class EngineSemanticResultsSource implements SemanticResultsSource {
  EngineSemanticResultsSource(this._repository);

  final SemanticSearchRepository _repository;

  /// ערוץ משלו: חיפוש בכרטיסייה אחרת אינו מבטל את החיפוש כאן.
  final SemanticSearchSession _session = SemanticSearchSession();

  @override
  bool get isDebugPreview => false;

  @override
  SemanticRankingConfig? get ranking => const SemanticRankingConfig();

  @override
  Future<SemanticResultsPage?> fetch(
    SemanticQueryOptions options, {
    required int offset,
    required int limit,
  }) async {
    final outcome = await _repository.search(
      SemanticSearchRequest(
        query: options.query,
        facets: options.facets,
        limit: limit,
        offset: offset,
        retrievalMode: options.includeLexical
            ? SemanticRetrievalMode.hybrid
            : SemanticRetrievalMode.semanticOnly,
        grouping: options.groupIdenticalText
            ? SemanticGroupingMode.identicalText
            : null,
      ),
      ranking: ranking,
      session: _session,
    );
    if (outcome == null) return null;
    final response = outcome.response;
    return SemanticResultsPage(
      items: [
        for (final result in response.results)
          SemanticResultItem.fromEngine(result),
      ],
      pageableTotal: response.groupCount ?? response.totalCount,
      executedMode: response.executedMode.name,
      semanticAvailable: response.semanticAvailable,
      fallbackReason: response.fallbackReason,
      fallbackKind: outcome.fallbackKind?.name,
      latencyMs: response.latencyMs.toInt(),
      totalCount: response.totalCount,
      lexicalTotalCount: response.lexicalTotalCount,
      groupCount: response.groupCount,
      countsAreExact: response.countsAreExact,
      truncated: response.truncated,
      candidateWindowTruncated: response.candidateWindowTruncated,
    );
  }

  @override
  void cancel() => _repository.cancelSearch(session: _session);

  @override
  Future<SemanticEngineSnapshot> engineSnapshot() =>
      _repository.engineSnapshot();
}

/// פיתוח בלבד: חיפוש מילולי שממופה לאותו מבנה, עם ציונים מדומים.
class DebugLexicalPreviewSource implements SemanticResultsSource {
  DebugLexicalPreviewSource({
    required this._engineSnapshot,
    this._searchRepository = const SearchRepository(),
  });

  final Future<SemanticEngineSnapshot> Function() _engineSnapshot;
  final SearchRepository _searchRepository;
  int _generation = 0;

  @override
  bool get isDebugPreview => true;

  @override
  SemanticRankingConfig? get ranking => null;

  @override
  Future<SemanticResultsPage?> fetch(
    SemanticQueryOptions options, {
    required int offset,
    required int limit,
  }) async {
    final generation = ++_generation;
    final stopwatch = Stopwatch()..start();
    final page = await _searchRepository.searchTextsAndCount(
      SearchQueryBuilder.sanitizeQuery(options.query),
      options.facets,
      limit,
      offset: offset,
      grouping: options.groupIdenticalText
          ? ResultGrouping.identicalText
          : null,
    );
    if (generation != _generation) return null;
    return SemanticResultsPage(
      items: [
        for (var i = 0; i < page.results.length; i++)
          SemanticResultItem.debugFromLexical(page.results[i], offset + i + 1),
      ],
      pageableTotal: page.groupCount ?? page.totalCount,
      executedMode: 'lexicalOnly',
      semanticAvailable: false,
      fallbackReason: kSemanticDebugPreviewFallbackReason,
      latencyMs: stopwatch.elapsedMilliseconds,
      totalCount: page.totalCount,
      lexicalTotalCount: page.totalCount,
      groupCount: page.groupCount,
      countsAreExact: true,
      truncated: page.truncated,
      candidateWindowTruncated: false,
    );
  }

  @override
  void cancel() => _generation++;

  @override
  Future<SemanticEngineSnapshot> engineSnapshot() => _engineSnapshot();
}

/// השורה המלאה של התוצאה מהאינדקס (ב-Rust, מחוץ ל-UI); `null` כשלא נמצאה.
Future<String?> resolveSemanticPassage(SemanticResultItem item) async {
  final engine = await TantivyDataProvider.instance.engine;
  final document = await engine
      .getDocumentById(id: item.id)
      .timeout(const Duration(seconds: 5));
  if (document == null || document.filePath != item.filePath) return null;
  return utils.stripHtmlIfNeeded(document.text).trim();
}
