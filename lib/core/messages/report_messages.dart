/// ריכוז כל ההודעות למשתמש של מנגנון דיווח הטעויות.
///
/// כל טקסט שמוצג למשתמש בתהליך שליחת דיווח (ישיר, טלפוני, מייל וניהול
/// התור) מוגדר כאן בלבד — אין לכתוב מחרוזות דיווח בקבצי הפיצ'רים.
abstract class ReportMessages {
  // ── שליחה ישירה (DirectErrorReportService) ─────────────────────────────

  // "נקלט" ולא "אושר": הקליטה אינה הכרעה בתוכן הדיווח.
  static const String sentToOtzaria = 'הדיווח נקלט אצל צוות אוצריא. תודה!';
  static const String sentToSefaria = 'הדיווח נקלט ויועבר לספריא. תודה!';
  static const String sentSuccessTitle = 'הדיווח נקלט';

  static String correctionNotSupportedByServer(String targetLabel) =>
      'הדיווח נקלט אצל $targetLabel, אך השרת עדיין אינו תומך בהצעת תיקון '
      'מובנית. ההצעה נשלחה כטקסט בתוך פירוט הטעות ונשמרה בהיסטוריית '
      'הדיווחים.';
  static const String reportIdConflict =
      'השרת כבר קלט דיווח אחר עם אותו מזהה, ולכן הדיווח לא נקלט. '
      'ניתן לדווח שוב — דיווח חדש מקבל מזהה חדש.';
  static const String pendingReportIdConflict =
      'השרת כבר קלט דיווח אחר עם אותו מזהה, ולכן הדיווח לא נקלט. '
      'הדיווח קיבל מזהה חדש ונשאר בתור — ניתן לשלוח אותו שוב.';

  static String bodyTooLarge(int maxKb) =>
      'הדיווח גדול מדי לשליחה (הגבול הוא ${maxKb}KB). יש לקצר את הפירוט '
      'או את ההצעה — הטקסט לא ייחתך.';

  static String duplicateReport(String targetLabel) =>
      'דיווח זהה לזה כבר נשלח ל$targetLabel בעבר, ולכן לא נשלחה הודעה נוספת. '
      'הדיווח נקלט במערכת.';
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
  static const String selectTextToReport =
      'יש לסמן טקסט או לבחור קטע לפני דיווח על טעות.';
  static const String cannotOpenMailApp = 'לא ניתן לפתוח את תוכנת הדואר';
  static const String cannotOpenEditPage = 'לא ניתן לפתוח את עמוד העריכה.';
  static const String cannotIdentifyReportedBook =
      'לא ניתן לזהות את הספר לדיווח.';
  static const String senderEmailSaved =
      'כתובת הזיהוי נשמרה. ניתן לשנות אותה בהגדרות.';
  static const String senderEmailCleared = 'כתובת הזיהוי הוסרה.';

  static String reportSubject(String bookTitle) => 'דיווח על טעות: $bookTitle';

  static const String proposalIdentical =
      'ההצעה זהה למקור. יש לשנות את הטקסט, לבחור "מחיקת הקטע" או "ללא הצעה".';

  static String proposalTooLong(int maxLength) =>
      'ההצעה ארוכה מדי (מעל $maxLength תווים). יש לקצר אותה — היא לא תיחתך.';

  static String originalTooLong(int maxLength) =>
      'השורה המקורית ארוכה מ-$maxLength תווים, ולכן לא ניתן להציע לה תיקון '
      'מובנה. ניתן לשלוח דיווח חופשי.';

  static const String invalidCharacters =
      'הטקסט מכיל תו פגום (חצי מתו מורכב, כמו אימוג׳י שנקטע), ולכן לא ניתן '
      'לשלוח אותו כהצעה מדויקת. יש למחוק את התו או לשלוח דיווח חופשי.';

  static const String proposalNeedsDetailsOrChange =
      'בלי הצעה יש לפרט מהי הטעות.';

  static const String correctionWholeLineNotice =
      'הקטע שסומן לא אותר באופן חד-משמעי בטקסט המקור (למשל בגלל ניקוד מוסתר, '
      'עיצוב או מופע חוזר), ולכן ההצעה חלה על השורה כולה.';

  static String sendError(Object error) => 'שגיאה בשליחת הדיווח: $error';

  static String handleError(Object error) => 'שגיאה בטיפול בדיווח: $error';

  static String savedForLater(int pendingCount) =>
      'הדיווח נשמר להמשך. יש כרגע $pendingCount דיווחים ממתינים בתור, וניתן לנהל את הדיווחים השמורים בהגדרות.';

  // ── ניהול התור בהגדרות (system_settings_tab) ───────────────────────────

  static const String markedAsSent = 'הדיווח סומן כנשלח.';
  static const String reportUpdated = 'הדיווח עודכן.';
  static const String detailsRequired =
      'לא ניתן לשמור דיווח ללא פירוט. הדיווח לא שונה.';
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

  // ── דיווח על התוכנה (app_report) ───────────────────────────────────────

  static String appReportSent(int? issueNumber) => issueNumber == null
      ? 'הדיווח נקלט אצל צוות אוצריא. תודה!'
      : 'הדיווח נקלט ונפתח עבורו דיווח מספר $issueNumber. תודה!';

  static String appReportMerged(int? issueNumber) => issueNumber == null
      ? 'הדיווח צורף לדיווח קיים על אותה תקלה. תודה!'
      : 'הדיווח צורף לדיווח קיים מספר $issueNumber על אותה תקלה. תודה!';

  static const String appReportQueued =
      'לא ניתן לשלוח כעת. הדיווח נשמר ויישלח אוטומטית בהמשך. '
      'ניתן לנהל את הדיווחים השמורים בהגדרות.';

  static String appReportRejected(String? field) => field == null
      ? 'השרת דחה את הדיווח, ולכן הוא לא נשמר לשליחה חוזרת.'
      : 'השרת דחה את הדיווח בגלל השדה "$field", ולכן הוא לא נשמר '
            'לשליחה חוזרת.';

  static const String appReportTitleRequired = 'יש למלא כותרת לדיווח.';
  static const String appReportDescriptionRequired =
      'יש לתאר את התקלה כדי שנוכל לטפל בה.';
  static const String appReportEmailRequired =
      'יש למלא כתובת דואר אלקטרוני תקינה — בלעדיה לא נוכל לחזור אליכם.';
  static const String appReportInvalidEmail =
      'כתובת הדואר האלקטרוני אינה תקינה.';
  static const String appReportCrashDismissed =
      'הדיווח על הקריסה לא נשלח. ניתן לדווח בכל עת דרך ההגדרות.';
  static const String appReportCannotOpenIssue =
      'לא ניתן לפתוח את הדיווח בדפדפן.';
  static String appReportImageTooLarge(int maxMegabytes) =>
      'תמונה גדולה מ-$maxMegabytes MB לא צורפה.';
  static String appReportTooManyImages(int maxCount) =>
      'ניתן לצרף עד $maxCount תמונות לדיווח.';
  static String appReportImagesTotalTooLarge(int maxMegabytes) =>
      'הגודל הכולל של התמונות מוגבל ל-$maxMegabytes MB.';
  static const String appReportImageReadFailed = 'לא ניתן היה לקרוא את התמונה.';

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
