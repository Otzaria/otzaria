/// ריכוז הודעות המערכת (UiSnack) של הספרייה, החיפוש, הניווט והעדכונים.
abstract class LibraryMessages {
  // ===== ספרייה =====
  static const String cannotOpenLinkInBrowser =
      'לא ניתן לפתוח את הקישור בדפדפן';

  static String bookDeletedFromLibrary(String title) =>
      'הספר "$title" נמחק מהספרייה';

  static String bookDeleteError(Object error) => 'שגיאה במחיקת הספר: $error';

  static const String libraryLoadError = 'שגיאה בטעינת הספרייה. נסה שוב.';

  static String talmudPdfEditionMissing(String title) =>
      'לא נמצאה מהדורת PDF ל"$title" — המסכת נפתחה כטקסט';

  static String zipExtractedSuccessfully(String fileName) =>
      'הקובץ "$fileName" חולץ בהצלחה!';

  static String hebrewBookDownloaded(String location) =>
      'הספר הורד אל $location';

  static const String hebrewBookDownloadCanceled = 'ההורדה בוטלה';

  static String hebrewBookDownloadError(Object error) =>
      'שגיאה בהורדת הספר: $error';

  // ===== חיפוש =====
  static String distanceSetAsDefault(int distance) =>
      'מרווח $distance נקבע כברירת מחדל לחיפוש רגיל';

  static const String searchIndexMissing =
      'אינדקס לא קיים, לא ניתן לבצע חיפוש זה ללא אינדקס.';

  static const String searchIndexOpenFailed =
      'פתיחת אינדקס החיפוש נכשלה — האינדוקס הושהה. נסה להפעיל מחדש את התוכנה';

  static const String searchResultIndexOutOfDate =
      'תוצאת החיפוש שייכת לאינדקס ישן. יש לעדכן את אינדקס החיפוש.';

  static const String searchResultContentDrifted =
      'תוכן הספר השתנה מאז עדכון האינדקס — מומלץ לעדכן את אינדקס החיפוש.';

  static String indexingCompletedWithFailures(int count) =>
      'האינדוקס הסתיים עם $count בעיות. לחץ לפתיחת קובץ השגיאות.';

  static const String emptySearchQuery = 'נא להזין טקסט לחיפוש';

  static String categoryOrBookNotFound(List<String> names) =>
      'הקטגוריה או הספר "${names.join('", "')}" לא נמצאו';

  static const String searchError = 'אירעה שגיאה בעת החיפוש';

  static const String loadMoreResultsError = 'אירעה שגיאה בטעינת תוצאות נוספות';

  // ===== ניווט =====
  static String bookNotFoundById(Object bookId) =>
      'הספר עם המזהה $bookId לא נמצא בספרייה';

  static String pdfBookNotFoundById(Object bookId) =>
      'ספר ה-PDF עם המזהה $bookId לא נמצא בספרייה';

  static String pluginNotFound(String pluginId) => 'התוסף "$pluginId" לא נמצא';

  static String pluginDisabled(String name) => 'התוסף "$name" מושבת';

  static String tabMovedToWorkspace(String workspaceName) =>
      'הכרטיסיה הועברה לשולחן העבודה "$workspaceName"';

  // ===== עדכונים =====
  static const String updateCheckNetworkError =
      'שגיאה בחיבור לרשת במהלך בדיקת עדכונים';

  static const String updateCheckError = 'שגיאה בבדיקת עדכונים';

  static const String noInternetConnection = 'אין חיבור לאינטרנט';

  static const String updateSourceUnreachable =
      'שרת העדכונים אינו זמין ברשת זו';

  static const String updateDownloadError = 'שגיאה בהורדת העדכון';

  static const String updateInstallerLaunchError = 'שגיאה בהפעלת מתקין העדכון';

  static const String deltaApplyFailed = 'החלת עדכון הדלתא נכשלה';

  static const String deltaResultMismatch =
      'תוצאת עדכון הדלתא אינה תואמת לגרסה הצפויה';

  static const String localLibraryContentMismatch =
      'תוכן הספרייה המקומית שונה מהצפוי';

  static String fullLibraryDownloadRequired(String reason, String size) =>
      '$reason — נדרשת הורדה מלאה ($size)';
}
