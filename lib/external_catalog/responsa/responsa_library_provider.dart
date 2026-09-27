import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
import 'package:otzaria/external_catalog/responsa/responsa_failure.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/responsa_catalog_repository.dart';
import 'package:otzaria/models/books.dart';

/// תוצאת ניסיון פתיחה של ספר חיצוני.
///
/// לעולם אינה חריג: כשל בפתיחה של ספק חיצוני (תוכנה שאינה מותקנת, גשר
/// שנפל, הפניה שלא נותחה) חייב להגיע ל-UI כערך, לא כ-exception שמפיל את
/// אוצריא.
class ExternalOpenResult {
  final bool ok;

  /// קוד שגיאה יציב, כשהפתיחה נכשלה.
  final String? errorCode;

  /// הודעה למשתמש. ריקה כשהפתיחה הצליחה.
  final String? message;

  const ExternalOpenResult.success()
    : ok = true,
      errorCode = null,
      message = null;

  const ExternalOpenResult.failure(this.errorCode, [this.message]) : ok = false;
}

/// ספק פרויקט השו"ת.
///
/// שתי שכבות נפרדות, ובכוונה:
///
/// * **קטלוג** — SQLite מקומי שנבנה מההתקנה של המשתמש. עצם קיום הרשומה
///   בקטלוג אומר שהספר קיים במהדורה שממנה הקטלוג נבנה; אין לבדוק קובץ,
///   כי כל הספרים יושבים בארכיון אחד ואין התקנה חלקית ברמת ספר.
/// * **שליטה בתוכנה** — נדרשת רק לפתיחה, ורצה באיזולט רקע בתוך אוצריא.
///   אין רכיב חיצוני להתקין ואין מה להגדיר בפרויקט השו"ת.
class ResponsaLibraryProvider {
  final ResponsaCatalogRepository catalog;
  final ResponsaController controller;

  ResponsaLibraryProvider({required this.catalog, required this.controller});

  /// פותח את הספר בתוכנה, בתחילתו.
  Future<ExternalOpenResult> open(Book book) async {
    final key = _keyOf(book);
    if (key == null) {
      return const ExternalOpenResult.failure(
        'notAResponsaBook',
        'הספר אינו ספר של פרויקט השו"ת',
      );
    }

    final references = await catalog.openRefsFor(key);
    if (references.isEmpty) {
      return ExternalOpenResult.failure(
        'notInCatalog',
        'הספר "${book.title}" אינו נמצא בקטלוג בר אילן שבמחשב. '
            'ייתכן שהקטלוג נבנה ממהדורה אחרת — יש לרענן אותו בהגדרות.',
      );
    }

    final report = await controller.openBook(
      references,
      expectedTitle: book.title,
      installPath: await catalog.sourceInstallPath(),
    );
    if (report.ok) return const ExternalOpenResult.success();
    return ExternalOpenResult.failure(
      report.failure?.name ?? 'openFailed',
      messageFor(
        report.failure,
        title: book.title,
        tried: report.triedRefs,
        detail: report.message,
      ),
    );
  }

  /// המפתח בקטלוג, או `null` לספר שאינו של בר אילן.
  static String? _keyOf(Book book) {
    final parsed = ExternalProviderRegistry.parse(book.externalLibraryId);
    if (parsed?.provider.kind != ExternalProviderKind.responsa) return null;
    return parsed!.value;
  }

  /// הודעת הכשל שהמשתמש רואה.
  ///
  /// שלושת המרכיבים — מה נכשל, על איזה ספר, ומה אפשר לעשות — נמסרים
  /// תמיד. "פתיחת הספר נכשלה" אינו מאפשר למשתמש שום צעד הבא, ובפרויקט
  /// השו"ת יש לו כמה צעדים אמיתיים: לסגור חלונות, לרענן קטלוג, או לדעת
  /// שהספר פשוט אינו במהדורה שברשותו.
  static String messageFor(
    ResponsaFailure? failure, {
    String? title,
    List<String> tried = const [],
    String? detail,
  }) {
    final book = (title == null || title.isEmpty) ? 'הספר' : '"$title"';
    final attempts = tried.isEmpty
        ? ''
        : ' ההפניות שנוסו: ${tried.take(4).join(' · ')}.';
    return switch (failure) {
      // כאן הבקר יודע יותר מהספק: הוא מבחין בין "אינו מותקן", "ההפעלה
      // כבויה בהגדרות" ו"לא עלה בזמן", והמשתמש צריך את ההבחנה הזו.
      ResponsaFailure.responsaNotRunning =>
        detail ??
            'בר אילן אינו פעיל ולא ניתן היה להפעיל אותו. '
                'יש לפתוח את פרויקט השו"ת ולנסות שוב.',
      ResponsaFailure.citationDialogNotFound =>
        'בר אילן לא פתח את חלון "עיון", ולכן לא ניתן היה לפתוח את $book. '
            'ייתכן שדיאלוג אחר פתוח בתוכנה וממתין לתשובה — יש לסגור אותו '
            'ולנסות שוב.',
      ResponsaFailure.referenceNotParsed =>
        'בר אילן לא זיהה את $book.$attempts '
            'ייתכן שהספר אינו קיים במהדורה המותקנת, או שיש לרענן את '
            'הקטלוג בהגדרות.',
      ResponsaFailure.openedWrongBook =>
        'בר אילן פתח ספר אחר במקום $book, והפתיחה בוטלה כדי שלא ייפתח '
            'ספר שגוי.${detail == null ? '' : ' ($detail)'}',
      ResponsaFailure.mdiWindowLimitReached =>
        'בבר אילן פתוחים כבר חלונות רבים והוא מפסיק לפתוח חדשים, ולכן '
            '$book לא נפתח. יש לסגור בו כמה חלונות ולנסות שוב.',
      ResponsaFailure.resultsNotCleared =>
        'רשימת התוצאות בבר אילן לא התנקתה, ולכן לא ניתן לדעת אם התוצאה '
            'שייכת ל$book. הפתיחה בוטלה; נסה שוב.',
      ResponsaFailure.timeout =>
        'בר אילן לא הגיב בזמן בעת פתיחת $book. ייתכן שהוא עסוק או ממתין '
            'לתשובה בחלון אחר.',
      ResponsaFailure.cancelled => 'הפתיחה בוטלה.',
      null => 'פתיחת $book בבר אילן נכשלה.${detail == null ? '' : ' $detail'}',
    };
  }
}
