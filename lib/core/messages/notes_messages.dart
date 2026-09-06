/// ריכוז הודעות המערכת (UiSnack) של הערות אישיות, סימניות,
/// היסטוריה וסביבות עבודה.
abstract class NotesMessages {
  // ===== הערות אישיות =====
  static const String emptyNoteNotSaved = 'ההערה ריקה, לא נשמרה';
  static const String noteSaved = 'ההערה נשמרה בהצלחה';
  static const String noteUpdated = 'ההערה עודכנה';
  static const String noteDeleted = 'ההערה נמחקה';
  static const String noteHasNoLocation = 'להערה הזו אין מיקום';
  static const String libraryNotLoadedYet = 'הספרייה לא נטענה עדיין';
  static const String backupCompleted = 'הגיבוי הושלם בהצלחה';
  static const String textExportCompleted = 'הייצוא לטקסט הושלם בהצלחה';
  static const String wordExportCompleted = 'הייצוא לוורד הושלם בהצלחה';

  static String notesListLoadError(Object error) =>
      'שגיאה בטעינת רשימת ההערות: $error';

  static String importCompleted({
    required int inserted,
    required int updated,
    required int skipped,
    required int duplicated,
  }) =>
      'ייבוא הושלם: נוספו $inserted, עודכנו $updated, '
      'דולגו $skipped, שוכפלו $duplicated';

  static String noteMovedToLine(int line) => 'ההערה הועברה לשורה $line';

  static String noteAssignedToLine(int line) => 'ההערה שויכה לשורה $line';

  static String bookNotFound(String bookId) => 'הספר לא נמצא: $bookId';

  static String cannotOpenLink(String url) => 'לא ניתן לפתוח את הקישור: $url';

  static String externalLink(String url) => 'קישור חיצוני: $url';

  static String linkToAnotherBook(String bookId) => 'קישור לספר אחר: $bookId';

  static String unsupportedLink(String url) => 'קישור לא נתמך: $url';

  // ===== סימניות =====
  static const String bookmarkAdded = 'הסימניה נוספה בהצלחה';
  static const String bookmarkAlreadyExists = 'הסימניה כבר קיימת';
  static const String bookmarkAddError = 'שגיאה בהוספת הסימניה';
  static const String bookmarkSaveError = 'שגיאה בשמירת הסימניות';
  static const String bookmarkClearError = 'שגיאה במחיקת הסימניות';
  static const String bookmarkDeleted = 'הסימניה נמחקה';
  static const String allBookmarksDeleted = 'כל הסימניות נמחקו';
  static const String bookBookmarksDeleted = 'סימניות הספר נמחקו';

  // ===== סימניות מרוכזות =====
  static const String groupBookmarkSaved = 'הסימניה המרוכזת נשמרה';
  static const String groupBookmarkReplaced = 'הסימניה המרוכזת עודכנה';
  static const String groupBookmarkDeleted = 'הסימניה המרוכזת נמחקה';
  static const String noOpenBooksForGroupBookmark = 'אין ספרים פתוחים לשמירה';
  static const String groupBookmarkNoSelection = 'לא נבחרו ספרים לשמירה';

  // ===== היסטוריה =====
  static const String historyEntryDeleted = 'נמחק בהצלחה';
  static const String allHistoryDeleted = 'כל ההיסטוריה נמחקה';

  // ===== סביבות עבודה =====
  static const String cannotDeleteActiveWorkspace =
      'לא ניתן למחוק שולחן עבודה פעיל';
  static const String workspaceDeleted = 'שולחן העבודה נמחק';

  static const String workspacesLoadFailed = 'טעינת שולחנות העבודה נכשלה';

  /// ⚠️ הכרטיסיות **לא** הוחלפו — השמירה קודמת לחשיפה בדיוק כדי שזה יהיה נכון.
  static const String workspaceSwitchFailed =
      'החלפת שולחן העבודה נכשלה. הכרטיסיות הפתוחות נשארו כפי שהיו.';

  static const String workspaceSaveFailed = 'שמירת שולחנות העבודה נכשלה';
}
