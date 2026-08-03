/// ריכוז הודעות המערכת (UiSnack) של מסכי ספרי הטקסט.
abstract class TextBookMessages {
  // ── שמור וזכור ──────────────────────────────────────────────────────────

  static const String shamorZachorDataNotLoaded = 'נתוני שמור וזכור לא נטענו';
  static const String bookNotFoundInDatabase = 'הספר לא נמצא במסד הנתונים';
  static const String bookNotFoundInShamorZachor = 'הספר לא נמצא בשמור וזכור';
  static const String onlyOfficialBooksSupportedInTracking =
      'רק ספרים מהספרייה הרשמית נתמכים במעקב בשמור וזכור';
  static const String bookPathNotFound = 'לא נמצא נתיב לספר';
  static const String addingBookToTracking = 'מוסיף ספר למעקב...';

  static String noFreeSlotInChapter(String chapterName) =>
      'אין מקום פנוי ב$chapterName, למדת הרבה!';

  static String chapterMarked(String displayName, String columnName) =>
      '$displayName סומן כ$columnName בהצלחה!';

  static String markingError(Object error) => 'שגיאה בסימון: $error';

  static String bookAddedToTracking(String bookName) =>
      'הספר "$bookName" נוסף למעקב בהצלחה!';

  static String addBookToTrackingError(Object error) =>
      'שגיאה בהוספת הספר למעקב: $error';

  // ── ייצוא והדפסה ────────────────────────────────────────────────────────

  static const String cannotCapturePageShapeForPrint =
      'לא ניתן לצלם את תצוגת "צורת הדף" לצורך הדפסה';
  static const String wordFileSaved = 'קובץ Word נשמר בהצלחה';
  static const String textFileSaved = 'קובץ טקסט נשמר בהצלחה';
  static const String exportFileLocked =
      'לא ניתן לשמור את הקובץ כי הוא פתוח בתוכנה אחרת. יש לסגור אותו ולנסות שוב.';
  static const String noCommentatorsToPrint = 'אין מפרשים להדפסה';

  static String exportFailed(Object error) => 'ייצוא הספר נכשל: $error';

  // ── קישורים ישירים ו-PDF ────────────────────────────────────────────────

  static const String directLinkUnavailable = 'קישור ישיר אינו זמין לספר זה';
  static const String selectTextForMarkLink =
      'יש לבחור טקסט כדי להעתיק קישור עם הדגשה';

  static String pdfNotFoundForBook(String bookTitle) =>
      'לא נמצא ספר PDF עבור "$bookTitle"';

  static const String pdfLocationNotFoundOpeningAtStart =
      'לא נמצא מיקום תואם ב-PDF — הספר נפתח מתחילתו';

  // ── תצוגה, העתקה והערות ─────────────────────────────────────────────────

  static const String perBookSettingsReset = 'ההגדרות הפר-ספריות אופסו בהצלחה';
  static const String searchUnavailableInThisView = 'חיפוש לא זמין בתצוגה זו';
  static const String selectTextToCopy = 'אנא בחר טקסט להעתקה';
  static const String noteSaved = 'ההערה נשמרה בהצלחה';
  static const String searchContentLoadFailed = 'טעינת תוכן הספר לחיפוש נכשלה';

  static String formattedCopyError(Object error) =>
      'שגיאה בהעתקה מעוצבת: $error';

  static String noteSaveError(Object error) => 'שגיאה בשמירת ההערה: $error';

  // ── צורת הדף — הסתרת טורים ──────────────────────────────────────────────

  static const String columnHiddenInBook =
      'הטור הוסתר בספר זה. ניתן לשנות בהגדרות צורת הדף.';
  static const String columnHiddenInWorkspace =
      'הטור הוסתר בשולחן העבודה הזה. ניתן לשנות בהגדרות צורת הדף.';
  static const String columnHiddenGlobally =
      'הטור הוסתר בכל הספרים. ניתן לשנות בהגדרות צורת הדף.';

  // ── עריכת טקסט (עורך הקטעים) ────────────────────────────────────────────

  static const String localEditsWarning =
      'שים לב: השינויים נשמרים מקומית בלבד, ובמקרה של עדכון הספרייה, השינויים ימחקו!';
  static const String lineStructureLocked =
      'בספר זה אסור לשנות מבנה שורות כדי לשמור על קישורי פרשנות';
  static const String textNotFound = 'הטקסט לא נמצא';
}
