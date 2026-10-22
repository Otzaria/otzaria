/// ריכוז הודעות המערכת (UiSnack) הכלליות והמשותפות.
abstract class CommonMessages {
  // ── העתקה ללוח ──────────────────────────────────────────────────────────
  static const String textCopied = 'הטקסט הועתק ללוח';
  static const String textCopiedShort = 'הטקסט הועתק';
  static const String formattedTextCopied = 'הטקסט המעוצב הועתק ללוח';
  static const String plainTextCopied = 'הטקסט הועתק ללוח ללא עיצוב';
  static const String textCopyError = 'שגיאה בהעתקת הטקסט';
  static const String clipboardCopyError = 'שגיאה בהעתקה ללוח';
  static const String clipboardUnavailable = 'לא ניתן לגשת ללוח';
  static const String linkCopied = 'הקישור הועתק';
  static const String pathCopied = 'הנתיב הועתק ללוח';
  static const String noTextSelected = 'אנא בחר טקסט להעתקה';
  static const String noContentToCopy = 'אין תוכן להעתקה';
  static const String paragraphCopied = 'הפסקה הועתקה בהצלחה';
  static const String paragraphCopyError = 'שגיאה בהעתקת הפסקה';

  static String copiedToClipboard(String text) => 'הועתק ללוח: $text';

  static String copyErrorWithDetails(Object error) => 'שגיאה בהעתקה: $error';

  // ── ניווט וקישורים ──────────────────────────────────────────────────────
  static const String sectionNotFound = 'הדף לא נמצא בתוכן העניינים';

  static String openedRef(String ref) => 'נפתח: $ref';

  static String cannotOpenLink(Object error) =>
      'לא ניתן לפתוח את הקישור: $error';

  static String linkOpenError(Object error) => 'שגיאה בפתיחת הקישור: $error';

  static String navigatedToHeader(String header) => 'נווט ל: $header';

  static String cannotNavigateToHeader(String header) =>
      'לא ניתן לנווט לכותרת: $header';

  static String headerNotFoundOpeningStart(String header, String bookTitle) =>
      'לא נמצאה הכותרת "$header" בספר $bookTitle, פותח את תחילת הספר';

  static String openedBookAtHeader(String bookTitle, String header) =>
      'פתח ספר: $bookTitle - $header';

  static String openedBookAtPartialHeader(
    String bookTitle,
    String reachedHeader,
    String missingHeader,
  ) =>
      'פתח ספר: $bookTitle - $reachedHeader. '
      'הכותרת "$missingHeader" לא נמצאה';

  static String navigatedToPartialHeader(
    String reachedHeader,
    String missingHeader,
  ) => 'נווט ל: $reachedHeader. הכותרת "$missingHeader" לא נמצאה';

  static String cannotOpenBook(String bookTitle) =>
      'לא ניתן לפתוח את הספר: $bookTitle';

  // ── חיפוש ───────────────────────────────────────────────────────────────
  static const String noTextSelectedForSearch = 'לא נבחר טקסט לחיפוש';

  // ── הערות ושמירה ────────────────────────────────────────────────────────
  static const String savedSuccessfully = 'השינויים נשמרו בהצלחה';
  static const String diagnosticsSaveError =
      'שמירת האבחון נכשלה. האיסוף הופסק והנתונים נשמרו בזיכרון.';

  // ── טלפון ───────────────────────────────────────────────────────────────
  static const String cannotOpenPhoneApp = 'לא ניתן לפתוח את אפליקציית הטלפון';
  static const String phoneAppOpenError = 'שגיאה בפתיחת אפליקציית הטלפון';

  // ── ניווט ───────────────────────────────────────────────────────────────
  static const String pressBackAgainToExit = 'לחץ שוב על חזרה ליציאה';

  // ── קיצורי מקשים ────────────────────────────────────────────────────────
  static const String shortcutRequired = 'יש לבחור קיצור';
  static const String shortcutNavigationKey =
      'לא ניתן להגדיר קיצור עם החיצים, Tab, PageUp/PageDown או Home/End — מקשים אלה משמשים לניווט ולגלילה';

  static String shortcutAlreadyInUse(String actionName) =>
      'קיצור זה כבר בשימוש עבור: $actionName';
}
