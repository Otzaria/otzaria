/// ריכוז הודעות המערכת (UiSnack) של מסכי הכלים.
abstract class ToolsMessages {
  // ── מסך הכלים ──
  static String pluginRequiresInternet(String pluginName) =>
      'התוסף "$pluginName" דורש חיבור אינטרנט ולא ניתן לפתוח אותו במצב מנותק';
  static String builtInToolHidden(String toolLabel) =>
      'הכלי "$toolLabel" מוסתר. ניתן להציג אותו דרך הגדרות → ניהול כלים';
  static String pluginNotShownInTools(String pluginName) =>
      'התוסף "$pluginName" אינו מוצג בכלים. ניתן להציג אותו דרך הגדרות → ניהול כלים';
  static String toolNotFound(String toolId) => 'הכלי "$toolId" לא נמצא';

  // ── מילונים (ארמית וראשי תיבות) ──
  static String dictionaryLoadError(Object error) =>
      'שגיאה בטעינת המילון: $error';

  // ── גימטריה ──
  static const String gematriaInvalidInput =
      'קלט לא תקין. יש להזין אותיות עבריות או מספרים בלבד.';
  static String gematriaSearchError(Object error) => 'שגיאה בחיפוש: $error';

  // ── שמור וזכור ──
  static String bookRemovedFromTracking(String bookName) =>
      'הספר "$bookName" הוסר מרשימת המעקב';
  static String bookRemovedFromShamorZachor(String bookName) =>
      'הספר "$bookName" הוסר משמור וזכור';
  static String bookRemoveError(Object error) => 'שגיאה בהסרת הספר: $error';
  static const String noBooksSelectedToAdd = 'לא נבחרו ספרים להוספה';
  static String booksAddedToTracking(int count) => '$count ספרים נוספו למעקב';
  static String booksAddFailed(int count) => '$count ספרים לא נוספו';
  static String booksAddError(Object error) => 'שגיאה בהוספת ספרים: $error';
  static const String progressSaveMissingId =
      'שגיאה: לא ניתן לשמור התקדמות לספר זה (חסר מזהה)';

  // ── לוח שנה ──
  static const String dateParseFailed = 'לא הצלחנו לפרש את התאריך.';
  static const String dateOutOfRange = 'התאריך מחוץ לטווח הנתמך.';
  static const String zmanAlertUnavailableTime =
      'לא ניתן להפעיל התראה לזמן לא זמין';
  static const String dafYomiUnavailableForDate = 'הדף היומי לא זמין לתאריך זה';
  static const String omerAlertUnavailableToday =
      'לא ניתן להפעיל התראה לספירת העומר ביום זה';
  static const String zmanAlertUpdateError = 'שגיאה בעדכון ההתראה';
  static String zmanAlertEnabled(String displayName) =>
      'התראה הופעלה עבור $displayName';
  static String zmanAlertCancelled(String displayName) =>
      'ההתראה בוטלה עבור $displayName';
  static const String cityDataNotFound =
      'לא נמצאו נתונים עבור העיר שנבחרה. נעשה שימוש באזור זמן ברירת המחדל.';
  static const String notificationsPermissionRequiredMacos =
      'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
      'עבור להגדרות המערכת > פרטיות ואבטחה > התראות > אוצריא\n'
      'או הפעל מחדש את האפליקציה ואשר את בקשת ההרשאות';
  static const String notificationsPermissionRequiredIos =
      'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
      'עבור להגדרות > התראות > אוצריא';
  static const String notificationsPermissionRequired =
      'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
      'עבור להגדרות המכשיר > אפליקציות > אוצריא > הרשאות';
  static const String eventTitleRequired = 'יש למלא כותרת לאירוע.';
  static const String eventRecurringYearsInvalid =
      'יש להזין מספר שנים חיובי עבור אירוע חוזר.';
  static const String eventEndBeforeStart =
      'תאריך הסיום חייב להיות שווה או מאוחר מתאריך ההתחלה.';
  static const String eventRangeLongerThanRecurrence =
      'טווח הימים של האירוע חייב להיות קצר מתדירות החזרה.';

  // ── דף יומי — ניווט ──
  static const String libraryStillLoading =
      'הספרייה עדיין בטעינה, נסה שוב בעוד רגע';
  static String categoryNotFound(String categoryName) =>
      'לא נמצאה קטגוריה: $categoryName';
  static String tractateNotFound(
    String tractate,
    String categoryName,
    String availableBooks,
  ) =>
      'לא נמצא ספר: $tractate ב$categoryName\nספרים זמינים: $availableBooks...';
}
