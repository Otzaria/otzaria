import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';

Category _category(
  String title,
  List<Book> books, {
  List<Category> sub = const [],
}) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 0,
  subCategories: sub,
  books: books,
  parent: null,
);

void main() {
  group('parseCategoryQuery', () {
    test('ללא @ — מחזיר את השאילתה כמות שהיא ו-facets null', () {
      final library = Library(
        categories: [
          _category('תורה', [TextBook(title: 'בראשית')]),
        ],
      );

      final parsed = parseCategoryQuery('שלום עולם', library);

      expect(parsed.query, 'שלום עולם');
      expect(parsed.hasCategoryToken, isFalse);
      expect(parsed.facets, isNull);
    });

    test('@קטגוריה — מוצא את נתיב הקטגוריה', () {
      final library = Library(
        categories: [
          _category('תורה', [TextBook(title: 'בראשית')]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@תורה', library);

      expect(parsed.query, 'שלום');
      expect(parsed.hasCategoryToken, isTrue);
      expect(parsed.categoryFound, isTrue);
      expect(parsed.facets, contains('/תורה'));
    });

    test('@ספר — מוצא את ה-facet של הספר', () {
      final library = Library(
        categories: [
          _category('תורה', [TextBook(title: 'בראשית')]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@בראשית', library);

      expect(parsed.query, 'שלום');
      expect(parsed.categoryFound, isTrue);
      // ה-facet של ספר כולל את המפתח הייחודי של הספר בסוף הנתיב.
      expect(parsed.facets!.single, contains('בראשית'));
    });

    test('@שם שלא קיים — token קיים אך אין התאמה', () {
      final library = Library(
        categories: [
          _category('תורה', [TextBook(title: 'בראשית')]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@לא-קיים', library);

      expect(parsed.hasCategoryToken, isTrue);
      expect(parsed.categoryFound, isFalse);
      expect(parsed.facets, isEmpty);
    });

    test('כמה @ — מאחד את ה-facets של כל הספרים', () {
      final library = Library(
        categories: [
          _category('תורה', [
            TextBook(title: 'רשי'),
            TextBook(title: 'רמבן'),
          ]),
        ],
      );

      final parsed = parseCategoryQuery('ערבך ערבא@רמבן@רשי', library);

      expect(parsed.query, 'ערבך ערבא');
      expect(parsed.hasCategoryToken, isTrue);
      expect(parsed.categoryFound, isTrue);
      expect(parsed.facets!.length, 2);
    });

    test('כמה @ — שם אחד לא קיים מדווח ב-notFoundNames', () {
      final library = Library(
        categories: [
          _category('תורה', [TextBook(title: 'רשי')]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@רשי@לא-קיים', library);

      expect(parsed.hasCategoryToken, isTrue);
      expect(parsed.categoryFound, isFalse);
      expect(parsed.notFoundNames, ['לא-קיים']);
    });

    test('התאמה מדויקת גוברת על הכלה — לא נגררים ספרים שמכילים את השם', () {
      final library = Library(
        categories: [
          _category('תנך', [
            TextBook(title: 'בראשית'),
            TextBook(title: 'רשי על בראשית'),
          ]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@בראשית', library);

      expect(parsed.categoryFound, isTrue);
      expect(parsed.facets!.length, 1);
      expect(parsed.facets!.single, isNot(contains('רשי')));
    });

    test('שם חלקי — התאמת הכלה בכותרת', () {
      final library = Library(
        categories: [
          _category('הלכה', [
            TextBook(title: 'משנה ברורה'),
            TextBook(title: 'ביאור הלכה'),
          ]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@ברורה', library);

      expect(parsed.categoryFound, isTrue);
      expect(parsed.facets!.single, contains('משנה ברורה'));
    });

    test('שגיאת כתיב — התאמה סלחנית לפי מרחק עריכה', () {
      final library = Library(
        categories: [
          _category('הלכה', [TextBook(title: 'משנה ברורה')]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@משנה ברורא', library);

      expect(parsed.categoryFound, isTrue);
      expect(parsed.facets!.single, contains('משנה ברורה'));
    });

    test('@ ריק — מתעלם מהתחביר', () {
      final library = Library(categories: []);

      final parsed = parseCategoryQuery('שלום@', library);

      expect(parsed.query, 'שלום');
      expect(parsed.hasCategoryToken, isFalse);
    });
  });
}
