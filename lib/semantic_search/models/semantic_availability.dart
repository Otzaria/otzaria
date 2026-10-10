import 'package:equatable/equatable.dart';

import 'semantic_failure.dart';

/// שלב הזמינות של מצב החיפוש הסמנטי.
enum SemanticAvailabilityPhase {
  /// לא מציגים את המצב כלל (ראו [SemanticAvailability.hiddenReason]).
  hidden,

  /// חסרה הסכמה לשליחת נתוני שימוש; בלעדיה המצב אינו שמיש.
  consentRequired,

  /// המודל או הוקטורים עוד לא הורדו.
  needsDownload,

  /// סט הוקטורים של גרסת הספרייה המותקנת עוד לא פורסם.
  vectorsNotPublished,

  /// מוריד את הנתונים (ראו [SemanticAvailability.progress]).
  downloading,

  /// מתקין את הוקטורים שהורדו.
  installing,

  /// המודל והוקטורים מותקנים; החיפוש נפתח בשימוש הראשון.
  ready,

  /// הפעולה האחרונה נכשלה (ראו [SemanticAvailability.failure]).
  failed,
}

/// למה המצב מוסתר.
enum SemanticHiddenReason {
  /// Android, iOS, או macOS שאינו arm64 מגרסה 14.
  unsupportedPlatform,

  /// מנוע החיפוש בבנייה הזו אינו תומך בוקטורים מותקנים.
  engineNotInBuild,
}

/// שלב בעבודת ההורדה וההתקנה.
enum SemanticDownloadItem {
  /// הורדת רכיב החיפוש (המודל).
  model,

  /// הורדת נתוני החיפוש (הוקטורים).
  vectors,

  /// התקנת הנתונים שהורדו.
  install,
}

/// התקדמות כוללת של עבודה אחת: הבתים נספרים על פני כל השלבים יחד, כך
/// שהאחוז אינו מתאפס במעבר משלב לשלב.
class SemanticDownloadProgress extends Equatable {
  /// השלב הנוכחי.
  final SemanticDownloadItem item;

  /// בתים שהורדו בכל העבודה עד עכשיו.
  final int receivedBytes;

  /// סך הבתים של כל העבודה; `null` כשאינו ידוע.
  final int? totalBytes;

  /// מספר השלב (מ-1) מתוך [stepCount]; שלבים שדולגו אינם נספרים.
  final int step;
  final int stepCount;

  /// בודק קובץ שהוכן מראש בשלב [item] (hash ארוך בלי מדידה).
  final bool checking;

  const SemanticDownloadProgress({
    required this.item,
    required this.receivedBytes,
    this.totalBytes,
    this.step = 1,
    this.stepCount = 1,
    this.checking = false,
  });

  /// אותה התקדמות, בבדיקת קובץ מוכן או אחריה.
  SemanticDownloadProgress withChecking(bool value) => SemanticDownloadProgress(
    item: item,
    receivedBytes: receivedBytes,
    totalBytes: totalBytes,
    step: step,
    stepCount: stepCount,
    checking: value,
  );

  /// בין 0 ל-1, או `null` כשהגודל אינו ידוע או בבדיקה.
  double? get fraction {
    final total = totalBytes;
    if (checking || total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [
    item,
    receivedBytes,
    totalBytes,
    step,
    stepCount,
    checking,
  ];
}

/// מצב הזמינות של החיפוש הסמנטי, כפי שהממשק צריך אותו.
///
/// [consentGranted] מחושב תמיד, גם כשהשלב אחר, כדי שהממשק יבדיל בין "חסרים
/// מנוע/מודל/וקטורים" ([isMissingEngineOrData]) לבין "חסרה הסכמה".
class SemanticAvailability extends Equatable {
  final SemanticAvailabilityPhase phase;
  final bool consentGranted;
  final SemanticHiddenReason? hiddenReason;
  final SemanticDownloadProgress? progress;
  final SemanticFailure? failure;

  /// גרסת הספרייה שהוקטורים שלה עוד לא פורסמו.
  final int? unpublishedLibraryVersion;

  /// המשתמש עצר את ההורדה; עדכוני ספרייה לא יחדשו אותה עד שיבקש שוב.
  final bool pausedByUser;

  /// חלון משני: מציגים מצב, אבל הורדה ומחיקה רק מהחלון הראשי.
  final bool isSecondaryWindow;

  const SemanticAvailability({
    required this.phase,
    required this.consentGranted,
    this.hiddenReason,
    this.progress,
    this.failure,
    this.unpublishedLibraryVersion,
    this.pausedByUser = false,
    this.isSecondaryWindow = false,
  });

  /// לפני הבדיקה הראשונה.
  static const SemanticAvailability initial = SemanticAvailability(
    phase: SemanticAvailabilityPhase.hidden,
    consentGranted: false,
  );

  /// אפשר לחפש: הכול מותקן והמשתמש הסכים.
  bool get isUsable =>
      phase == SemanticAvailabilityPhase.ready && consentGranted;

  /// חסרים רק המנוע, המודל או הוקטורים — לא ההסכמה ולא הפלטפורמה.
  ///
  /// תצוגה מקדימה בפיתוח מותרת כש-`kDebugMode && consentGranted &&
  /// isMissingEngineOrData`.
  bool get isMissingEngineOrData => switch (phase) {
    SemanticAvailabilityPhase.hidden =>
      hiddenReason == SemanticHiddenReason.engineNotInBuild,
    SemanticAvailabilityPhase.consentRequired ||
    SemanticAvailabilityPhase.ready => false,
    SemanticAvailabilityPhase.needsDownload ||
    SemanticAvailabilityPhase.vectorsNotPublished ||
    SemanticAvailabilityPhase.downloading ||
    SemanticAvailabilityPhase.installing ||
    SemanticAvailabilityPhase.failed => true,
  };

  @override
  List<Object?> get props => [
    phase,
    consentGranted,
    hiddenReason,
    progress,
    failure?.kind,
    unpublishedLibraryVersion,
    pausedByUser,
    isSecondaryWindow,
  ];
}
