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

  /// מוריד את המודל או את הוקטורים (ראו [SemanticAvailability.progress]).
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

/// מה מורידים כרגע.
enum SemanticDownloadItem { model, vectors }

/// התקדמות ההורדה.
class SemanticDownloadProgress extends Equatable {
  final SemanticDownloadItem item;
  final int receivedBytes;

  /// `null` כשהגודל אינו ידוע.
  final int? totalBytes;

  const SemanticDownloadProgress({
    required this.item,
    required this.receivedBytes,
    this.totalBytes,
  });

  /// בין 0 ל-1, או `null` כשהגודל אינו ידוע.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [item, receivedBytes, totalBytes];
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
