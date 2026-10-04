import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';

class MemoryConsentPersistence implements SearchFeedbackConsentPersistence {
  String? state;
  int? version;

  @override
  String? readState() => state;

  @override
  int? readVersion() => version;

  @override
  Future<void> write(String state, int version) async {
    this.state = state;
    this.version = version;
  }
}

final DateTime kStart = DateTime.utc(2026, 10, 2, 10);

SemanticSearchContext searchContext({
  String id = 'session_abcdefgh',
  String query = 'שבת שלום',
  SemanticEngineSnapshot engine = const SemanticEngineSnapshot(
    state: 'ready',
    modelFamilyId: 'family@abc',
    modelQuantization: 'int8',
    embeddingDim: 256,
    vectorsReleaseTag: 'vectors-v30',
    vectorsLibraryVersion: 30,
    vectorSegments: 1,
  ),
  Map<String, Object?>? ranking,
  String? fallbackKind,
  String? fallbackReason,
  String retrievalMode = 'hybrid',
  String lexicalMode = 'exact',
  String? grouping,
  String executedMode = 'hybrid',
  int fuzzyMaxDistance = 0,
  int pageSize = 50,
}) => SemanticSearchContext(
  searchSessionId: id,
  query: query,
  startedAt: kStart,
  params: SemanticSearchParamsSnapshot(
    retrievalMode: retrievalMode,
    lexicalMode: lexicalMode,
    fuzzyMaxDistance: fuzzyMaxDistance,
    grouping: grouping,
    matchNikud: false,
    matchTaamim: false,
    facets: const ['/תנך'],
    allLibrary: false,
    pageSize: pageSize,
    ranking: ranking,
  ),
  response: SemanticSearchResponseSnapshot(
    executedMode: executedMode,
    semanticAvailable: true,
    fallbackReason: fallbackReason,
    fallbackKind: fallbackKind,
    latencyMs: 120,
    totalCount: 200,
    lexicalTotalCount: 37,
    groupCount: null,
    countsAreExact: false,
    truncated: false,
    candidateWindowTruncated: false,
  ),
  engine: engine,
);

SemanticResultSnapshot result({
  int rank = 1,
  bool isUserBook = false,
  String title = 'בראשית',
  String reference = 'בראשית א, א',
  String snippet = 'בראשית ברא',
  String? passage,
  List<String> matched = const [],
  double fused = 0.5,
  String source = 'both',
  int segment = 3,
  String? passageSource,
}) => SemanticResultSnapshot(
  rank: rank,
  title: title,
  reference: reference,
  segment: segment,
  isPdf: false,
  isUserBook: isUserBook,
  source: source,
  lexicalScore: 1.2,
  semanticScore: 0.8,
  fusedScore: fused,
  mergedCount: 0,
  snippetText: snippet,
  passageText: passage,
  passageTextSource: passageSource ?? (passage == null ? null : 'line'),
  matchedText: matched,
);
