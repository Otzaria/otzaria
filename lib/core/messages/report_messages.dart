/// ריכוז כל ההודעות למשתמש של מנגנון דיווח הטעויות.
///
/// כל טקסט שמוצג למשתמש בתהליך שליחת דיווח (ישיר, מייל וניהול
/// התור) מוגדר כאן בלבד — אין לכתוב מחרוזות דיווח בקבצי הפיצ'רים.
abstract class ReportMessages {
  static const extendedReportQueued =
      'הדיווח נשמר במלואו בתור. לאיסוף באמצעות תוכנת העדכון אופליין נדרשת גרסה תואמת; צרופות מורחבות דורשות גם שרת דיווחים מעודכן.';
  static const reportServerUpgradeRequired =
      'השרת עדיין אינו תומך בדיווח המלא הזה. הדיווח נשמר במלואו; ניתן לערוך אותו או לנסות שוב לאחר עדכון השרת.';
  static const reportRejectedPreserved =
      'השרת דחה את הדיווח. התוכן נשמר וניתן לערוך אותו או לנסות שוב.';
  static const portableSlowDriveHint =
      'התוכנה נתקעה או נסגרה כנראה בגלל כונן נייד איטי. '
      'מומלץ להעביר את ההתקנה הניידת לכונן פנימי או לכונן מהיר יותר.';

  // ── שליחה ישירה (DirectErrorReportService) ─────────────────────────────

  // "נקלט" ולא "אושר": הקליטה אינה הכרעה בתוכן הדיווח.
  static const String sentToOtzaria = 'הדיווח נקלט אצל צוות אוצריא. תודה!';
  static const String sentToSefaria = 'הדיווח נקלט ויועבר לספריא. תודה!';
  static const String sentSuccessTitle = 'הדיווח נקלט';
  static const String sendingTitle = 'שליחת הדיווח';
  static const String sending = 'שולח את הדיווח…';

  static const correctionNotSupportedTemplate =
      'הדיווח נקלט אצל {target}, אך השרת עדיין אינו תומך בהצעת תיקון '
      'מובנית. ההצעה נשלחה כטקסט בתוך פירוט הטעות ונשמרה בהיסטוריית '
      'הדיווחים.';
  static String correctionNotSupportedByServer(String targetLabel) =>
      correctionNotSupportedTemplate.replaceAll('{target}', targetLabel);
  static const String reportIdConflict =
      'השרת כבר קלט דיווח אחר עם אותו מזהה, ולכן הדיווח לא נקלט. '
      'ניתן לדווח שוב — דיווח חדש מקבל מזהה חדש.';
  static const String pendingReportIdConflict =
      'השרת כבר קלט דיווח אחר עם אותו מזהה, ולכן הדיווח לא נקלט. '
      'הדיווח קיבל מזהה חדש ונשאר בתור — ניתן לשלוח אותו שוב.';

  static const bodyTooLargeTemplate =
      'הדיווח גדול מדי לשליחה (הגבול הוא {limit}KB). יש לקצר את הפירוט '
      'או את ההצעה — הטקסט לא ייחתך.';
  static String bodyTooLarge(int maxKb) =>
      bodyTooLargeTemplate.replaceAll('{limit}', '$maxKb');

  static const duplicateReportTemplate =
      'דיווח זהה לזה כבר נשלח ל{target} בעבר, ולכן לא נשלחה הודעה נוספת. '
      'הדיווח נקלט במערכת.';
  static String duplicateReport(String targetLabel) =>
      duplicateReportTemplate.replaceAll('{target}', targetLabel);
  static const String offlineQueueDisabled =
      'מצב אופליין פעיל, והגדרת התור האוטומטי כבויה.';
  static const String noInternet = 'אין כרגע חיבור לאינטרנט.';
  static const String serverTimeout = 'השרת לא הגיב בזמן.';
  static const String sendFailed = 'שגיאה בשליחת הדיווח.';
  static const String unexpectedSendError =
      'אירעה שגיאה לא צפויה בשליחת הדיווח.';

  static const queuedOfflineTemplate =
      'אין כרגע חיבור. הדיווח נשמר ויישלח אוטומטית '
      'ל{target} כשהתוכנה תחזור להיות מקוונת. '
      'ניתן לנהל את הדיווחים השמורים בהגדרות.';
  static String queuedOffline(String targetLabel) =>
      queuedOfflineTemplate.replaceAll('{target}', targetLabel);

  static const queuedAfterFailureTemplate =
      'השליחה לא הצליחה כרגע. הדיווח נשמר להמשך ויישלח אוטומטית '
      'ל{target} בניסיון הבא. ניתן לנהל את הדיווחים '
      'השמורים בהגדרות.';
  static String queuedAfterFailure(String targetLabel) =>
      queuedAfterFailureTemplate.replaceAll('{target}', targetLabel);

  static const serverPermanentFailureTemplate =
      'שרת הדיווחים החזיר {status}. הדיווח לא נשמר להמשך כי נראה שיש בעיה קבועה בנתונים שנשלחו.';
  static String serverPermanentFailure(int statusCode) =>
      serverPermanentFailureTemplate.replaceAll('{status}', '$statusCode');

  static const serverTransientFailureTemplate =
      'שרת הדיווחים החזיר {status}. הדיווח יישמר להמשך.';
  static String serverTransientFailure(int statusCode) =>
      serverTransientFailureTemplate.replaceAll('{status}', '$statusCode');

  /// כותרת חלון הסיכום של סקריפט השליחה האופליין (bat/sh).
  static const String offlineScriptWindowTitle =
      'שליחת דיווחים שמורים - אוצריא';

  // ── דיאלוג הדיווח (error_report_dialog) ────────────────────────────────

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
      'ההצעה זהה למקור. יש לשנות את הטקסט או לבחור "מחיקת הקטע". '
      'אם אין הצעה — יש לבחור "דיווח חופשי".';

  static const proposalTooLongTemplate =
      'ההצעה ארוכה מדי (מעל {max} תווים). יש לקצר אותה — היא לא תיחתך.';
  static String proposalTooLong(int maxLength) =>
      proposalTooLongTemplate.replaceAll('{max}', '$maxLength');

  static const originalTooLongTemplate =
      'השורה המקורית ארוכה מ-{max} תווים, ולכן לא ניתן להציע לה תיקון '
      'מובנה. ניתן לשלוח דיווח חופשי.';
  static String originalTooLong(int maxLength) =>
      originalTooLongTemplate.replaceAll('{max}', '$maxLength');

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

  static const String appReportTitleRequired = 'יש למלא כותרת לדיווח.';
  static const String appReportDescriptionRequired =
      'יש לתאר את התקלה כדי שנוכל לטפל בה.';
  static const String appReportEmailRequired =
      'יש למלא כתובת דואר אלקטרוני תקינה — בלעדיה לא נוכל לחזור אליכם.';
  static const String appReportInvalidEmail =
      'כתובת הדואר האלקטרוני אינה תקינה.';
  static const String appReportDraftSaved =
      'הטיוטה נשמרה. היא תיפתח שוב בפעם הבאה שתפתחו את טופס הדיווח.';
  static const String appReportDraftDiscarded = 'הטיוטה נמחקה.';
  static const String appReportCannotOpenIssue =
      'לא ניתן לפתוח את הדיווח בדפדפן.';
  static const String appReportImageTooLargeTemplate =
      'תמונה גדולה מ-{limit} MiB לא צורפה.';
  static const String appReportTooManyImagesTemplate =
      'ניתן לצרף עד {count} תמונות לדיווח.';
  static const String appReportAttachmentsTooLargeTemplate =
      'הגודל הכולל של הצרופות מוגבל ל-{limit} MiB.';
  static const String appReportNoClipboardImage = 'אין תמונה נתמכת בלוח.';
  static const String appReportImageReadFailed = 'לא ניתן היה לקרוא את התמונה.';
}
