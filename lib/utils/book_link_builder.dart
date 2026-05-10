// לוגיקה טהורה לבניית קישורי deep link לספרים.
// קובץ זה אינו תלוי ב-Flutter ולכן ניתן לבדיקה עם dart test רגיל.

/// בניית קישור ישיר לספר לפי מזהה
String buildBookLink(int bookId) => 'otzaria://open/book/$bookId';

/// בניית קישור ישיר למקטע/עמוד ספציפי בספר.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionLink(int bookId, int index) =>
    'otzaria://open/book/$bookId?index=${index < 0 ? 0 : index}';
