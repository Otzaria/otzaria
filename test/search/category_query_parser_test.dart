import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/utils/facet_helper.dart';

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

    test('ספר זהה שומר גם קטגוריה זהה בלי להרחיב להתאמות חלקיות', () {
      final exactBook = TextBook(title: 'משנה ברורה', id: 1);
      final category = _category('משנה ברורה', [
        TextBook(title: 'ביאור הלכה', id: 2),
      ]);
      final library = Library(
        categories: [
          category,
          _category('הלכה', [
            exactBook,
            TextBook(title: 'קיצור משנה ברורה', id: 3),
          ]),
          _category('פירושי משנה ברורה', [
            TextBook(title: 'הערות', id: 4),
          ]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@משנה ברורה', library);

      expect(
        parsed.facets,
        unorderedEquals([
          category.path,
          FacetHelper.buildBookFacet(
            FacetHelper.resolveCategoryPath(exactBook),
            exactBook,
          ),
        ]),
      );
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

    test('@שם מחבר — מחזיר כל ספר שהשם בכותרתו (issue #2030)', () {
      final books = [
        TextBook(title: 'חידושי רמב"ן על בבא מציעא', id: 2),
        TextBook(title: 'אגרת הרמב"ן', id: 3),
      ];
      final library = Library(
        categories: [
          _category('רמב״ן', [TextBook(title: 'רמב"ן על בראשית', id: 1)]),
          _category('ראשונים', books),
        ],
      );

      final parsed = parseCategoryQuery('מוחזק @רמב"ן', library);

      expect(
        parsed.facets,
        containsAll(
          books.map(
            (book) => FacetHelper.buildBookFacet(
              FacetHelper.resolveCategoryPath(book),
              book,
            ),
          ),
        ),
      );
    });

    test('@ ריק — מתעלם מהתחביר', () {
      final library = Library(categories: []);

      final parsed = parseCategoryQuery('שלום@', library);

      expect(parsed.query, 'שלום');
      expect(parsed.hasCategoryToken, isFalse);
    });
  });

  group('categoryQueryPart', () {
    test('ללא @ — מחזיר את הטקסט כמות שהוא', () {
      expect(categoryQueryPart('שלום עולם'), 'שלום עולם');
    });

    test('עם @ — מחזיר את החלק שלפניו ללא trim (שימור אופסטים)', () {
      expect(categoryQueryPart('שלום @תורה'), 'שלום ');
      expect(categoryQueryPart('שלום@רשי@רמבן'), 'שלום');
    });

    test('@ בתחילת הטקסט — מחזיר ריק', () {
      expect(categoryQueryPart('@תורה'), '');
    });
  });
}
