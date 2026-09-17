import 'package:otzaria/external_catalog/providers/external_provider_capabilities.dart';
import 'package:otzaria/external_catalog/providers/external_provider_registry.dart';
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

/// ספק ספרים חיצוני: טעינת קטלוג, בדיקת זמינות ופתיחה.
///
/// אין לכפות על כל הספקים אסטרטגיית אחסון אחת. אוצר החכמה והיברובוקס
/// נטענים מקטלוג משותף שמתעדכן מהרשת; פרויקט השו"ת נבנה מקומית מההתקנה
/// של המשתמש. המשותף הוא החוזה שכאן, לא המימוש.
abstract interface class ExternalLibraryProvider {
  /// מזהה טקסטואלי יציב (`otzar`, `hebrewbooks`, `responsa`).
  String get id;

  String get displayName;

  /// התחילית של `externalLibraryId` (`oh`, `hb`, `rp`).
  String get idPrefix;

  /// נתיב הלוגו, או `null` לספק בלי לוגו ייעודי.
  String? get iconAsset;

  ExternalProviderCapabilities get capabilities;

  /// התיאור הסטטי מתוך [ExternalProviderRegistry].
  ExternalProviderDescriptor get descriptor;

  /// כל ספרי הספק. ספק שאינו זמין מחזיר רשימה ריקה, לא חריג.
  Future<List<Book>> loadBooks();

  /// האם ניתן לפתוח את הספר הזה **כרגע** — קטלוג קיים, תוכנה מותקנת וכו'.
  Future<bool> canOpen(Book book);

  Future<ExternalOpenResult> openBook(Book book);
}
