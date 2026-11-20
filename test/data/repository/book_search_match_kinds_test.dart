import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library_match_filter.dart';

/// סוג ההתאמה של כל תוצאה — הבסיס לצ'יפי הסינון בתוצאות האיתור (#4232).
void main() {
  const entries = [
    BookSearchEntry(
      index: 0,
      title: 'טור',
      author: 'רבנו יעקב בעל הטורים',
      topics: '',
      categoryPath: 'הלכה',
    ),
    BookSearchEntry(
      index: 1,
      title: 'עין יצחק',
      author: 'רבי יצחק אלחנן ספקטור',
      topics: '',
    ),
    BookSearchEntry(
      index: 2,
      title: 'פרישה',
      author: 'רבי יהושע פלק הכהן',
      topics: '',
      categoryPath: 'הלכה, טור, מפרשים',
    ),
    BookSearchEntry(
      index: 3,
      title: 'שולחן ערוך',
      author: '',
      topics: '',
      acronyms: ['שוע'],
    ),
    BookSearchEntry(
      index: 4,
      title: 'אור החיים',
      author: 'רבי חיים אבולעפיה',
      topics: '',
      categoryPath: 'מדרש',
    ),
    BookSearchEntry(
      index: 5,
      title: 'ספר המצות',
      author: '',
      topics: '',
      categoryPath: 'ספרי מצוות',
    ),
  ];

  Map<int, Set<BookMatchKind>> kindsFor(String query) {
    final matches = PreparedBookSearchIndex(entries).search(
      BookSearchQuery(
        queryWords: query.split(' '),
        topics: const [],
        sortByRatio: true,
        normalizedQuery: query,
      ),
    );
    return {
      for (var i = 0; i < matches.indices.length; i++)
        matches.indices[i]: {
          for (final kind in BookMatchKind.values)
            if (matches.kinds[i] & kind.bit != 0) kind,
        },
    };
  }

  test('שם, מחבר ונתיב התיקייה מסומנים כל אחד בנפרד', () {
    final kinds = kindsFor('טור');
    expect(kinds[0], {BookMatchKind.title, BookMatchKind.author});
    expect(kinds[1], {BookMatchKind.author});
    expect(kinds[2], {BookMatchKind.folder});
  });

  test('כינוי מסומן ככינוי ולא כשם', () {
    expect(kindsFor('שוע')[3], {BookMatchKind.acronym});
  });

  test('מילה שתאמה רק בכתיב דומה מסומנת ככזו', () {
    expect(kindsFor('אבועלפיה')[4], {BookMatchKind.spelling});
  });

  test('כתיב דומה בשם נשאר כזה גם כשהמילה מופיעה מילולית בנתיב', () {
    expect(kindsFor('מצוות')[5], {BookMatchKind.spelling});
  });

  test('התאמות לשם ולנתיב באותה שאילתה נשמרות בלי כתיב דומה', () {
    expect(kindsFor('טור הלכה')[0], {
      BookMatchKind.title,
      BookMatchKind.author,
      BookMatchKind.folder,
    });
  });

  test('כתיב דומה בספר והתאמה לנתיב נשמרים יחד', () {
    expect(kindsFor('אבועלפיה מדרש')[4], {
      BookMatchKind.spelling,
      BookMatchKind.folder,
    });
  });

  test('בלי מסנן הכול מוצג; עם מסנן — רק הסוגים שנבחרו', () {
    final authorOnly = BookMatchKind.author.bit;
    expect(LibraryMatchFilter.showsBook(const {}, authorOnly), isTrue);
    expect(
      LibraryMatchFilter.showsBook(const {
        LibraryMatchFilter.title,
      }, authorOnly),
      isFalse,
    );
    expect(
      LibraryMatchFilter.showsBook(const {
        LibraryMatchFilter.title,
        LibraryMatchFilter.author,
      }, authorOnly),
      isTrue,
    );
    expect(
      LibraryMatchFilter.showsBook(const {
        LibraryMatchFilter.folders,
      }, authorOnly),
      isFalse,
    );
  });

  test('כרטיסי התיקיות מוצגים רק כשאין מסנן או כשנבחרו', () {
    expect(LibraryMatchFilter.showsFolders(const {}), isTrue);
    expect(
      LibraryMatchFilter.showsFolders(const {LibraryMatchFilter.title}),
      isFalse,
    );
    expect(
      LibraryMatchFilter.showsFolders(const {LibraryMatchFilter.folders}),
      isTrue,
    );
  });

  test('present מחזיר רק סוגים שיש להם תוצאות', () {
    expect(
      LibraryMatchFilter.present([
        BookMatchKind.title.bit,
        BookMatchKind.author.bit | BookMatchKind.spelling.bit,
      ], hasFolders: false),
      {
        LibraryMatchFilter.title,
        LibraryMatchFilter.author,
        LibraryMatchFilter.spelling,
      },
    );
    expect(LibraryMatchFilter.present(const [], hasFolders: true), {
      LibraryMatchFilter.folders,
    });
  });
}
