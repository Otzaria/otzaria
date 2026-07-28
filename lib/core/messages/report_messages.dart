/// ריכוז כל ההודעות למשתמש של מנגנון דיווח הטעויות.
///
/// כל טקסט שמוצג למשתמש בתהליך שליחת דיווח (ישיר, טלפוני, מייל וניהול
/// התור) מוגדר כאן בלבד — אין לכתוב מחרוזות דיווח בקבצי הפיצ'רים.
abstract class ReportMessages {
  // ── שליחה ישירה (DirectErrorReportService) ─────────────────────────────

  static const String sentToOtzaria = 'הדיווח נשלח בהצלחה לצוות אוצריא.';
  static const String sentToSefaria = 'הדיווח נשלח בהצלחה לספריא.';
  static const String sentSuccessTitle = 'הדיווח נשלח בהצלחה';
  static const String offlineQueueDisabled =
      'מצב אופליין פעיל, והגדרת התור האוטומטי כבויה.';
  static const String noInternet = 'אין כרגע חיבור לאינטרנט.';
  static const String serverTimeout = 'השרת לא הגיב בזמן.';
  static const String sendFailed = 'שגיאה בשליחת הדיווח.';
  static const String unexpectedSendError =
      'אירעה שגיאה לא צפויה בשליחת הדיווח.';

  static String queuedOffline(String targetLabel) =>
      'אין כרגע חיבור. הדיווח נשמר ויישלח אוטומטית '
      'ל$targetLabel כשהתוכנה תחזור להיות מקוונת. '
      'ניתן לנהל את הדיווחים השמורים בהגדרות.';

  static String queuedAfterFailure(String targetLabel) =>
      'השליחה לא הצליחה כרגע. הדיווח נשמר להמשך ויישלח אוטומטית '
      'ל$targetLabel בניסיון הבא. ניתן לנהל את הדיווחים '
      'השמורים בהגדרות.';

  static String serverPermanentFailure(int statusCode) =>
      'שרת הדיווחים החזיר $statusCode. הדיווח לא נשמר להמשך כי נראה שיש בעיה קבועה בנתונים שנשלחו.';

  static String serverTransientFailure(int statusCode) =>
      'שרת הדיווחים החזיר $statusCode. הדיווח יישמר להמשך.';

  /// כותרת חלון הסיכום של סקריפט השליחה האופליין (bat/sh).
  static const String offlineScriptWindowTitle =
      'שליחת דיווחים שמורים - אוצריא';

  // ── דיאלוג הדיווח (error_report_dialog) ────────────────────────────────

  static const String phoneSentThanks =
      'הדיווח נשלח בהצלחה לצוות אוצריא. תודה על הדיווח!';
  static const String cannotOpenMailApp = 'לא ניתן לפתוח את תוכנת הדואר';
  static const String cannotOpenEditPage = 'לא ניתן לפתוח את עמוד העריכה.';
  static const String cannotIdentifyReportedBook =
      'לא ניתן לזהות את הספר לדיווח.';
  static const String senderEmailSaved =
      'כתובת הזיהוי נשמרה. ניתן לשנות אותה בהגדרות.';
  static const String senderEmailCleared = 'כתובת הזיהוי הוסרה.';

  static String reportSubject(String bookTitle) => 'דיווח על טעות: $bookTitle';

  static String sendError(Object error) => 'שגיאה בשליחת הדיווח: $error';

  static String handleError(Object error) => 'שגיאה בטיפול בדיווח: $error';

  static String savedForLater(int pendingCount) =>
      'הדיווח נשמר להמשך. יש כרגע $pendingCount דיווחים ממתינים בתור, וניתן לנהל את הדיווחים השמורים בהגדרות.';

  // ── ניהול התור בהגדרות (system_settings_tab) ───────────────────────────

  static const String markedAsSent = 'הדיווח סומן כנשלח.';
  static const String reportUpdated = 'הדיווח עודכן.';
  static const String removedFromQueue = 'הדיווח הוסר מהתור.';
  static const String deletedFromHistory = 'הדיווח נמחק מההיסטוריה.';
  static const String historyCleared = 'היסטוריית הדיווחים נוקתה.';
  static const String pendingCleared = 'הדיווחים השמורים נמחקו.';
  static const String noPendingToSend = 'לא נמצאו דיווחים שמורים לשליחה.';
  static const String noPendingToExport = 'אין דיווחים שמורים לייצוא.';
  static const String scriptSavedWindows =
      'סקריפט השליחה נשמר בהצלחה. לשליחת הדיווחים הפעילו את הקובץ '
      'במחשב מחובר.';

  static String pendingFlushed(int sentCount) =>
      'נשלחו $sentCount דיווחים ממתינים.';

  static String pendingFlushFailed(int pendingCount) =>
      'לא ניתן לשלוח כרגע את הדיווחים השמורים. עדיין שמורים בתור $pendingCount דיווחים, וניתן לנהל אותם בהגדרות.';

  static String scriptSavedUnix(String fileName) =>
      'סקריפט השליחה נשמר בהצלחה. הריצו אותו במחשב מחובר '
      '(אם הקובץ אינו ניתן להרצה: bash $fileName).';

  static String scriptSaveError(Object error) => 'שגיאה בשמירת הסקריפט: $error';

  // ── דיווח טלפוני (PhoneReportService) ──────────────────────────────────

  static const String phoneSent = 'הדיווח נשלח בהצלחה';
  static const String phoneBadRequest =
      'שגיאה בנתוני הדיווח. בדוק שכל השדות מלאים';
  static const String phoneUnauthorized = 'שגיאת הרשאה. פנה לתמיכה טכנית';
  static const String phoneForbidden =
      'אין הרשאה לשלוח דיווח. פנה לתמיכה טכנית';
  static const String phoneServiceUnavailable =
      'שירות הדיווח אינו זמין. פנה לתמיכה טכנית';
  static const String phoneTooManyRequests =
      'יותר מדי בקשות. המתן מספר דקות ונסה שוב';
  static const String phoneServerUnavailable =
      'השרת אינו זמין כעת. נסה שוב מאוחר יותר';
  static const String phoneNoInternet =
      'אין חיבור לאינטרנט. בדוק את החיבור ונסה שוב';
  static const String phoneClientError =
      'שגיאה בשליחת הנתונים. נסה שוב מאוחר יותר';
  static const String phoneUnexpectedRetry =
      'שגיאה לא צפויה. נסה שוב מאוחר יותר';
  static const String phoneUnexpected = 'שגיאה לא צפויה';

  static String phoneUnexpectedStatus(int statusCode) =>
      'שגיאה לא צפויה: $statusCode';

  static String phoneSendDataError(int statusCode) =>
      'שגיאה בשליחת הנתונים ($statusCode)';
}
