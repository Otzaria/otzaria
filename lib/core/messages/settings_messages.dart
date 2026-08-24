/// ריכוז הודעות המערכת (UiSnack) של מסכי ההגדרות.
abstract class SettingsMessages {
  // ── העברת מיקום (change_location_dialog) ────────────────────────────────

  static String movingFolderFiles(String folderName) =>
      'מעביר את קבצי $folderName\nהפעולה עשויה לקחת מספר דקות';

  static String folderMovedSourceNotDeleted(
    String folderName,
    String sourcePath,
  ) =>
      '$folderName הועבר בהצלחה, אך לא ניתן למחוק את תיקיית המקור. אנא מחק ידנית: $sourcePath';

  static String folderMoved(String folderName) => '$folderName הועבר בהצלחה';

  static String folderMoveError(String folderName, Object error) =>
      'שגיאה בהעברת קבצי $folderName: $error';

  static const String cannotMoveLibraryIntoItself =
      'לא ניתן להעביר את הספרייה לתוך עצמה';

  static String libraryMoveError(Object error) =>
      'שגיאה בהעברת הספרייה: $error';

  static const String libraryMovedOldFilesLeft =
      'הספרייה הועברה, אך חלק מהקבצים הישנים לא נמחקו. ניתן למחוק אותם '
      'ידנית מהמיקום הישן.';

  // ── סיסמת מצב מוגן (safer_mode_password_dialog) ────────────────────────

  static const String passwordRequired = 'נא להזין סיסמה';
  static const String wrongPassword = 'סיסמה שגויה';
  static const String passwordTooShort = 'הסיסמה חייבת להכיל לפחות 4 תווים';
  static const String passwordsDoNotMatch = 'הסיסמאות אינן תואמות';
  static const String passwordSaved = 'הסיסמה נשמרה בהצלחה';
  static const String passwordRemoved = 'הסיסמה הוסרה';

  static String passwordSaveError(Object error) =>
      'שגיאה בשמירת הסיסמה: $error';

  static String passwordRemoveError(Object error) =>
      'שגיאה בהסרת הסיסמה: $error';

  static const String protectedModeEnabled = 'המצב המוגן הופעל';
  static const String protectedModeDisabled = 'המצב המוגן הושבת';

  // ── ייבוא ספרים אישיים (personal_books_import_panel) ───────────────────

  static String importErrors(String errors) => 'שגיאות בייבוא:\n$errors';

  static String unsupportedFilesSkipped(int count) =>
      '$count קבצים דולגו — ניתן לייבא רק TXT, PDF ו-Word';

  static String bookDeleteError(Object error) => 'שגיאה במחיקת הספר: $error';

  static String bookDeleted(String title) => 'הספר "$title" נמחק';

  // ── תיקיות אישיות (custom_folders_panel) ───────────────────────────────

  static const String folderNotFound = 'התיקייה לא נמצאה';

  static String folderAdded(String folderName) =>
      'התיקייה "$folderName" נוספה בהצלחה';

  static String fileExtracted(Object? fileName) =>
      'הקובץ "$fileName" חולץ בהצלחה!';

  static const String pathCopied = 'הנתיב הועתק ללוח';

  // ── ניהול תוספים (tools_management_panel) ──────────────────────────────

  static const String pluginsShownInTools = 'התוספים יוצגו בכלים';
  static const String pluginsHiddenFromTools = 'התוספים הוסרו מהכלים';
  static const String noSelectedPluginUsesNetwork =
      'אף תוסף נבחר לא מצהיר על שימוש ברשת — אין מה לעדכן';
  static const String networkAccessGranted = 'גישה לרשת הוענקה לתוספים הנבחרים';
  static const String networkAccessRevoked = 'גישה לרשת בוטלה לתוספים הנבחרים';
  static const String noSelectedPluginSupportsStartup =
      'אף תוסף נבחר לא תומך בטעינה אוטומטית בעלייה';
  static const String runOnStartupEnabled =
      'טעינה אוטומטית בעלייה הופעלה לתוספים הנבחרים';
  static const String runOnStartupDisabled =
      'טעינה אוטומטית בעלייה בוטלה לתוספים הנבחרים';
  static const String pluginsMarkedForDeletion = 'התוספים סומנו למחיקה';

  // ── לוח שנה (calendar_settings_panel) ──────────────────────────────────

  static const String noCalendarsFound = 'לא נמצאו לוחות שנה. נסה להתחבר מחדש.';

  // ── קיצורי מקשים (shortcuts_settings_tab) ──────────────────────────────

  static String shortcutAlreadyInUse(String conflictingNames) =>
      'קיצור זה כבר בשימוש עבור: $conflictingNames';

  static const String shortcutsReset = 'קיצורי המקשים אופסו בהצלחה';

  // ── מערכת וגיבויים (system_settings_tab) ───────────────────────────────

  static String booksListLoadError(Object error) =>
      'שגיאה בטעינת רשימת הספרים: $error';

  static const String libraryLoaded = 'הספרייה נטענה בהצלחה.';

  static String partialBackupSaved(String size, String missingSections) =>
      'גיבוי חלקי נשמר ($size) — חסרים: $missingSections';

  static String backupSaved(String size) => 'הגיבוי נשמר! גודל: $size';

  static String backupPluginTooLarge(String pluginId) =>
      'התוסף "$pluginId" גדול מדי ולא נכלל בגיבוי';

  static String backupCreateError(Object error) =>
      'שגיאה ביצירת הגיבוי: $error';

  static const String noBackupFileFound = 'לא נמצא קובץ גיבוי בתיקיית הגיבוי';

  static const String archiveNotCreatedYet =
      'עדיין לא נוצר ארכיון — הוא נבנה כשגיבויים ישנים ממוזגים';

  static String backupRestoreError(Object error) =>
      'שגיאה בשחזור הגיבוי: $error';

  static String backupsMergedToArchive(int count) =>
      '$count גיבויים מוזגו לארכיון';

  static String backupFilesDeleted(int count) => '$count קבצים נמחקו';

  static String backupSpaceFreed(String size) => 'התפנו $size';

  static const String nothingToClean = 'אין מה לנקות — הכל מעודכן';

  static String backupCleanupError(Object error) =>
      'שגיאה בניקוי הגיבויים: $error';

  // ── ספרייה (library_settings_tab) ──────────────────────────────────────

  static const String hebrewBooksPathRemoved =
      'מיקום ספרי היברובוקס הוסר בהצלחה';

  static String hebrewBooksPathRemoveError(Object error) =>
      'שגיאה בהסרת המיקום: $error';

  static String oldLibraryCopyDeleted(String size) =>
      'העותק הישן נמחק — התפנו $size';

  static String oldLibraryCopyDeleteError(Object error) =>
      'שגיאה במחיקת העותק הישן: $error';

  // ── רשימת ספרים (books_list_dialog) ────────────────────────────────────

  static String booksListSaved(int rowCount) =>
      'רשימת הספרים נשמרה: $rowCount שורות';

  static String fileSaveError(Object error) => 'שגיאה בשמירת הקובץ: $error';

  // ── הגדרות טקסט (text_settings_tab) ────────────────────────────────────

  static const String perBookSettingsReset = 'כל ההגדרות המיוחדות אופסו בהצלחה';
  static const String perBookSettingsResetFailed =
      'איפוס ההגדרות המיוחדות נכשל';

  // ── קטלוג חיצוני (external_catalog_settings_helper) ────────────────────

  static const String noCatalogNoExternalBooks =
      'ללא מסד הקטלוגים לא יוצגו ספרים חיצוניים';

  static const String downloadingCatalogDb = 'מוריד את מסד הקטלוגים החיצוני...';

  static const String catalogDbDownloaded = 'מסד הקטלוגים הורד בהצלחה';

  static String catalogDbDownloadError(Object error) =>
      'שגיאה בהורדת מסד הקטלוגים: $error';
}
