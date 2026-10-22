/// ריכוז הודעות המערכת (UiSnack) של המרקר.
abstract class MarkerMessages {
  // ===== סימון בספר =====
  static String marked(String color) => 'סומן ב$color';
  static String recolored(String color) => 'הצבע שונה ל$color';
  static const String alreadyMarked = 'הטקסט כבר מסומן בצבע הזה';
  static const String repaired = 'הסימון עודכן לטקסט שנבחר';
  static String markedWhileHidden(String color) =>
      'סומן ב$color, אבל הצגת הסימונים כבויה בהגדרות המרקר';
  static const String cannotAnchor =
      'לא ניתן לסמן את הטקסט שנבחר. נסו לבחור אותו מחדש.';
  static const String noSelection = 'בחרו טקסט כדי לסמן אותו';
  static String removed(int count) =>
      count == 1 ? 'הסימון הוסר' : '$count סימונים הוסרו';
  static const String undo = 'ביטול';
  static const String restored = 'הסימון הוחזר';
  static const String removeFailed = 'הסרת הסימון נכשלה';
  static const String restoreFailed = 'החזרת הסימון נכשלה';
  static const String copied = 'הסימון הועתק';
  static const String bookHidden =
      'הסימונים בספר הזה מוסתרים. לחיצה נוספת תחזיר אותם.';
  static const String bookShown = 'הסימונים בספר הזה מוצגים שוב';
  static const String highlightsTurnedOn =
      'הצגת הסימונים הופעלה מחדש בכל הספרים';

  // ===== עריכה =====
  static const String noteSaved = 'ההערה נשמרה';
  static const String noteDeleted = 'ההערה נמחקה';
  static const String draftRestored = 'נטענה טיוטה שלא נשמרה';
  static const String tagsSaved = 'התגיות נשמרו';
  static const String rangeSaved = 'גבולות הסימון עודכנו';
  static const String moved = 'הסימון הועבר לטקסט שנבחר';
  static const String moveNeedsSelection =
      'בחרו בספר את הטקסט שאליו להעביר את הסימון, ולחצו שוב';
  static const String moveOtherBook = 'הטקסט שנבחר אינו בספר של הסימון';
  static const String rangeNeedsBook =
      'טקסט הסימון עוד לא נטען. נסו שוב בעוד רגע';
  static const String sourceUnavailable = 'לא ניתן לקרוא את טקסט הסימון מהספר';
  static const String rangeOutdated =
      'הסימון אינו תואם לטקסט הנוכחי. סמנו אותו מחדש.';
  static const String tooLong = 'הקטע ארוך מכדי לסמן אותו בבת אחת';
  static const String deletedElsewhere = 'הסימון נמחק בינתיים, בחלון אחר';
  static const String changedElsewhere =
      'הסימון השתנה בחלון אחר מאז שנפתח לעריכה.';
  static const String saveFailed = 'שמירת הסימון נכשלה';
  static const String loadFailed = 'טעינת הסימונים נכשלה';
  static String colorChanged(int count, String color) =>
      count == 1 ? 'הצבע שונה ל$color' : 'הצבע של $count סימונים שונה ל$color';
  static String tagsAdded(int count) =>
      count == 1 ? 'התגיות נוספו לסימון' : 'התגיות נוספו ל-$count סימונים';
  static String tagReplaced(int count) =>
      count == 1 ? 'התגית עודכנה בסימון אחד' : 'התגית עודכנה ב-$count סימונים';

  // ===== ניווט =====
  static const String bookNotFound = 'הספר של הסימון לא נמצא בספרייה';
  static const String libraryNotReady = 'הספרייה עדיין נטענת';

  // ===== ייבוא, ייצוא וגיבוי =====
  static const String exportCompleted = 'הייצוא הושלם';
  static const String exportFailed = 'הייצוא נכשל';
  static const String backupCompleted = 'הגיבוי נשמר';
  static const String nothingToExport = 'אין סימונים לייצוא';
  static const String importFileTooLarge = 'הקובץ גדול מדי לייבוא';
  static const String importInvalidFile =
      'הקובץ אינו גיבוי של המרקר או שהוא פגום';
  static const String importNothingFound = 'לא נמצאו בקובץ סימונים תקינים';
  static const String importNoLegacyData =
      'לא נמצאו סימונים של תוסף המרקר הישן';
  static String importCompleted(int added, int skipped) {
    final done = switch (added) {
      0 => 'לא נוספו סימונים חדשים',
      1 => 'יובא סימון אחד',
      _ => 'יובאו $added סימונים',
    };
    if (skipped == 0) return done;
    return skipped == 1
        ? '$done, סימון אחד כבר היה קיים'
        : '$done, $skipped כבר היו קיימים';
  }

  static const String importFailed = 'הייבוא נכשל ולא שינה דבר';
  static const String importReadFailed = 'קריאת הקובץ נכשלה';
  static const String importLegacyReadFailed =
      'קריאת הנתונים של תוסף המרקר הישן נכשלה. הנתונים שלו לא שונו.';
  static const String safetyBackupFailed =
      'שמירת הגיבוי שלפני הייבוא נכשלה, ולכן הייבוא לא בוצע';
  static const String paletteImportFailed =
      'הסימונים יובאו, אבל טעינת הצבעים מהקובץ נכשלה';
}
