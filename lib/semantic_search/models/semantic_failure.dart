/// סוגי הכשל של החיפוש הסמנטי ברמת האפליקציה.
///
/// הערכים הראשונים זהים בשמם ל-`SemanticErrorKind` של המנוע, והמתאם ממפה
/// לפי שם; סוג שהמנוע יוסיף בעתיד ממופה ל-[internal]. השאר הם כשלי
/// האפליקציה עצמה (הסכמה, רשת, הורדה).
enum SemanticFailureKind {
  // ── סוגי המנוע ──
  notConfigured,
  featureNotInBuild,
  artifactMissing,
  artifactCorrupt,
  artifactIncompatible,
  artifactNotPublished,
  insufficientDiskSpace,
  modelMissing,
  tokenizerMissing,
  modelInvalid,
  modelIdentityMismatch,
  onnxRuntimeMissing,
  onnxRuntimeUnusable,
  backendNotInBuild,
  sessionConflict,
  readOnlySession,
  reindexRequired,
  queryFailed,
  cancelled,
  invalidInput,
  internal,

  /// התקנה או קומפקטציה אחרת של אותו סט רצה; לנסות שוב אחר כך.
  vectorsBusy,

  // ── סוגי האפליקציה ──
  consentRequired,
  offline,
  network,
  rateLimited,
  checksumMismatch,
  releaseMalformed,
  modelSourceNotConfigured,
  libraryVersionUnknown,
  notReady,

  /// release של סוג שהאפליקציה עוד לא מתקינה (delta).
  unsupportedRelease,

  /// release בלי SHA-256 של המניפסט שפורסם מחוצה לו.
  releaseUnverified,

  /// הורדה, התקנה ומחיקה רצות רק בחלון הראשי.
  secondaryWindow,

  /// מיקום הספרייה מועבר כעת.
  libraryMoving;

  /// האם זה סוג של המנוע (`SemanticErrorKind`) ולא של האפליקציה.
  bool get isEngineKind => index <= vectorsBusy.index;

  /// ממפה שם סוג של המנוע לסוג האפליקציה; שם לא מוכר הופך ל-[internal].
  static SemanticFailureKind fromEngineName(String name) =>
      _byEngineName[name] ?? SemanticFailureKind.internal;

  static final Map<String, SemanticFailureKind> _byEngineName = {
    for (final kind in values)
      if (kind.isEngineKind) kind.name: kind,
  };
}

/// כשל של פעולה סמנטית. נזרק מכל מתודה ציבורית של שכבת החיפוש הסמנטי.
class SemanticFailure implements Exception {
  /// סוג הכשל, לפיו מחליטים מה להציג ומה להציע למשתמש.
  final SemanticFailureKind kind;

  /// הפירוט הטכני (לרוב באנגלית, מהמנוע) — ליומן ולדיווח, לא לתצוגה.
  final String message;

  /// השדה שהכשל נוגע לו, כשהמנוע ציין אותו.
  final String? field;

  const SemanticFailure(this.kind, [this.message = '', this.field]);

  @override
  String toString() =>
      'SemanticFailure(${kind.name}${field == null ? '' : ', $field'}): '
      '$message';
}
