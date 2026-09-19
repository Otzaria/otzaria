// לוגיקה טהורה לבניית קישורי deep link לספרים.
// קובץ זה אינו תלוי ב-Flutter ולכן ניתן לבדיקה עם dart test רגיל.

import 'package:otzaria/models/book_source.dart';

/// ערך הפרמטר `source` בקישור: אין לרשמי, `user` לאישי, `db:<slug>` למצורף.
String? bookLinkSourceParam(BookSource source) => switch (source) {
  OfficialBookSource() => null,
  UserBookSource() => 'user',
  AttachedBookSource(:final slug) => 'db:$slug',
};

/// המקור מתוך הפרמטר `source` של קישור (בלי פרמטר — רשמי). null לערך לא מוכר.
BookSource? parseBookLinkSourceParam(String? value) {
  if (value == null) return BookSource.official;
  final trimmed = value.trim();
  final lower = trimmed.toLowerCase();
  if (lower == 'official') return BookSource.official;
  if (lower == 'user') return BookSource.user;
  if (lower.startsWith('db:')) {
    final slug = trimmed.substring(3);
    return BookSource.isValidSlug(slug) ? BookSource.attached(slug) : null;
  }
  return null;
}

String _bookSourceSuffix(BookSource source) {
  final param = bookLinkSourceParam(source);
  return param == null ? '' : '?source=${Uri.encodeQueryComponent(param)}';
}

String _queryPrefix(BookSource source) {
  final param = bookLinkSourceParam(source);
  return param == null ? '?' : '?source=${Uri.encodeQueryComponent(param)}&';
}

/// בניית קישור ישיר לספר טקסט לפי מזהה ומקור.
String buildBookLink(int bookId, {BookSource source = BookSource.official}) =>
    'otzaria://open/book/$bookId${_bookSourceSuffix(source)}';

/// בניית קישור ישיר לספר PDF לפי מזהה ומקור.
String buildPdfBookLink(
  int bookId, {
  BookSource source = BookSource.official,
}) => 'otzaria://open/pdf/$bookId${_bookSourceSuffix(source)}';

/// בניית קישור ישיר למקטע ספציפי בספר טקסט.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionLink(
  int bookId,
  int index, {
  BookSource source = BookSource.official,
}) =>
    'otzaria://open/book/$bookId${_queryPrefix(source)}index=${index < 0 ? 0 : index}';

/// בניית קישור ישיר לעמוד ספציפי בספר PDF.
/// ערכי page שליליים מוחלפים ב-1.
String buildPdfPageLink(
  int bookId,
  int page, {
  BookSource source = BookSource.official,
}) =>
    'otzaria://open/pdf/$bookId${_queryPrefix(source)}index=${page < 1 ? 1 : page}';

/// בניית קישור למקטע עם הדגשת המקטע כולו.
/// ערכי index שליליים מוחלפים ב-0.
String buildSectionMarkLink(
  int bookId,
  int index, {
  BookSource source = BookSource.official,
}) =>
    'otzaria://open/book/$bookId${_queryPrefix(source)}index=${index < 0 ? 0 : index}&mark';

/// בניית קישור למקטע עם הדגשת טקסט ספציפי.
/// text ריק או רווחים בלבד → מחזיר null (לא לבנות קישור).
/// ערכי index שליליים מוחלפים ב-0.
String? buildTextMarkLink(
  int bookId,
  int index,
  String text, {
  BookSource source = BookSource.official,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  final encoded = Uri.encodeComponent(trimmed);
  return 'otzaria://open/book/$bookId${_queryPrefix(source)}index=${index < 0 ? 0 : index}&m=$encoded';
}

/// בניית רשימת פריטי תת-תפריט "העתק קישור ישיר" עבור תפריט הלחיצה הימנית.
/// הקישור לספר עצמו מוצג בתפריט "אפשרויות נוספות" שבסרגל העליון, ולכן אינו
/// כלול כאן כדי למנוע כפילות.
/// מחזיר 2 פריטים ללא טקסט מסומן, 3 פריטים עם טקסט מסומן לא-ריק.
/// כל פריט מכיל label ו-link (link יכול להיות null אם הבנייה נכשלה).
List<({String label, String? link})> buildDirectLinkSubmenuEntries({
  required int bookId,
  BookSource source = BookSource.official,
  required int index,
  required String? selectedText,
}) {
  final entries = <({String label, String? link})>[
    (
      label: 'העתק קישור למקטע זה',
      link: buildSectionLink(bookId, index, source: source),
    ),
    (
      label: 'העתק קישור עם הדגשת המקטע',
      link: buildSectionMarkLink(bookId, index, source: source),
    ),
  ];

  if (selectedText != null && selectedText.trim().isNotEmpty) {
    entries.add((
      label: 'העתק קישור עם הדגשת הטקסט',
      link: buildTextMarkLink(
        bookId,
        index,
        selectedText,
        source: source,
      ),
    ));
  }

  return entries;
}
