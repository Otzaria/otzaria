/// מודלים לייבוא נתוני-משתמש (דורות וקישורים) מקבצי CSV שהוכנו מראש.
///
/// ה-parser ([UserImportParser]) ממיר טקסט CSV למודלים האלה; שכבת ה-repository
/// כותבת אותם ל-user_books.db (דור → book_generation, קישור → user_link).
library;

import 'package:otzaria/models/book_source.dart';

/// שמות הדורות הקנוניים שמותר להזין בקובץ הדורות.
///
/// "שאר מפרשים" אינו ברשימה — הוא משמעו "בלי דור" ואין טעם לייבא אותו.
const Set<String> kCanonicalEraNames = {
  'תורה שבכתב',
  'חז"ל',
  'ראשונים',
  'אחרונים',
  'מחברי זמננו',
};

/// מיפוי תווית-סוג בעברית (בקובץ הקישורים) לשם connection_type ב-DB.
///
/// פירוש/תרגום הם תלויי-טקסט (מוצגים בפאנל המפרשים); הפניה/מקור מוצגים
/// בפאנל הקישורים. ראה [LinkTypes].
const Map<String, String> kHebrewConnectionTypes = {
  'פירוש': 'COMMENTARY',
  'תרגום': 'TARGUM',
  'הפניה': 'REFERENCE',
  'מקור': 'SOURCE',
  'אחר': 'OTHER',
};

/// שמות מבנה שמקבלים את תצוגת המבנה הרשמי המקביל: סימנים/סעיפים מוצגים
/// כסימני חלוקה בגוף הטקסט, ונושאים ככותרת מעל השורה.
const Map<String, String> kHebrewAltTocStructureKeys = {
  'סימנים': 'Simanim',
  'סעיפים': 'Seifim',
  'נושאים': 'Topic',
};

/// שורת כותרת שפוענחה מקובץ כותרות.
class ParsedHeading {
  /// מספר השורה בקובץ הכותרות (1-based), לדיווח שגיאות.
  final int rowNumber;

  /// כותרת הספר — רק בקובץ רוחבי (עמודת "ספר"); בקובץ פר-ספר null.
  final String? bookTitle;

  /// מזהה קטגוריה, אם צוין (לפירוק כפילות-כותרת).
  final int? categoryId;

  /// שם המבנה כפי שיוצג בלשונית (למשל "סימנים").
  final String structure;

  /// רמת הכותרת בעץ (1 = שורש).
  final int level;

  final String title;

  /// מספר השורה בספר (1-based), כשצוין.
  final int? lineNumber;

  /// טקסט שהשורה בספר פותחת בו, כשלא צוין מספר שורה.
  final String? anchorText;

  const ParsedHeading({
    required this.rowNumber,
    this.bookTitle,
    this.categoryId,
    required this.structure,
    required this.level,
    required this.title,
    this.lineNumber,
    this.anchorText,
  });
}

/// שורת גרסה שפוענחה מקובץ גרסאות. בקובץ שבתיקיית הספרים [primary] ו-[version]
/// הם נתיבי קבצים יחסיים לקובץ; בייבוא מההגדרות — כותרות ספרים.
/// ראשי ממקור לא-אישי ([primarySource]) הוא תמיד כותרת ספר בקטלוג.
class ParsedBookVersion {
  final int rowNumber;
  final String primary;
  final String version;

  /// שם הגרסה לתצוגה; כשחסר — שם ספר הגרסה.
  final String? label;
  final String? notes;
  final double? priority;

  /// מקור הספר הראשי (עמודת "מקור_ראשי"); ברירת המחדל — ספר אישי.
  final BookSource primarySource;

  /// נתיב קטגוריה לפירוק כפילות כותרת של ראשי לא-אישי ("תנך/תורה").
  final String? primaryCategoryPath;

  const ParsedBookVersion({
    required this.rowNumber,
    required this.primary,
    required this.version,
    this.label,
    this.notes,
    this.priority,
    this.primarySource = BookSource.user,
    this.primaryCategoryPath,
  });
}

/// רשומת גרסה כפי שהיא נשמרת ב-user_book_version.
///
/// ראשי אישי מזוהה ב-[primaryBookId]; ראשי ממקור אחר — ב-[primarySource]
/// ו-[primaryTitle] (+[primaryCategoryPath]), ונפתר מול הקטלוג בכל טעינה.
class UserBookVersionRecord {
  final int versionBookId;
  final int? primaryBookId;
  final String versionTitle;
  final String? versionNotes;
  final double? priority;
  final BookSource primarySource;
  final String? primaryTitle;
  final String? primaryCategoryPath;

  const UserBookVersionRecord({
    required this.versionBookId,
    required int this.primaryBookId,
    required this.versionTitle,
    this.versionNotes,
    this.priority,
  }) : primarySource = BookSource.user,
       primaryTitle = null,
       primaryCategoryPath = null;

  /// גרסה אישית של ספר מהספרייה הרשמית או ממסד מצורף.
  const UserBookVersionRecord.ofCatalogBook({
    required this.versionBookId,
    required this.primarySource,
    required String this.primaryTitle,
    this.primaryCategoryPath,
    required this.versionTitle,
    this.versionNotes,
    this.priority,
  }) : primaryBookId = null;

  /// הראשי אינו ספר אישי, ולכן נפתר לפי כותרת.
  bool get hasCatalogPrimary => !primarySource.isUser;
}

/// שורת דור שפוענחה מקובץ הדורות.
class ParsedBookGeneration {
  /// כותרת הספר האישי שאליו משויך הדור.
  final String bookTitle;

  /// שם הדור הקנוני (אחד מ-[kCanonicalEraNames]).
  final String eraName;

  /// שם המחבר, אם צוין.
  final String? author;

  /// מזהה קטגוריה, אם צוין (לפירוק כפילות-כותרת).
  final int? categoryId;

  const ParsedBookGeneration({
    required this.bookTitle,
    required this.eraName,
    this.author,
    this.categoryId,
  });
}

/// שורת קישור שפוענחה מקובץ הקישורים.
class ParsedUserLink {
  /// כותרת ספר המקור — רלוונטי רק בקובץ הרוחבי (עמודת "ספר_מקור").
  /// בקובץ פר-ספר הערך null וספר המקור נקבע מהקשר.
  final String? sourceBookTitle;

  /// האם ספר המקור אישי. ברירת המחדל true (מקור=ספר אישי) לשמירת תאימות
  /// לקבצים קיימים; מקור רשמי מסומן במפורש בעמודת "מקור_אישי".
  final bool sourceIsUserBook;

  /// מזהה קטגוריית המקור, אם צוין (רמז ל-resolution בין ספרים חד-שמיים).
  final int? sourceCategoryId;

  /// מספר השורה בספר המקור כפי שהמשתמש כתב (1-based).
  final int sourceLineNumber;

  /// כותרת ספר היעד (זיהוי לפי שם — תומך חוצה-DB).
  final String targetTitle;

  /// כתובת היעד כפי שנכתבה (ref), אם צוינה.
  final String? targetRef;

  /// שם connection_type ב-DB (אחד מערכי [kHebrewConnectionTypes]).
  final String connectionType;

  /// האם ספר היעד הוא ספר אישי (מפריד בין מרחבי ה-id).
  final bool targetIsUserBook;

  /// מזהה קטגוריית היעד, אם צוין (רמז ל-resolution).
  final int? targetCategoryId;

  const ParsedUserLink({
    this.sourceBookTitle,
    this.sourceIsUserBook = true,
    this.sourceCategoryId,
    required this.sourceLineNumber,
    required this.targetTitle,
    this.targetRef,
    required this.connectionType,
    this.targetIsUserBook = false,
    this.targetCategoryId,
  });
}

/// רשומת קישור-משתמש כפי שהיא נשמרת בטבלת user_link ב-user_books.db.
///
/// אינדקסי השורות הם 0-based (כמו line.lineIndex ב-DB); בעת בניית [Link]
/// לתצוגה מוסיפים 1 (כמו [getLinksForBookRange]).
class UserLinkRecord {
  /// כותרת ספר המקור — הזיהוי חוצה-DB (כמו היעד), כדי שגם ספר רשמי יוכל
  /// לשמש מקור בלי לכתוב ל-seforim.db.
  final String sourceTitle;

  /// מזהה קטגוריית המקור, אם ידוע (פירוק כפילות-כותרת).
  final int? sourceCategoryId;

  /// האם ספר המקור אישי (מפריד בין מרחבי ה-DB של המקור).
  final bool sourceIsUserBook;

  final int sourceLineIndex;
  final String targetTitle;
  final int? targetCategoryId;
  final bool targetIsUserBook;
  final String? targetRef;
  final int? targetLineIndex;
  final String connectionType;

  const UserLinkRecord({
    required this.sourceTitle,
    this.sourceCategoryId,
    this.sourceIsUserBook = true,
    required this.sourceLineIndex,
    required this.targetTitle,
    this.targetCategoryId,
    this.targetIsUserBook = false,
    this.targetRef,
    this.targetLineIndex,
    required this.connectionType,
  });
}

/// שורת קישור בפורמט ה-native של אוצריא (קובצי `<ספר>_links.json` מתיקיית
/// links). שני הצדדים מזוהים לפי כותרת בלבד — אישי/רשמי מאותר אוטומטית בייבוא.
class ParsedNativeLink {
  /// מספר השורה בספר הבסיס (line_index_1, 1-based).
  final int sourceLineNumber;

  /// כותרת ספר היעד (path_2 ללא סיומת).
  final String targetTitle;

  /// מספר השורה בספר היעד (line_index_2, 1-based).
  final int targetLineNumber;

  /// הכתובת העברית של היעד (heRef_2) — להצגה בלבד.
  final String? targetRef;

  /// שם connection_type ב-DB.
  final String connectionType;

  const ParsedNativeLink({
    required this.sourceLineNumber,
    required this.targetTitle,
    required this.targetLineNumber,
    this.targetRef,
    required this.connectionType,
  });
}

/// שגיאת פענוח של שורה בודדת, לדיווח מרוכז למשתמש.
class ImportRowError {
  /// מספר השורה בקובץ (1-based, כולל שורת הכותרת).
  final int lineNumber;

  /// הודעת השגיאה בעברית.
  final String message;

  const ImportRowError(this.lineNumber, this.message);

  @override
  String toString() => 'שורה $lineNumber: $message';
}

/// תוצאת פענוח: השורות התקינות שנקלטו + רשימת השגיאות (שורות פגומות מדולגות).
class ParseResult<T> {
  final List<T> rows;
  final List<ImportRowError> errors;

  const ParseResult(this.rows, this.errors);

  bool get hasErrors => errors.isNotEmpty;
}
