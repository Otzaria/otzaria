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

/// בניית קישור למקטע עם הדגשת המקטע כולו.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionMarkLink(int bookId, int index) =>
    'otzaria://open/book/$bookId?index=${index < 0 ? 0 : index}&mark';

/// בניית קישור למקטע עם הדגשת טקסט ספציפי.
/// text ריק או רווחים בלבד → מחזיר null (לא לבנות קישור).
/// ערכי index שליליים מוחלפים ב-0.
String? buildTextMarkLink(int bookId, int index, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final encoded = Uri.encodeComponent(trimmed);
  return 'otzaria://open/book/$bookId?index=${index < 0 ? 0 : index}&m=$encoded';
}

/// בניית רשימת פריטי תת-תפריט "העתק קישור ישיר".
/// מחזיר 3 פריטים ללא טקסט מסומן, 4 פריטים עם טקסט מסומן לא-ריק.
/// כל פריט מכיל label ו-link (link יכול להיות null אם הבנייה נכשלה).
List<({String label, String? link})> buildDirectLinkSubmenuEntries({
  required int bookId,
  required int index,
  required String? selectedText,
}) {
  final entries = <({String label, String? link})>[
    (label: 'העתק קישור ישיר לספר זה', link: buildBookLink(bookId)),
    (label: 'העתק קישור למקטע זה', link: buildSectionLink(bookId, index)),
    (
      label: 'העתק קישור עם הדגשת המקטע',
      link: buildSectionMarkLink(bookId, index)
    ),
  ];

  if (selectedText != null && selectedText.trim().isNotEmpty) {
    entries.add((
      label: 'העתק קישור עם הדגשת הטקסט',
      link: buildTextMarkLink(bookId, index, selectedText),
    ));
  }

  return entries;
}
