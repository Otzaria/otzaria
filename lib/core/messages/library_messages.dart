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

  static String searchModeSetAsDefault(String mode) =>
      'חיפוש חדש ייפתח מעכשיו במצב $mode';

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

  static String indexingCompletedWithWarnings(int count) =>
      'האינדוקס הושלם. ב-$count ספרי PDF נשמטו עמודים בודדים מהחיפוש. '
      'לחץ לפרטים.';

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

  /// השולחן נמחק בחלון אחר בין בניית התפריט לבחירה.
  static const String workspaceNoLongerExists =
      'שולחן העבודה הזה אינו קיים יותר';

  // ===== עדכונים =====
  static const String updateCheckNetworkError =
      'שגיאה בחיבור לרשת במהלך בדיקת עדכונים';

  static const String updateCheckError = 'שגיאה בבדיקת עדכונים';

  /// GitHub הגביל את מספר הבדיקות מכתובת ה-IP; [minutes] = `null` כשלא ידוע.
  static String updateRateLimited(int? minutes) => minutes == null
      ? 'GitHub הגביל זמנית את מספר הבדיקות מרשת זו. נסה שוב מאוחר יותר'
      : 'GitHub הגביל זמנית את מספר הבדיקות מרשת זו. נסה שוב בעוד $minutes דקות';

  static const String noInternetConnection = 'אין חיבור לאינטרנט';

  static const String updateSourceUnreachable =
      'שרת העדכונים אינו זמין ברשת זו';

  static const String updateDownloadError = 'שגיאה בהורדת העדכון';

  static const String updateInstallerLaunchError = 'שגיאה בהפעלת מתקין העדכון';

  static const String updateDiskSpaceError =
      'אין מספיק מקום פנוי בדיסק לעדכון הספרייה';

  static const String updateNetworkInterrupted =
      'החיבור לרשת נקטע במהלך ההורדה';

  static const String deltaApplyFailed = 'החלת עדכון הדלתא נכשלה';

  static const String deltaResultMismatch =
      'תוצאת עדכון הדלתא אינה תואמת לגרסה הצפויה';

  static const String localLibraryContentMismatch =
      'תוכן הספרייה המקומית שונה מהצפוי';

  static const String libraryContentDriftAfterUpdate =
      'העדכון הוחל, אך תוכן הספרייה המקומית סוטה מהגרסה הרשמית';

  static String fullLibraryDownloadRequired(String reason, String size) =>
      '$reason — נדרשת הורדה מלאה ($size)';

  /// בחירת מסלול כשהחלת הדלתא צפויה להימשך זמן רב (issue #1211).
  static String heavyDeltaRouteChoice({
    required String reason,
    required String deltaDownloadSize,
    required String deltaApplySize,
    required String fullDownloadSize,
  }) =>
      '$reason.\n'
      'עדכון דלתא: הורדה קטנה ($deltaDownloadSize), אך פריסה של '
      '$deltaApplySize והחלה ארוכה — עשרות דקות ומעלה. מתאים לרשת איטית.\n'
      'הורדה מלאה: הורדה גדולה ($fullDownloadSize) והחלה מהירה — דקות.';

  static const String smallUpdateDialogTitle = 'העדכון מוכן';

  /// לפני האישור: המעדכן החיצוני משוגר רק בלחיצה על הכפתור, ולכן אסור
  /// להבטיח כאן שסגירה ידנית של אוצריא תשלים את העדכון.
  static const String smallUpdateDialogContent =
      'לחיצה על "סגור והתקן" היא שמתחילה את ההתקנה: אוצריא תיסגר — כולל '
      'חלונות נוספים — ותיפתח מחדש בגרסה החדשה.';

  static const String smallUpdateDialogCancel = 'לא עכשיו';

  static const String smallUpdateDialogConfirm = 'סגור והתקן';

  /// אחרי האישור, כשחלון כלשהו עוד פתוח: רק כאן המעדכן כבר רץ וממתין
  /// ליציאת התהליך, ולכן רק כאן סגירה ידנית באמת משלימה את העדכון.
  static const String smallUpdateAwaitingCloseChip = 'סגור את החלונות שנותרו';

  static const String smallUpdateAwaitingCloseMessage =
      'העדכון יושלם כשאוצריא תיסגר לגמרי. סגור את החלונות שנותרו פתוחים — '
      'והעדכון יושלם מעצמו ואוצריא תיפתח מחדש בגרסה החדשה.';

  /// המעדכן ויתר כי חלון סירב להיסגר. ההתקנה לא נגעה, והעדכון חזר למצב
  /// "מוכן להתקנה" — ההבטחה של [smallUpdateAwaitingCloseMessage] כבר אינה נכונה.
  static const String smallUpdateGaveUp =
      'העדכון לא הותקן, כי אוצריא לא נסגרה לגמרי. שום דבר לא השתנה, '
      'והעדכון עדיין מוכן — לחץ על "מוכן להתקנה" כדי לנסות שוב.';

  /// התקנת Linux ניידת אינה מתעדכנת במנהל החבילות, ולעדכון המצומצם לא
  /// נמצאה חבילה — דף ההורדות נפתח בדפדפן.
  static const String portableUpdateOpenedReleasePage =
      'דף ההורדות נפתח בדפדפן. הורד את החבילה המלאה ופרוס אותה במקום '
      'התיקייה הקיימת.';

  /// נלווה להודעת שלב ההחלה כשמסלול הדלתא כבד ואין הורדה מלאה חלופית.
  static String applyStageWithHeavyDeltaNotice(String stageMessage) =>
      '$stageMessage — ההחלה עשויה להימשך זמן רב';

  // ===== ייבוא ספרייה בשני קבצים (חבילת FULL של אנדרואיד) =====
  /// הארכיון הכיל רק קבצים נלווים; ה-DB מגיע בקובץ נפרד.
  static const String archiveImportedAwaitingDatabase =
      'הקבצים הנלווים יובאו. כעת יש לייבא לאותה ספרייה את קובץ הספרייה '
      '(.zdb או .db.zst).';
  static const String archiveNestedDatabaseUnsupported =
      'מבנה הארכיון אינו נתמך: קובץ הספרייה נמצא בתוך תיקייה. יש לייבא את '
      'הארכיון של הקבצים הנלווים ואת קובץ הספרייה (.zdb) כל אחד בנפרד.';

  // ===== קובץ הספרייה הדחוס (seforim.zdb) =====
  static const String zdbFullDownloading = 'מוריד ספרייה מלאה';
  static const String zdbFullVerifying = 'מאמת את קובץ הספרייה שהורד';
  static const String zdbFullInstalling = 'מתקין את קובץ הספרייה';

  /// ייעול האחסון אחרי עדכון: דחיסה מקומית כשאין עותק עדכני להוריד.
  static const String storageOptimizingCompact =
      'מייעל את אחסון הספרייה — הספרייה סגורה עד הסיום';
  static const String storageOptimizingCancelled = 'ייעול אחסון הספרייה בוטל';
  static const String storageOptimized = 'אחסון הספרייה יועל';
  static const String storageOptimizedLocally =
      'ההורדה נכשלה, ואחסון הספרייה יועל במחשב';
  static const String storageOptimizeDeferred =
      'ייעול אחסון הספרייה נדחה לבדיקת העדכון הבאה';
  static const String storageOptimizeLater =
      'ייעול אחסון הספרייה יוצע שוב בבדיקת העדכון הבאה';

  /// הצעת הורדה של בסיס עדכני (באישור, כמו כל הורדה מלאה).
  static String storageRebaseOffer(String size) =>
      'ייעול אחסון: הורדה של ~$size';
  static const String storageRebaseDialogTitle = 'ייעול אחסון הספרייה';
  static String storageRebaseDialogContent(
    String size, {
    bool recommendWifi = false,
  }) =>
      'העדכונים שהצטברו תופסים כבר יותר ממחצית גודל הספרייה, והם מאטים את '
      'פתיחתה. הורדה של עותק עדכני (כ-$size) תחליף אותם. אפשר גם לדחות — '
      'אז האחסון ייועל במחשב כשהספרייה פנויה, או שהשאלה תחזור בבדיקה הבאה.'
      '${recommendWifi ? '\n\n$storageRebaseWifiHint' : ''}';

  /// באנדרואיד בלבד: ההורדה גדולה, ורשת סלולרית עלולה להיות מוגבלת או בתשלום.
  static const String storageRebaseWifiHint =
      'מומלץ להתחבר לרשת Wi-Fi לפני ההורדה.';
  static const String storageRebaseConfirm = 'הורד וייעל';
  static const String storageRebaseLater = 'אחר כך';
}
