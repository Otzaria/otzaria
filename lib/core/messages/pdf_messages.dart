/// ריכוז הודעות המערכת (UiSnack) של צפיין ה-PDF וההדפסה.
abstract class PdfMessages {
  static const String noCommentariesToPrint = 'אין מפרשים להדפסה';
  static const String directLinkUnavailableForBook =
      'קישור ישיר אינו זמין לספר זה';
  static const String perBookSettingsReset = 'ההגדרות הפר-ספריות אופסו בהצלחה';
  static const String textLocationNotFoundOpeningAtStart =
      'לא נמצא מיקום תואם בטקסט — הספר נפתח מתחילתו';
  static const String searchError = 'שגיאה בחיפוש';
  static const String noTextLayer =
      'ספר זה הוא סריקה בלבד ואינו מכיל טקסט, ולכן לא ניתן לחפש בתוכו';
  static const String advancedSearchUnavailableInTalmudPdf =
      'חיפוש מתקדם אינו זמין במהדורת ה-PDF של התלמוד הבבלי. '
      'ניתן לחפש בגרסת הטקסט של המסכת, ולפתוח משם את התוצאה.';
  static const String bookNotInSearchIndex =
      'הספר אינו נמצא באינדקס החיפוש, ולכן חיפוש מתקדם אינו זמין בו. עדכון האינדקס מתבצע בהגדרות הספרייה.';
  static const String pageRangeRenderFailed = 'עיבוד טווח העמודים שנבחר נכשל';
  static const String multiPageSheetRenderFailed =
      'עיבוד עמודים מרובים בגיליון נכשל';
  static const String wordFileSaved = 'קובץ Word נשמר בהצלחה';
  static const String pdfFileSaved = 'קובץ PDF נשמר בהצלחה';
  static const String fileLockedByAnotherApp =
      'לא ניתן לשמור את הקובץ כי הוא פתוח בתוכנה אחרת. יש לסגור אותו ולנסות שוב.';

  static const String editableExportRestricted =
      'ספר זה אינו ניתן לייצוא לפורמט הניתן לעריכה. ניתן להדפיסו או לשמרו כ-PDF.';

  static const String saferModeNoPrinter =
      'במצב סייפר ניתן להדפיס רק למדפסת נייר, ולא נמצאה מדפסת כזו. '
      'לפתיחת דיאלוג ההדפסה של המערכת נדרשת סיסמה.';

  static String fileExportFailed(Object error) => 'ייצוא הקובץ נכשל: $error';
  static String printFailed(String printer) => 'ההדפסה למדפסת "$printer" נכשלה';
}
