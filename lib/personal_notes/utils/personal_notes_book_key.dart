import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// מפתח הספר של הערות אישיות. ספר רשמי ואישי ממופתחים לפי הכותרת, כמו בהערות
/// שכבר נשמרו; ספר ממסד מצורף מקבל `title|db:<slug>` כדי לא להתערבב איתם.
String personalNotesBookKey(Book book) =>
    personalNotesBookKeyFor(book.title, book.source);

/// כמו [personalNotesBookKey], מכותרת ומקור.
String personalNotesBookKeyFor(String title, BookSource source) =>
    switch (source) {
      AttachedBookSource(:final slug) => '$title|db:$slug',
      _ => title,
    };

/// מפרק מפתח שנבנה ב-[personalNotesBookKeyFor] לכותרת ולמקור. מפתח בלי
/// סיומת מצורף מחזיר מקור null — רשמי או אישי, לפי הכותרת בלבד.
({String title, BookSource? source}) parsePersonalNotesBookKey(String key) {
  final marker = key.lastIndexOf('|db:');
  if (marker > 0) {
    final slug = key.substring(marker + 4);
    if (BookSource.isValidSlug(slug)) {
      return (
        title: key.substring(0, marker),
        source: BookSource.attached(slug),
      );
    }
  }
  return (title: key, source: null);
}
