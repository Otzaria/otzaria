// חוזה קבוע בין ממשק החיפוש הסמנטי לאוסף המשוב. שינוי שם/חתימה מחייב תיאום
// עם צד השרת (פרוטוקול search-feedback v1).

/// מצב ההסכמה לשליחת נתוני שימוש. `unknown` — טרם נשאל (או גרסת נוסח ישנה).
enum SearchFeedbackConsent { unknown, granted, declined }

/// סימון של המשתמש על תוצאה.
enum SearchFeedbackVote { like, dislike, cleared }

/// הדרך שבה נפתחה תוצאה.
enum SearchFeedbackOpenVia { click, preview, background, keyboard }

/// הסיבה שבגללה הסתיים העיון בתוצאה שנפתחה.
enum SearchFeedbackDwellEnd {
  tabClosed,
  tabSwitched,
  returnedToResults,
  appExit,
  capped,
}

/// השער של מצב החיפוש הסמנטי כולו: בלי הסכמה המצב אינו שמיש.
abstract interface class SearchFeedbackConsentStore {
  /// המצב הנוכחי (קריאה סינכרונית מההגדרות).
  SearchFeedbackConsent get consent;

  /// משדר את המצב החדש בכל שינוי.
  Stream<SearchFeedbackConsent> get changes;

  /// רושם הסכמה לגרסת הנוסח הנוכחית.
  Future<void> grant();

  /// רושם סירוב.
  Future<void> decline();

  /// מסרב, ומוחק את התור שלא נשלח ואת מפתח ההתקנה.
  Future<void> revoke();
}

class SemanticSearchParamsSnapshot {
  const SemanticSearchParamsSnapshot({
    required this.retrievalMode,
    required this.lexicalMode,
    required this.fuzzyMaxDistance,
    required this.grouping,
    required this.matchNikud,
    required this.matchTaamim,
    required this.facets,
    required this.allLibrary,
    required this.pageSize,
    this.ranking,
  });

  final String retrievalMode; // hybrid|semanticOnly|lexicalOnly
  final String lexicalMode; // exact|fuzzy
  final int fuzzyMaxDistance;
  final String? grouping; // sameSection|identicalText|null
  final bool matchNikud;
  final bool matchTaamim;
  final List<String> facets;
  final bool allLibrary;
  final int pageSize;

  /// אפשרויות הדירוג שהופעלו בפועל (מפה שטוחה); null = ברירות המחדל של המנוע.
  final Map<String, Object?>? ranking;
}

/// ה-fallbackReason היחיד שנשלח (טקסט המנוע חופשי ועלול להכיל נתיבים).
const String kSemanticDebugPreviewFallbackReason = 'debugPreview';

class SemanticSearchResponseSnapshot {
  const SemanticSearchResponseSnapshot({
    required this.executedMode,
    required this.semanticAvailable,
    required this.fallbackReason,
    this.fallbackKind,
    required this.latencyMs,
    required this.totalCount,
    required this.lexicalTotalCount,
    required this.groupCount,
    required this.countsAreExact,
    required this.truncated,
    required this.candidateWindowTruncated,
  });

  final String executedMode; // disabled|hybrid|semanticOnly|lexicalOnly
  final bool semanticAvailable;
  final String? fallbackReason;
  final String? fallbackKind;
  final int latencyMs;
  final int totalCount;
  final int lexicalTotalCount;
  final int? groupCount;
  final bool countsAreExact;
  final bool truncated;
  final bool candidateWindowTruncated;
}

class SemanticEngineSnapshot {
  const SemanticEngineSnapshot({
    this.state,
    this.modelFamilyId,
    this.modelQuantization,
    this.modelPackageChecksum,
    this.embeddingDim,
    this.vectorsReleaseTag,
    this.vectorsLibraryVersion,
    this.vectorSegments,
  });

  final String? state; // SemanticState name
  final String? modelFamilyId; // model.json family_id
  final String? modelQuantization; // int8|fp32
  final String? modelPackageChecksum;
  final int? embeddingDim;
  final String? vectorsReleaseTag;
  final int? vectorsLibraryVersion;
  final int? vectorSegments;
}

/// שאילתה אחת שנשלחה. יש ליצור חדשה (עם [searchSessionId] חדש) בכל שליחה.
class SemanticSearchContext {
  const SemanticSearchContext({
    required this.searchSessionId,
    required this.query,
    required this.startedAt,
    required this.params,
    required this.response,
    required this.engine,
  });

  final String searchSessionId;
  final String query;
  final DateTime startedAt;
  final SemanticSearchParamsSnapshot params;
  final SemanticSearchResponseSnapshot response;
  final SemanticEngineSnapshot engine;
}

class SemanticResultSnapshot {
  const SemanticResultSnapshot({
    required this.rank,
    required this.title,
    required this.reference,
    required this.segment,
    required this.isPdf,
    required this.isUserBook,
    required this.source,
    required this.lexicalScore,
    required this.semanticScore,
    required this.fusedScore,
    required this.mergedCount,
    required this.snippetText,
    this.passageText,
    this.passageTextSource,
    this.matchedText = const [],
  });

  final int rank; // 1-based over the whole list
  final String title;
  final String reference;
  final int segment;
  final bool isPdf;

  /// תוצאות מספרים אישיים לעולם אינן נשלחות.
  final bool isUserBook;
  final String source; // lexical|semantic|both
  final double? lexicalScore;
  final double? semanticScore;
  final double fusedScore;
  final int mergedCount;
  final String snippetText; // plain text, no html
  final String? passageText; // full paragraph, when resolvable
  final String? passageTextSource; // line|snippet
  final List<String> matchedText;
}

/// רושם "שגר ושכח": כל מתודה אינה עושה דבר בלי הסכמה.
/// לעולם אינו זורק ואינו חוסם את הממשק (התור אסינכרוני מבפנים).
abstract interface class SearchFeedbackRecorder {
  bool get isCollecting;

  void recordSearch(SemanticSearchContext context);

  void recordResultsShown(
    SemanticSearchContext context,
    int offset,
    List<SemanticResultSnapshot> results,
  );

  /// מחזיר את ה-openId שיש למסור ל-[recordDwell].
  String recordOpen(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackOpenVia via,
  );

  void recordDwell(
    SemanticSearchContext context,
    String openId,
    Duration dwell,
    SearchFeedbackDwellEnd end,
  );

  void recordVote(
    SemanticSearchContext context,
    SemanticResultSnapshot result,
    SearchFeedbackVote vote,
  );
}
