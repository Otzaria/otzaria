import 'package:equatable/equatable.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticSearchResponse;

import 'semantic_failure.dart';

/// מצב ה-session הסמנטי של המנוע, בשפת האפליקציה.
enum SemanticBackendState {
  /// הבנייה אינה כוללת חיפוש סמנטי.
  notInBuild,

  /// אין session פתוח.
  notConfigured,

  /// סט וקטורים פתוח ומשרת חיפוש.
  ready,

  /// מצב של session פיתוח (וקטורים שנבנו במכשיר) — לא במסלול האפליקציה.
  other,
}

/// תמונת מצב של המנוע הסמנטי.
class SemanticBackendStatus extends Equatable {
  final SemanticBackendState state;

  /// שם המצב כפי שהמנוע מדווח אותו — לטלמטריה.
  final String rawState;

  /// סוג הכשל האחרון, כשהמנוע מדווח עליו.
  final SemanticFailureKind? errorKind;
  final String? lastError;

  /// גרסת הספרייה של הסט הפתוח; `null` כשאין סט פתוח.
  final int? vectorsLibraryVersion;
  final int vectorSegments;
  final bool needsCompaction;

  const SemanticBackendStatus({
    required this.state,
    required this.rawState,
    this.errorKind,
    this.lastError,
    this.vectorsLibraryVersion,
    this.vectorSegments = 0,
    this.needsCompaction = false,
  });

  /// מצב של בנייה בלי חיפוש סמנטי.
  static const SemanticBackendStatus notInBuild = SemanticBackendStatus(
    state: SemanticBackendState.notInBuild,
    rawState: 'notInBuild',
    errorKind: SemanticFailureKind.featureNotInBuild,
  );

  @override
  List<Object?> get props => [
    state,
    rawState,
    errorKind,
    lastError,
    vectorsLibraryVersion,
    vectorSegments,
    needsCompaction,
  ];
}

/// segment אחד בסט הוקטורים המותקן.
class SemanticSegmentSummary extends Equatable {
  final String id;

  /// `base`, `delta` או `compacted`.
  final String kind;
  final int fromLibraryVersion;
  final int toLibraryVersion;
  final int sizeBytes;

  const SemanticSegmentSummary({
    required this.id,
    required this.kind,
    required this.fromLibraryVersion,
    required this.toLibraryVersion,
    required this.sizeBytes,
  });

  @override
  List<Object?> get props => [
    id,
    kind,
    fromLibraryVersion,
    toLibraryVersion,
    sizeBytes,
  ];
}

/// מה מותקן בתיקיית הוקטורים (`semanticVectorsInfo`).
class SemanticVectorsSummary extends Equatable {
  /// האם מותקן שם סט; כל שאר השדות ריקים כשלא.
  final bool present;
  final String identityDigest;
  final int libraryVersion;
  final String libraryReleaseTag;
  final List<SemanticSegmentSummary> segments;
  final int bytesOnDisk;
  final bool needsCompaction;

  /// הדור החי לא נפתח, והדור שלפניו נפתח במקומו.
  final bool recoveredFromPrevious;

  const SemanticVectorsSummary({
    required this.present,
    this.identityDigest = '',
    this.libraryVersion = 0,
    this.libraryReleaseTag = '',
    this.segments = const [],
    this.bytesOnDisk = 0,
    this.needsCompaction = false,
    this.recoveredFromPrevious = false,
  });

  /// אין סט מותקן.
  static const SemanticVectorsSummary absent = SemanticVectorsSummary(
    present: false,
  );

  @override
  List<Object?> get props => [
    present,
    identityDigest,
    libraryVersion,
    libraryReleaseTag,
    segments,
    bytesOnDisk,
    needsCompaction,
    recoveredFromPrevious,
  ];
}

/// בקשת התקנה של release וקטורים (`installSemanticVectors`).
class SemanticInstallRequest extends Equatable {
  final String vectorsDir;
  final String segmentPath;
  final String manifestJson;
  final String? publishedManifestSha256;
  final String modelIdentityJson;

  const SemanticInstallRequest({
    required this.vectorsDir,
    required this.segmentPath,
    required this.manifestJson,
    required this.publishedManifestSha256,
    required this.modelIdentityJson,
  });

  @override
  List<Object?> get props => [
    vectorsDir,
    segmentPath,
    manifestJson,
    publishedManifestSha256,
    modelIdentityJson,
  ];
}

/// מה ההתקנה עשתה.
class SemanticInstallSummary extends Equatable {
  /// `base`, `delta` או `compacted`.
  final String kind;
  final int libraryVersion;
  final int segments;
  final int bytesOnDisk;
  final bool needsCompaction;
  final bool alreadyApplied;

  const SemanticInstallSummary({
    required this.kind,
    required this.libraryVersion,
    required this.segments,
    required this.bytesOnDisk,
    required this.needsCompaction,
    required this.alreadyApplied,
  });

  @override
  List<Object?> get props => [
    kind,
    libraryVersion,
    segments,
    bytesOnDisk,
    needsCompaction,
    alreadyApplied,
  ];
}

/// כמה משורות האינדקס הפתוח מכוסות בוקטורים (`semanticCoverage`).
class SemanticCoverageSummary extends Equatable {
  final int liveKeyedLines;
  final int coveredLines;
  final int booksLive;
  final int booksCovered;
  final int vectorsLibraryVersion;
  final double ratio;

  const SemanticCoverageSummary({
    required this.liveKeyedLines,
    required this.coveredLines,
    required this.booksLive,
    required this.booksCovered,
    required this.vectorsLibraryVersion,
    required this.ratio,
  });

  @override
  List<Object?> get props => [
    liveKeyedLines,
    coveredLines,
    booksLive,
    booksCovered,
    vectorsLibraryVersion,
    ratio,
  ];
}

/// בקשת פתיחה של סט הוקטורים והמודל (`openSemanticArtifact`).
class SemanticOpenRequest extends Equatable {
  final String vectorsDir;
  final String modelPath;
  final String modelIdentityJson;

  /// ONNX Runtime שמצורף לאפליקציה; `null` — המנוע מחפש בעצמו.
  final String? onnxRuntimePath;

  const SemanticOpenRequest({
    required this.vectorsDir,
    required this.modelPath,
    required this.modelIdentityJson,
    this.onnxRuntimePath,
  });

  @override
  List<Object?> get props => [
    vectorsDir,
    modelPath,
    modelIdentityJson,
    onnxRuntimePath,
  ];
}

/// אסטרטגיית האיחוד של הדירוג ההיברידי.
enum SemanticFusion { weighted, rrf, adaptive }

/// כל פרמטרי הדירוג ההיברידי, כברירות המחדל של המנוע.
///
/// ברירות המחדל לא כוילו; האובייקט קיים כדי לכייל מהאפליקציה בלי שחרור
/// מנוע. `null` במקום אובייקט = הדירוג של המנוע.
class SemanticRankingConfig extends Equatable {
  final SemanticFusion fusion;
  final int rrfK;
  final double? alphaOverride;
  final double alphaQuotedPhrase;
  final double alphaExactReference;
  final double alphaShort;
  final double alphaMixed;
  final double alphaConceptual;
  final double alphaUnknown;
  final double bm25SaturationK;
  final double semanticThreshold;
  final double agreementBonus;
  final double phraseMatchBonus;
  final double rareTermBonus;
  final double sectionCoverageBonus;
  final double duplicatePenalty;
  final bool metadataRankingEnabled;
  final double candidateWindowMultiplier;

  const SemanticRankingConfig({
    this.fusion = SemanticFusion.weighted,
    this.rrfK = 60,
    this.alphaOverride,
    this.alphaQuotedPhrase = 1.0,
    this.alphaExactReference = 0.85,
    this.alphaShort = 0.7,
    this.alphaMixed = 0.5,
    this.alphaConceptual = 0.3,
    this.alphaUnknown = 0.5,
    this.bm25SaturationK = 10.0,
    this.semanticThreshold = 0.0,
    this.agreementBonus = 0.1,
    this.phraseMatchBonus = 0.0,
    this.rareTermBonus = 0.0,
    this.sectionCoverageBonus = 0.0,
    this.duplicatePenalty = 0.0,
    this.metadataRankingEnabled = false,
    this.candidateWindowMultiplier = 2.0,
  });

  /// השדה `ranking` של הטלמטריה: שטוח, ו-`alphaByQueryType` כמפה מקוננת אחת.
  Map<String, Object?> toSnapshotMap() => {
    'fusionStrategy': fusion.name,
    'rrfK': rrfK,
    'alphaOverride': alphaOverride,
    'alphaByQueryType': {
      'quotedPhrase': alphaQuotedPhrase,
      'exactReference': alphaExactReference,
      'short': alphaShort,
      'mixed': alphaMixed,
      'conceptual': alphaConceptual,
      'unknown': alphaUnknown,
    },
    'bm25SaturationK': bm25SaturationK,
    'semanticThreshold': semanticThreshold,
    'agreementBonus': agreementBonus,
    'phraseMatchBonus': phraseMatchBonus,
    'rareTermBonus': rareTermBonus,
    'sectionCoverageBonus': sectionCoverageBonus,
    'duplicatePenalty': duplicatePenalty,
    'metadataRankingEnabled': metadataRankingEnabled,
    'candidateWindowMultiplier': candidateWindowMultiplier,
  };

  @override
  List<Object?> get props => [toSnapshotMap()];
}

/// תוצאת חיפוש סמנטי.
class SemanticSearchOutcome {
  /// התשובה של המנוע: התוצאות, הספירות והמצב שבוצע בפועל.
  final SemanticSearchResponse response;

  /// למה המסלול הסמנטי לא שירת, כשהתבקש ולא שירת; `null` כששירת.
  final SemanticFailureKind? fallbackKind;

  const SemanticSearchOutcome({required this.response, this.fallbackKind});
}

/// ביטול של פעולה סמנטית אחת (חיפוש, התקנה, אימות).
///
/// המתאם למנוע מקשר אותו ל-token של המנוע; ביטול אינו ניתן לאיפוס.
class SemanticCancelHandle {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  /// האם [cancel] נקרא.
  bool get isCancelled => _cancelled;

  /// מבטל את הפעולה; קריאה חוזרת אינה משנה דבר.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// רושם [listener] לביטול ומחזיר פונקציה שמסירה אותו. כשכבר בוטל —
  /// [listener] נקרא מיד.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}
