/// ריכוז הודעות המערכת (UiSnack) של צפיין ה-PDF וההדפסה.
abstract class PdfMessages {
  static const String textSelectionLoading =
      'המסמך עדיין נטען. יש לנסות שוב לאחר סיום הטעינה';
  static const String textSelectionFailed = 'שגיאה בבחירת הטקסט';
  static const String noCommentariesToPrint = 'אין מפרשים להדפסה';
  static const String directLinkUnavailableForBook =
      'קישור ישיר אינו זמין לספר זה';
  static const String perBookSettingsReset = 'ההגדרות הפר-ספריות אופסו בהצלחה';
  static const String textLocationNotFoundOpeningAtStart =
      'לא נמצא מיקום תואם בטקסט — הספר נפתח מתחילתו';
  static const String noTextLayer =
      'ספר זה הוא סריקה בלבד ואינו מכיל טקסט, ולכן לא ניתן לחפש בתוכו';
  static const String advancedSearchUnavailableInTalmudPdf =
      'חיפוש מתקדם אינו זמין במהדורת ה-PDF של התלמוד הבבלי. '
      'ניתן לחפש בגרסת הטקסט של המסכת, ולפתוח משם את התוצאה.';
  static const String bookNotInSearchIndex =
      'הספר אינו נמצא באינדקס החיפוש, ולכן חיפוש מתקדם אינו זמין בו. עדכון האינדקס מתבצע בהגדרות הספרייה.';
  static const String personalBookNotInSearchIndex =
      'ספרים אישיים אינם נכללים באינדקס החיפוש לפי הגדרת "עדכון אינדקס אוטומטי", ולכן חיפוש מתקדם אינו זמין בספר זה.';
  static const String pageRangeRenderFailed = 'עיבוד טווח העמודים שנבחר נכשל';
  static const String multiPageSheetRenderFailed =
      'עיבוד עמודים מרובים בגיליון נכשל';
  static const String wordFileSaved = 'קובץ Word נשמר בהצלחה';
  static const String pdfFileSaved = 'קובץ PDF נשמר בהצלחה';
  static const String fileLockedByAnotherApp =
      'לא ניתן לשמור את הקובץ כי הוא פתוח בתוכנה אחרת. יש לסגור אותו ולנסות שוב.';

  static const String editableExportRestricted =
      'ספר זה אינו ניתן לייצוא לפורמט הניתן לעריכה. ניתן להדפיסו או לשמרו כ-PDF.';
  static const String exportFormatRestrictedByPublisher =
      'לבקשת המו"ל, לא ניתן לשמור ספר זה בפורמט זה. ניתן להדפיסו.';

  static String printLimitedByPublisher(int maxLines) =>
      'לבקשת המו"ל, ניתן להדפיס מספר זה עד $maxLines שורות בכל פעם';
  static String commentaryPrintLimitedByPublisher(int maxLines) =>
      'לבקשת המו"ל, מפרשים מסוימים יודפסו עד $maxLines קטעים בכל פעם';

  static const String saferModeNoPrinter =
      'במצב סייפר ניתן להדפיס רק למדפסת נייר, ולא נמצאה מדפסת כזו. '
      'לפתיחת דיאלוג ההדפסה של המערכת נדרשת סיסמה.';

  static String fileExportFailed(Object error) => 'ייצוא הקובץ נכשל: $error';
  static const String printSent = 'המסמך נשלח להדפסה';

  static const String printError =
      'ההדפסה נכשלה. פרטי השגיאה נרשמו ביומן השגיאות.';
  static String printFailed(String printer) => 'ההדפסה למדפסת "$printer" נכשלה';
  static String saferDirectPrint(String printer) =>
      'מצב סייפר: ההדפסה נשלחת ישירות למדפסת "$printer", ללא דיאלוג ההדפסה של המערכת';
  static const String printPreparing = 'מכין…';
  static const String printSending = 'שולח…';
  static const String closeWhilePrintingTitle = 'הדפסה פעילה';
  static const String closeWhilePrinting =
      'הדפסה עדיין נשלחת למדפסת. לצאת בכל זאת?';
  static const String closeWhilePrintingConfirm = 'צא בכל זאת';
}
