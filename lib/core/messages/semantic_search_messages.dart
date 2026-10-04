import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';

/// ריכוז הודעות החיפוש הסמנטי: כשלים ומצבי הורדה.
///
/// ההודעות הן תבניות עם `{name}` (גם מפתחות התרגום); להצגה ישירה — [withName].
abstract class SemanticSearchMessages {
  /// [template] עם שם המצב במקום `{name}`.
  static String withName(String template) =>
      template.replaceAll('{name}', kSemanticSearchModeName);

  static const String corruptOrIncompatible =
      'נתוני {name} פגומים או אינם תואמים לגרסה זו. יש להוריד אותם מחדש.';
  static const String notOfficialRelease =
      'נתוני {name} שהתקבלו אינם הגרסה הרשמית. יש להוריד אותם מחדש.';
  static const String insufficientDiskSpace =
      'אין מספיק מקום פנוי בכונן לנתוני {name}.';
  static const String modelMissing =
      'רכיב החיפוש של {name} חסר או פגום. יש להוריד אותו מחדש.';
  static const String onnxRuntimeMissing =
      'רכיב ההרצה של {name} חסר בהתקנה. יש להתקין את התוכנה מחדש.';
  static const String onnxRuntimeUnusable =
      'רכיב ההרצה של {name} אינו נטען. יש להפעיל מחדש את התוכנה.';
  static const String notSupported = '{name} אינו נתמך בגרסה זו של התוכנה.';
  static const String consentRequired =
      '{name} מחייב הסכמה לשליחת נתוני שימוש אנונימיים.';
  static const String offline =
      'מצב לא מקוון פעיל. יש לכבות אותו כדי להוריד את נתוני {name}.';
  static const String network =
      'ההורדה נכשלה בגלל בעיית רשת. נסו שוב מאוחר יותר.';
  static const String rateLimited =
      'שרת ההורדות חסם זמנית את הבקשות. נסו שוב בעוד כשעה.';
  static const String checksumMismatch = 'הקובץ שהורד פגום. נסו להוריד שוב.';
  static const String modelSourceNotConfigured =
      'מקור ההורדה של רכיב החיפוש של {name} עוד לא הוגדר.';
  static const String libraryVersionUnknown =
      'לא ניתן לקבוע את גרסת הספרייה המותקנת.';
  static const String notReady = 'נתוני {name} עוד לא הותקנו.';
  static const String internal = 'אירעה שגיאה ב{name}.';
  static const String resultsRefreshed =
      'תוצאות החיפוש רועננו. מוצג העמוד הראשון.';
  static const String vectorsBusy =
      'נתוני {name} מתעדכנים כרגע. הניסיון יחזור מעצמו בעוד כמה דקות.';
  static const String unsupportedRelease =
      'גרסה זו של נתוני {name} אינה נתמכת עדיין. יש לעדכן את התוכנה.';
  static const String secondaryWindow =
      'את נתוני {name} אפשר להוריד ולמחוק רק מהחלון הראשי של התוכנה.';
  static const String libraryMoving =
      'מיקום הספרייה מועבר כעת. נסו שוב בסיום ההעברה.';

  // ── שלבי ההורדה (גם מפתחות התרגום) ──
  static const String downloadingComponent = 'מוריד את רכיב החיפוש';
  static const String downloadingData = 'מוריד את נתוני החיפוש';
  static const String installingData = 'מתקין את נתוני החיפוש';
  static const String checkingStagedFiles = 'בודק את הקבצים שהוכנו מראש';
  static const String stepTemplate = 'שלב {step} מתוך {count} — {action}';
  static const String percentTemplate = '{label} ({percent}%)';

  /// הפעולה של שלב [item].
  static String stepAction(SemanticDownloadItem item) => switch (item) {
    SemanticDownloadItem.model => downloadingComponent,
    SemanticDownloadItem.vectors => downloadingData,
    SemanticDownloadItem.install => installingData,
  };

  /// הפעולה המוצגת: בדיקת קובץ מוכן, או הפעולה של השלב.
  static String progressAction(SemanticDownloadProgress progress) =>
      progress.checking ? checkingStagedFiles : stepAction(progress.item);

  /// תווית השלב בעברית, עם מספר השלב כשיש יותר משלב אחד, ואחוז כולל בהורדה.
  static String progressLabel(SemanticDownloadProgress progress) {
    final action = progressAction(progress);
    final label = progress.stepCount > 1
        ? stepTemplate
              .replaceAll('{step}', '${progress.step}')
              .replaceAll('{count}', '${progress.stepCount}')
              .replaceAll('{action}', action)
        : action;
    final percent = progressPercent(progress);
    return percent == null
        ? label
        : percentTemplate
              .replaceAll('{label}', label)
              .replaceAll('{percent}', percent);
  }

  /// האחוז הכולל להצגה, או `null` בהתקנה ובגודל לא ידוע.
  static String? progressPercent(SemanticDownloadProgress progress) {
    final fraction = progress.fraction;
    if (fraction == null || progress.item == SemanticDownloadItem.install) {
      return null;
    }
    return (fraction * 100).toStringAsFixed(0);
  }

  /// כל ההודעות של [failure] — לבדיקות הכיסוי של התרגום.
  static const List<String> allFailureMessages = [
    corruptOrIncompatible,
    notOfficialRelease,
    insufficientDiskSpace,
    modelMissing,
    onnxRuntimeMissing,
    onnxRuntimeUnusable,
    notSupported,
    consentRequired,
    offline,
    network,
    rateLimited,
    checksumMismatch,
    modelSourceNotConfigured,
    libraryVersionUnknown,
    notReady,
    internal,
    vectorsBusy,
    unsupportedRelease,
    secondaryWindow,
    libraryMoving,
  ];

  /// ההודעה למשתמש עבור [kind].
  static String failure(SemanticFailureKind kind) => switch (kind) {
    SemanticFailureKind.artifactMissing ||
    SemanticFailureKind.notConfigured ||
    SemanticFailureKind.notReady => notReady,
    SemanticFailureKind.artifactCorrupt ||
    SemanticFailureKind.artifactIncompatible ||
    SemanticFailureKind.releaseMalformed => corruptOrIncompatible,
    SemanticFailureKind.artifactNotPublished ||
    SemanticFailureKind.releaseUnverified => notOfficialRelease,
    SemanticFailureKind.vectorsBusy => vectorsBusy,
    SemanticFailureKind.unsupportedRelease => unsupportedRelease,
    SemanticFailureKind.secondaryWindow => secondaryWindow,
    SemanticFailureKind.libraryMoving => libraryMoving,
    SemanticFailureKind.insufficientDiskSpace => insufficientDiskSpace,
    SemanticFailureKind.modelMissing ||
    SemanticFailureKind.tokenizerMissing ||
    SemanticFailureKind.modelInvalid ||
    SemanticFailureKind.modelIdentityMismatch => modelMissing,
    SemanticFailureKind.onnxRuntimeMissing => onnxRuntimeMissing,
    SemanticFailureKind.onnxRuntimeUnusable ||
    SemanticFailureKind.sessionConflict => onnxRuntimeUnusable,
    SemanticFailureKind.featureNotInBuild ||
    SemanticFailureKind.backendNotInBuild => notSupported,
    SemanticFailureKind.consentRequired => consentRequired,
    SemanticFailureKind.offline => offline,
    SemanticFailureKind.network => network,
    SemanticFailureKind.rateLimited => rateLimited,
    SemanticFailureKind.checksumMismatch => checksumMismatch,
    SemanticFailureKind.modelSourceNotConfigured => modelSourceNotConfigured,
    SemanticFailureKind.libraryVersionUnknown => libraryVersionUnknown,
    SemanticFailureKind.readOnlySession ||
    SemanticFailureKind.reindexRequired ||
    SemanticFailureKind.queryFailed ||
    SemanticFailureKind.cancelled ||
    SemanticFailureKind.invalidInput ||
    SemanticFailureKind.internal => internal,
  };
}
