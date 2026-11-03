import 'package:otzaria/data/book_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';

class _FakeSearchResult {
  final String filePath;

  _FakeSearchResult(this.filePath);
}

void main() {
  group('FacetHelper.buildFacetCountsFromResults', () {
    test('מחשב ספירות עבור שורש, אבות וספרים', () {
      final genesis = TextBook(
        id: 101,
        title: 'בראשית',
        categoryPath: '/תנ"ך/תורה',
      );
      final berachot = TextBook(
        id: 202,
        title: 'ברכות',
        categoryPath: '/משנה/זרעים',
      );

      final bookByIndexedFilePath = <String, Book>{
        BookIdentity.indexedFilePath(genesis): genesis,
        BookIdentity.indexedFilePath(berachot): berachot,
      };

      final counts = FacetHelper.buildFacetCountsFromResults(
        [
          _FakeSearchResult(
            BookIdentity.indexedFilePath(genesis),
          ),
          _FakeSearchResult(
            BookIdentity.indexedFilePath(berachot),
          ),
        ],
        bookByIndexedFilePath,
      );

      expect(counts['/'], 2);
      expect(counts['/תנ"ך'], 1);
      expect(counts['/תנ"ך/תורה'], 1);
      expect(counts['/תנ"ך/תורה/id:101'], 1);
      expect(counts['/משנה'], 1);
      expect(counts['/משנה/זרעים'], 1);
      expect(counts['/משנה/זרעים/id:202'], 1);
    });

    test('מבדיל בין ספרים עם אותו שם לפי מפתח ה-filePath היציב', () {
      final firstBook = TextBook(
        id: 11,
        title: 'שבת',
        categoryPath: '/תלמוד בבלי/סדר מועד',
      );
      final secondBook = TextBook(
        id: 22,
        title: 'שבת',
        categoryPath: '/הלכה',
      );

      final counts = FacetHelper.buildFacetCountsFromResults(
        [
          _FakeSearchResult(
            BookIdentity.indexedFilePath(firstBook),
          ),
          _FakeSearchResult(
            BookIdentity.indexedFilePath(secondBook),
          ),
        ],
        {
          BookIdentity.indexedFilePath(firstBook): firstBook,
          BookIdentity.indexedFilePath(secondBook): secondBook,
        },
      );

      expect(counts['/תלמוד בבלי/סדר מועד/id:11'], 1);
      expect(counts['/הלכה/id:22'], 1);
    });

    test('תוצאה של ספר שכבר אינו בספרייה מדולגת בשקט', () {
      final counts = FacetHelper.buildFacetCountsFromResults(
        [_FakeSearchResult('uid:99')],
        const <String, Book>{},
      );

      expect(counts, isEmpty);
    });
  });

  group('FacetHelper.buildFacetCountsFromBookCounts', () {
    test('מחשב ספירות אגרגטיביות ממפת ספרים ייחודית', () {
      final genesis = TextBook(
        title: 'בראשית',
        id: 101,
        categoryPath: '/תנ"ך/תורה',
      );
      final berachot = TextBook(
        title: 'ברכות',
        id: 202,
        categoryPath: '/משנה/זרעים',
      );

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        {
          BookIdentity.indexedFilePath(genesis): 3,
          BookIdentity.indexedFilePath(berachot): 2,
        },
        {
          BookIdentity.indexedFilePath(genesis): genesis,
          BookIdentity.indexedFilePath(berachot): berachot,
        },
      );

      expect(counts['/'], 5);
      expect(counts['/תנ"ך'], 3);
      expect(counts['/תנ"ך/תורה'], 3);
      expect(counts['/תנ"ך/תורה/id:101'], 3);
      expect(counts['/משנה'], 2);
      expect(counts['/משנה/זרעים'], 2);
      expect(counts['/משנה/זרעים/id:202'], 2);
    });

    test('מנרמל categoryPath עם פסיקים לפני בניית facets', () {
      final genesis = TextBook(
        title: 'בראשית',
        id: 101,
        categoryPath: 'תנ"ך, תורה',
      );

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        {
          BookIdentity.indexedFilePath(genesis): 1,
        },
        {
          BookIdentity.indexedFilePath(genesis): genesis,
        },
      );

      expect(counts['/'], 1);
      expect(counts['/תנ"ך'], 1);
      expect(counts['/תנ"ך/תורה'], 1);
      expect(counts['/תנ"ך/תורה/id:101'], 1);
      expect(counts.containsKey('/תנ"ך, תורה'), isFalse);
    });
  });

  group('FacetHelper.buildFacetCountsFromBookCounts — ספרים רבים בקטגוריה', () {
    late _CountingCategory leaf;
    late Map<String, int> bookCounts;
    late Map<String, Book> booksByKey;

    setUp(() {
      final root = _category('ספריית אוצריא', null);
      final talmud = _category('תלמוד בבלי', root);
      leaf = _CountingCategory(_category('סדר מועד', talmud));
      bookCounts = {};
      booksByKey = {};
      for (var i = 0; i < 40; i++) {
        final book = TextBook(title: 'מסכת $i', id: 300 + i, category: leaf);
        final key = BookIdentity.indexedFilePath(book);
        bookCounts[key] = i + 1;
        booksByKey[key] = book;
      }
      final loose = TextBook(title: 'ספר בלי קטגוריה', id: 900);
      final looseKey = BookIdentity.indexedFilePath(loose);
      bookCounts[looseKey] = 7;
      booksByKey[looseKey] = loose;
    });

    test('נתיב הקטגוריה מחושב פעם אחת לקטגוריה ולא לכל ספר', () {
      FacetHelper.buildFacetCountsFromBookCounts(bookCounts, booksByKey);
      expect(leaf.pathReads, 1);
    });

    test('הספירות זהות לחישוב ספר-ספר', () {
      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        bookCounts,
        booksByKey,
      );

      expect(counts, _countsBookByBook(bookCounts, booksByKey));
      expect(counts['/'], 827);
      expect(counts['/תלמוד בבלי/סדר מועד'], 820);
    });

    test('הספירות זהות לחישוב ספר-ספר בעץ בכמה עומקים עם אבות משותפים', () {
      final root = _category('ספריית אוצריא', null);
      final talmud = _category('תלמוד בבלי', root);
      final nashim = _category('סדר נשים', talmud);
      final shulchanAruch = _category('שולחן ערוך', _category('הלכה', root));
      final books = [
        TextBook(title: 'ברכות', id: 1, category: talmud),
        TextBook(title: 'שבת', id: 2, category: leaf),
        TextBook(title: 'יבמות', id: 3, category: nashim),
        TextBook(title: 'כתובות', id: 4, category: nashim),
        TextBook(
          title: 'קצות החושן',
          id: 5,
          category: _category('חושן משפט, ביאורים', shulchanAruch),
        ),
        TextBook(title: 'אורח חיים', id: 6, category: shulchanAruch),
        TextBook(title: 'ספר בשורש', id: 7, category: root),
        TextBook(title: 'בראשית', id: 8, categoryPath: 'תנ"ך, תורה'),
        TextBook(title: 'שמות', id: 9, topics: 'תנ"ך, תורה'),
        TextBook(title: 'ספר בלי מיקום', id: 10),
      ];
      final counts = <String, int>{};
      final byKey = <String, Book>{};
      for (final (i, book) in books.indexed) {
        final key = BookIdentity.indexedFilePath(book);
        counts[key] = i + 1;
        byKey[key] = book;
      }

      final facetCounts = FacetHelper.buildFacetCountsFromBookCounts(
        counts,
        byKey,
      );

      expect(facetCounts, _countsBookByBook(counts, byKey));
      expect(facetCounts['/'], 55);
      expect(facetCounts['/תלמוד בבלי'], 1 + 2 + 3 + 4);
      expect(facetCounts['/הלכה/שולחן ערוך/חושן משפט/ביאורים'], 5);
    });
  });
}

Category _category(String title, Category? parent) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: [],
  books: [],
  parent: parent,
);

/// החישוב ספר-ספר: נתיב ואבות מלאים לכל ספר בנפרד.
Map<String, int> _countsBookByBook(
  Map<String, int> bookCounts,
  Map<String, Book> booksByKey,
) {
  final expected = <String, int>{};
  for (final MapEntry(:key, :value) in bookCounts.entries) {
    final book = booksByKey[key]!;
    final categoryPath = FacetHelper.resolveCategoryPath(book);
    FacetHelper.incrementFacet(
      expected,
      FacetHelper.buildBookFacet(categoryPath, book),
      value,
    );
    if (categoryPath != null && categoryPath.isNotEmpty) {
      FacetHelper.incrementFacetWithAncestors(expected, categoryPath, value);
    } else {
      FacetHelper.incrementFacet(expected, '/', value);
    }
  }
  return expected;
}

class _CountingCategory extends Category {
  _CountingCategory(Category source)
    : super(
        title: source.title,
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: source.parent,
      );

  int pathReads = 0;

  @override
  String get path {
    pathReads++;
    return super.path;
  }
}
