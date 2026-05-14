// לוגיקה טהורה לבניית קישורי deep link לספרים.
// קובץ זה אינו תלוי ב-Flutter ולכן ניתן לבדיקה עם dart test רגיל.

/// בניית קישור ישיר לספר טקסט לפי מזהה
String buildBookLink(int bookId) => 'otzaria://open/book/$bookId';

/// בניית קישור ישיר לספר PDF לפי מזהה (משותף עם TextBook)
String buildPdfBookLink(int bookId) => 'otzaria://open/pdf/$bookId';

/// בניית קישור ישיר למקטע ספציפי בספר טקסט.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionLink(int bookId, int index) =>
    'otzaria://open/book/$bookId?index=${index < 0 ? 0 : index}';

/// בניית קישור ישיר לעמוד ספציפי בספר PDF.
/// ערכי page שליליים מוחלפים ב-1.
String buildPdfPageLink(int bookId, int page) =>
    'otzaria://open/pdf/$bookId?index=${page < 1 ? 1 : page}';
