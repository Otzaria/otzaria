import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

/// מפתח הספר של הערות אישיות. ספר רשמי ואישי ממופתחים לפי הכותרת, כמו בהערות
/// שכבר נשמרו; ספר ממסד מצורף מקבל `title|db:<slug>` כדי לא להתערבב איתם.
String personalNotesBookKey(Book book) =>
    personalNotesBookKeyFor(book.title, book.source);

/// מפתחות ההערות של כל הספרים ב-[category] ובתתי-הקטגוריות שלה.
/// Set ולא List: הסינון בודק כל הערה מול הקטגוריה, שעשויה להכיל אלפי ספרים.
Set<String> personalNotesBookKeysInCategory(Category category) {
  final keys = <String>{};
  void collect(Category cat) {
    for (final book in cat.books) {
      keys.add(personalNotesBookKey(book));
    }
    cat.subCategories.forEach(collect);
  }

  collect(category);
  return keys;
}

/// מספר ההערות של כל קטגוריה בעץ [root], במעבר אחד. ספר כפול (טקסט + PDF)
/// נספר פעם אחת בתוך הקטגוריה שלו.
Map<Category, int> personalNotesCategoryCounts(
  Category root,
  int Function(String bookKey) countForBook,
) {
  final counts = <Category, int>{};
  int visit(Category category) {
    var count = 0;
    final seenKeys = <String>{};
    for (final book in category.books) {
      final key = personalNotesBookKey(book);
      if (seenKeys.add(key)) count += countForBook(key);
    }
    for (final sub in category.subCategories) {
      count += visit(sub);
    }
    return counts[category] = count;
  }

  visit(root);
  return counts;
}

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

/// הספר בקטלוג שאליו שייך מפתח ההערות [key]. מפתח בלי סיומת מצורף אינו
/// נפתר לעולם לספר ממסד מצורף בכותרת זהה.
Book? findBookForPersonalNotesKey(Library library, String key) {
  final text = findTextBookForPersonalNotesKey(library, key);
  if (text != null) return text;
  final parsed = parsePersonalNotesBookKey(key);
  return _candidates(library, parsed.title, parsed.source).firstOrNull;
}

/// כמו [findBookForPersonalNotesKey], רק ספר שנפתח בקורא הטקסט.
TextBook? findTextBookForPersonalNotesKey(Library library, String key) {
  final parsed = parsePersonalNotesBookKey(key);
  final candidates = _candidates(library, parsed.title, parsed.source);
  final direct = candidates.where((b) => b.runtimeType == TextBook).firstOrNull;
  if (direct is TextBook) return direct;
  final document = candidates.whereType<ConvertibleDocumentBook>().firstOrNull;
  return document?.toTextBook();
}

Iterable<Book> _candidates(Library library, String title, BookSource? source) =>
    library.getAllBooks().where(
      (b) =>
          b.title == title &&
          (source == null ? !b.source.isAttached : b.source == source),
    );
