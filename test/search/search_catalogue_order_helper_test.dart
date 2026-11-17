import 'package:otzaria/data/book_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';

void main() {
  group('SearchCatalogueOrderHelper', () {
    test('הסדר הקטלוגי: קטגוריות עליונות לפי הסדר הקבוע, ספרים לפי order', () {
      final ordered = SearchCatalogueOrderHelper.buildOrderedKeys<String>(
        _buildLibrary(),
        keyOf: (book) => book.title as String,
      );

      expect(ordered, ['בראשית', 'שבת', 'חגיגה', 'משנה תורה, הלכות שבת']);
    });

    test('ספרים מצורפים בסוף ומפתח כפול שומר את המיקום הראשון', () {
      final attached = BookSource.attached('מצורף');
      final library = Library(categories: [])
        ..books.addAll([
          TextBook(title: 'מצורף בעץ', order: 0, source: attached),
          TextBook(title: 'בראשית', order: 1),
        ])
        ..offTreeBooks = [
          TextBook(title: 'בראשית'),
          TextBook(title: 'גרסה נוספת'),
          TextBook(title: 'מצורף מחוץ לעץ', source: attached),
        ];
      String keyOf(dynamic book) => (book as Book).title;

      expect(
        SearchCatalogueOrderHelper.buildOrderedKeys(library, keyOf: keyOf),
        ['בראשית', 'בראשית', 'גרסה נוספת', 'מצורף בעץ', 'מצורף מחוץ לעץ'],
      );
      expect(
        SearchCatalogueOrderHelper.buildKeyOrderMap(library, keyOf: keyOf),
        {'בראשית': 0, 'גרסה נוספת': 2, 'מצורף בעץ': 3, 'מצורף מחוץ לעץ': 4},
      );
    });

    test('דירוג קטגוריות עליונות משמר סדר קבוע ונפילה לסדר מותאם', () {
      final library = _buildLibrary();
      final tanakh = library.subCategories.singleWhere(
        (category) => category.title == 'תנ"ך',
      );
      final halacha = library.subCategories.singleWhere(
        (category) => category.title == 'הלכה',
      );

      expect(
        SearchCatalogueOrderHelper.topCategoryOrder(tanakh),
        lessThan(SearchCatalogueOrderHelper.topCategoryOrder(halacha)),
      );
      final unknown = Category(
        title: 'קטגוריה אחרת',
        description: '',
        shortDescription: '',
        order: 3,
        subCategories: [],
        books: [],
        parent: library,
      );
      expect(
        SearchCatalogueOrderHelper.topCategoryOrder(unknown),
        greaterThan(SearchCatalogueOrderHelper.topCategoryOrder(halacha)),
      );
    });

    test('ספרי הקטגוריה קודמים למפרשים שבתת-קטגוריה (issue #649)', () {
      final library = _buildMidrashLibrary();

      final ordered = SearchCatalogueOrderHelper.buildOrderedKeys<String>(
        library,
        keyOf: (book) => book.title as String,
      );

      expect(ordered, [
        'ספרא',
        'ספרי במדבר',
        'ראבד על ספרא',
        'בראשית רבה',
        'שמות רבה',
        'מתנות כהונה',
      ]);
    });

    test('סדר הקטלוג במנוע עולה מהמדרש למפרשיו (issue #649)', () async {
      final library = _buildMidrashLibrary();
      final order = {
        for (final entry in await IndexingRepository.buildBookOrder(library))
          entry.filePath: entry.catalogueOrder,
      };
      int orderOf(String title) =>
          order[BookIdentity.indexedFilePath(
            library.getAllBooks().singleWhere((book) => book.title == title),
          )]!;

      expect(orderOf('ספרא'), lessThan(orderOf('ראבד על ספרא')));
      expect(orderOf('בראשית רבה'), lessThan(orderOf('מתנות כהונה')));
    });
  });
}

/// משחזר את מבנה קטגוריית "מדרש" בספרייה: בכל רמה יש ספרים לצד
/// תת-קטגוריית "מפרשים".
Library _buildMidrashLibrary() {
  final library = Library(categories: []);

  final midrash = Category(
    title: 'מדרש',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: library,
  );
  library.subCategories.add(midrash);

  final halacha = Category(
    title: 'הלכה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: midrash,
  );
  final aggada = Category(
    title: 'אגדה',
    description: '',
    shortDescription: '',
    order: 2,
    subCategories: [],
    books: [],
    parent: midrash,
  );
  midrash.subCategories.addAll([halacha, aggada]);

  halacha.books.addAll([
    TextBook(title: 'ספרא', order: 1, category: halacha),
    TextBook(title: 'ספרי במדבר', order: 2, category: halacha),
  ]);

  final halachaMefarshim = Category(
    title: 'מפרשים',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: halacha,
  );
  halacha.subCategories.add(halachaMefarshim);
  halachaMefarshim.books.add(
    TextBook(title: 'ראבד על ספרא', order: 1, category: halachaMefarshim),
  );

  final rabba = Category(
    title: 'מדרש רבה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: aggada,
  );
  aggada.subCategories.add(rabba);
  rabba.books.addAll([
    TextBook(title: 'בראשית רבה', order: 1, category: rabba),
    TextBook(title: 'שמות רבה', order: 2, category: rabba),
  ]);

  final rabbaMefarshim = Category(
    title: 'מפרשים',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: rabba,
  );
  rabba.subCategories.add(rabbaMefarshim);
  rabbaMefarshim.books.add(
    TextBook(title: 'מתנות כהונה', order: 1, category: rabbaMefarshim),
  );

  return library;
}

Library _buildLibrary() {
  final library = Library(categories: []);
  final tanakh = Category(
    title: 'תנ"ך',
    description: '',
    shortDescription: '',
    order: 999,
    subCategories: [],
    books: [],
    parent: library,
  );
  final bavli = Category(
    title: 'תלמוד בבלי',
    description: '',
    shortDescription: '',
    order: 999,
    subCategories: [],
    books: [],
    parent: library,
  );
  final halacha = Category(
    title: 'הלכה',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: library,
  );
  library.subCategories.addAll([halacha, bavli, tanakh]);

  tanakh.books.add(
    TextBook(title: 'בראשית', order: 1, category: tanakh),
  );

  final moed = Category(
    title: 'סדר מועד',
    description: '',
    shortDescription: '',
    order: 5,
    subCategories: [],
    books: [],
    parent: bavli,
  );
  bavli.subCategories.add(moed);

  moed.books.addAll([
    TextBook(title: 'שבת', order: 1, category: moed),
    TextBook(title: 'חגיגה', order: 11, category: moed),
  ]);

  halacha.books.add(
    TextBook(title: 'משנה תורה, הלכות שבת', order: 1, category: halacha),
  );

  return library;
}
