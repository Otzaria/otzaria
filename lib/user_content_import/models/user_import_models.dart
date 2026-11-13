/// מודלים לייבוא נתוני-משתמש (דורות וקישורים) מקבצי CSV שהוכנו מראש.
///
/// ה-parser ([UserImportParser]) ממיר טקסט CSV למודלים האלה; שכבת ה-repository
/// כותבת אותם ל-user_books.db (דור → book_generation, קישור → user_link).
library;

import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';

/// קובץ ייבוא אחרי שתוכנו נקרא. הייבוא עובד על הצורה הזו ולא על [File], כדי
/// שאותו מסלול ישרת גם קובץ שנבחר עכשיו וגם קובץ ששמור בספריית הייבוא.
class ImportedFile {
  /// שם הקובץ בלבד (בלי נתיב) — הוא שקובע את סוג התוכן.
  final String name;
  final String content;

  /// נבחר בייבוא הנוכחי, להבדיל מקובץ שמור שרק נבנה מחדש איתו.
  final bool selected;

  const ImportedFile({
    required this.name,
    required this.content,
    this.selected = false,
  });
}

/// סוג התוכן שקובץ ייבוא נושא, לפי שמו. משמש להצגה ולקיבוץ בהגדרות.
enum UserImportKind { links, generations, headings, versions }

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

/// סוגי ה-native המותרים — ערכי ה-ConnectionType של מחולל ה-DB.
const Set<String> kNativeConnectionTypes = {
  LinkTypes.commentary,
  LinkTypes.superCommentary,
  LinkTypes.targum,
  LinkTypes.reference,
  LinkTypes.source,
  LinkTypes.midrash,
  LinkTypes.quotation,
  LinkTypes.mesoratHashas,
  LinkTypes.einMishpat,
  LinkTypes.diburHamatchil,
  LinkTypes.parshanut,
  LinkTypes.mishnahInTalmud,
  LinkTypes.related,
  LinkTypes.other,
  LinkTypes.linker,
  LinkTypes.sifreiMitzvot,
  LinkTypes.essay,
  LinkTypes.allusion,
  LinkTypes.liturgy,
  LinkTypes.elucidation,
  LinkTypes.explication,
  LinkTypes.law,
  LinkTypes.summary,
  LinkTypes.footnotes,
};

/// נגזר מ-[LinkTypes.hebrewLabels], כך שסוג חדש ב-DB נתמך בייבוא מיד.
/// [LinkTypes.altToc] מוחרג: הוא תוצר תוכן-עניינים חלופי ולא נשמר ב-user_link.
final Set<String> kImportableConnectionTypes = Set.unmodifiable(
  LinkTypes.hebrewLabels.keys.where((type) => type != LinkTypes.altToc),
);

/// תווית עברית (כפי שמוצגת בפאנל הקישורים) ← connection_type ב-DB.
/// הכינויים של [kLegacyHebrewConnectionTypes] גוברים על תווית רשמית זהה.
final Map<String, String> kHebrewConnectionTypes =
    _buildHebrewConnectionTypes();

Map<String, String> _buildHebrewConnectionTypes() {
  final byLabel = <String, String>{};
  for (final entry in LinkTypes.hebrewLabels.entries) {
    if (!kImportableConnectionTypes.contains(entry.key)) continue;
    // putIfAbsent ולא השמה: תווית משותפת נפתרת לסוג הראשון בסדר ההכרזה.
    byLabel.putIfAbsent(entry.value, () => entry.key);
  }
  byLabel.addAll(kLegacyHebrewConnectionTypes);
  return Map.unmodifiable(byLabel);
}

/// כינויים שאינם התווית הרשמית ("הפניה" = "עיון", "אחר" = "לא מסווג"), כדי
/// שקובצי CSV קיימים של משתמשים ימשיכו להיקלט.
const Map<String, String> kLegacyHebrewConnectionTypes = {
  'פירוש': LinkTypes.commentary,
  'תרגום': LinkTypes.targum,
  'הפניה': LinkTypes.reference,
  'מקור': LinkTypes.source,
  'אחר': LinkTypes.other,
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

  /// שם connection_type ב-DB (אחד מערכי [LinkTypes.hebrewConnectionTypes]).
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

  /// אופסט עוגן בצד המקור, כפי שנכתב ב-native JSON (תווים גולמיים).
  final int? anchorStart;
  final int? anchorEnd;

  /// אות העוגן שנגזרה מ-heRef_2, למשל "א".
  final String? anchorLabel;

  /// סוף טווח שורות בצד המקור/היעד, באינדקס 0-based.
  final int? sourceLineIndexEnd;
  final int? targetLineIndexEnd;
  final String? targetRefEnd;
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
    this.anchorStart,
    this.anchorEnd,
    this.anchorLabel,
    this.sourceLineIndexEnd,
    this.targetLineIndexEnd,
    this.targetRefEnd,
    required this.connectionType,
  });

  /// עותק שבו שדות תצוגה וטווח *חסרים* מושלמים מ-[other]; ערך קיים לעולם
  /// אינו נדרס. משמש במיזוג שני הצדדים של אותו קישור.
  UserLinkRecord fillMissingFrom(UserLinkRecord other) => UserLinkRecord(
    sourceTitle: sourceTitle,
    sourceCategoryId: sourceCategoryId,
    sourceIsUserBook: sourceIsUserBook,
    sourceLineIndex: sourceLineIndex,
    targetTitle: targetTitle,
    targetCategoryId: targetCategoryId,
    targetIsUserBook: targetIsUserBook,
    targetRef: targetRef ?? other.targetRef,
    targetLineIndex: targetLineIndex,
    anchorStart: anchorStart,
    anchorEnd: anchorEnd ?? other.anchorEnd,
    anchorLabel: anchorLabel ?? other.anchorLabel,
    sourceLineIndexEnd: sourceLineIndexEnd ?? other.sourceLineIndexEnd,
    targetLineIndexEnd: targetLineIndexEnd ?? other.targetLineIndexEnd,
    targetRefEnd: targetRefEnd ?? other.targetRefEnd,
    connectionType: connectionType,
  );
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

  /// אופסטי עוגן בצד המקור, כפי שנכתבו בקובץ (תווים גולמיים).
  final int? anchorStart;
  final int? anchorEnd;
  final String? anchorLabel;

  /// קצות טווח אופציונליים, 1-based בקובץ ו-0-based לאחר הפענוח.
  final int? sourceLineNumberEnd;
  final int? targetLineNumberEnd;
  final String? targetRefEnd;

  /// שם connection_type ב-DB (אחד מ-[kNativeConnectionTypes]).
  final String connectionType;

  const ParsedNativeLink({
    required this.sourceLineNumber,
    required this.targetTitle,
    required this.targetLineNumber,
    this.targetRef,
    this.anchorStart,
    this.anchorEnd,
    this.anchorLabel,
    this.sourceLineNumberEnd,
    this.targetLineNumberEnd,
    this.targetRefEnd,
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
}
