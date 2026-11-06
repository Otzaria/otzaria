import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
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

class _CountingBook extends TextBook {
  _CountingBook() : super(title: 'ספר אחר', id: 1);

  int titleReads = 0;

  @override
  String get title {
    titleReads++;
    return super.title;
  }
}

class _CountingCategory extends Category {
  _CountingCategory()
    : super(
        title: 'קטגוריה',
        description: '',
        shortDescription: '',
        order: 0,
        subCategories: [],
        books: [],
        parent: null,
      );

  int pathReads = 0;

  @override
  String get path {
    pathReads++;
    return super.path;
  }
}

void main() {
  group('parseCategoryQuery', () {
    setUp(AcronymsCache.instance.clear);
    tearDown(AcronymsCache.instance.clear);

    String facetOf(Book book) =>
        FacetHelper.buildBookFacet(FacetHelper.resolveCategoryPath(book), book);

    for (final pair in [('שורש', 'שרש'), ('דובר', 'דבר')]) {
      test('@${pair.$1} אינו מרחיב את התחום לפי כלל כתיב שמות הספרים', () {
        final library = Library(categories: [_category(pair.$2, [])]);
        final parsed = parseCategoryQuery('מילה@${pair.$1}', library);
        expect(parsed.categoryFound, isFalse);
        expect(parsed.facets, isEmpty);
      });
    }

    test('@ מעדיף קטגוריה מילולית על מילה אחרת בכתיב קרוב', () {
      final library = Library(
        categories: [_category('דבר', []), _category('דובר', [])],
      );
      final parsed = parseCategoryQuery('מילה@דובר', library);
      expect(parsed.facets, hasLength(1));
      expect(parsed.facets!.single, contains('דובר'));
    });

    test('@ שומר התאמת שגיאת הקלדה גם בלי כלל כתיב שמות הספרים', () {
      final library = Library(categories: [_category('בראשית', [])]);
      final parsed = parseCategoryQuery('מילה@בראשיתת', library);
      expect(parsed.categoryFound, isTrue);
      expect(parsed.facets, contains(contains('בראשית')));
    });

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
          _category('תורה', [TextBook(title: 'רשי'), TextBook(title: 'רמבן')]),
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
          _category('פירושי משנה ברורה', [TextBook(title: 'הערות', id: 4)]),
        ],
      );

      final parsed = parseCategoryQuery('שלום@משנה ברורה', library);

      expect(parsed.facets, [
        FacetHelper.buildBookFacet(
          FacetHelper.resolveCategoryPath(exactBook),
          exactBook,
        ),
        category.path,
      ]);
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

    test('שם ללא נתיב לא בונה facet לספרים שאינם תואמים', () {
      final category = _CountingCategory();
      final book = TextBook(title: 'ספר אחר', id: 1, category: category);
      category.books.add(book);
      final library = Library(categories: [category]);

      final parsed = parseCategoryQuery('מילה@לאקייםבכלל', library);

      expect(parsed.categoryFound, isFalse);
      expect(category.pathReads, 0);
    });

    test('fallback אינו קורא ומנרמל שוב כותרות שכבר נסרקו', () {
      final book = _CountingBook();
      final library = Library(
        categories: [
          _category('תורה', [book]),
        ],
      );

      for (final name in ['בראשיט', 'זכ']) {
        book.titleReads = 0;
        final parsed = parseCategoryQuery('מילה@$name', library);

        expect(parsed.categoryFound, isFalse);
        expect(book.titleReads, 1, reason: name);
      }
    });

    for (final exactFirst in [true, false]) {
      test(
        'ספר מדויק ${exactFirst ? "ראשון" : "אחרון"} אינו בונה facet מקורב',
        () {
          final fuzzyCategory = _CountingCategory();
          fuzzyCategory.books.add(
            TextBook(title: 'בראשיט', id: 1, category: fuzzyCategory),
          );
          final exactBook = TextBook(title: 'בראשית', id: 2);
          final exactCategory = _category('תורה', [exactBook]);
          final library = Library(
            categories: exactFirst
                ? [exactCategory, fuzzyCategory]
                : [fuzzyCategory, exactCategory],
          );

          for (final name in ['בראשית', 'בְּרֵאשִׁית']) {
            expect(parseCategoryQuery('מילה@$name', library).facets, [
              facetOf(exactBook),
            ]);
          }
          expect(fuzzyCategory.pathReads, 0);
        },
      );
    }

    test('מילה שלמה שומרת ספרים לפני קטגוריה מדויקת בלי ספר מדויק', () {
      final books = [
        TextBook(title: 'פירוש בראשית', id: 1),
        TextBook(title: 'אוצרבראשית', id: 2),
        TextBook(title: 'בראשיט', id: 3),
        TextBook(title: 'מבוא לבראשית', id: 4),
      ];
      final exactCategory = _category('בראשית', []);
      final library = Library(
        categories: [exactCategory, _category('תורה', books)],
      );

      expect(parseCategoryQuery('מילה@בראשית', library).facets, [
        facetOf(books[0]),
        facetOf(books[3]),
        exactCategory.path,
      ]);
    });

    test('הכלה גוברת על שגיאת כתיב ושומרת סדר ספרים וקטגוריות', () {
      final books = [
        TextBook(title: 'בראשיט', id: 1),
        TextBook(title: 'אוצרבראשית', id: 2),
        TextBook(title: 'קיצורבראשית', id: 3),
      ];
      final matchingCategory = _category('פירושיבראשית', []);
      final library = Library(
        categories: [matchingCategory, _category('תורה', books)],
      );

      expect(parseCategoryQuery('מילה@בראשית', library).facets, [
        facetOf(books[1]),
        facetOf(books[2]),
        matchingCategory.path,
      ]);
    });

    test('ללא התאמה מילולית מוחזרות ההתאמות המקורבות בסדר המקורי', () {
      final books = [
        TextBook(title: 'בראשית', id: 1),
        TextBook(title: 'בראשיט', id: 2),
      ];
      final category = _category('בראשיח', books);
      final library = Library(categories: [category]);

      expect(parseCategoryQuery('מילה@בראשיז', library).facets, [
        ...books.map(facetOf),
        category.path,
      ]);
    });

    test('כינוי מדויק נשאר מתחת לכותרת מדויקת ואינו זולג למקור אחר', () {
      AcronymsCache.instance.setAcronymsForTesting({
        1: ['רש״י'],
      });
      final aliasBook = TextBook(title: 'פירוש התורה', id: 1);
      final exactBook = TextBook(title: 'רש״י', id: 2);
      final otherSources = [
        TextBook(title: 'ספר אישי', id: 1, source: BookSource.user),
        TextBook(
          title: 'ספר מצורף',
          id: 1,
          source: BookSource.attached('other'),
        ),
      ];
      final books = [aliasBook, ...otherSources];
      final category = _category('תורה', books);
      final library = Library(categories: [category]);

      expect(parseCategoryQuery('מילה@רשי', library).facets, [
        facetOf(aliasBook),
      ]);
      category.books.add(exactBook);
      expect(parseCategoryQuery('מילה@רשי', library).facets, [
        facetOf(exactBook),
      ]);
    });

    test('מילים מקורבות יכולות להתאים בנפרד לכותרת ולכינוי', () {
      AcronymsCache.instance.setAcronymsForTesting({
        1: ['בראשית'],
      });
      final book = TextBook(title: 'חידושים', id: 1);
      final library = Library(
        categories: [
          _category('תורה', [book]),
        ],
      );

      expect(parseCategoryQuery('מילה@חידושימ בראשיט', library).facets, [
        facetOf(book),
      ]);
    });

    test('כל שם @ בוחר בנפרד בין התאמה מילולית למקורבת', () {
      final exactBook = TextBook(title: 'בראשית', id: 1);
      final fuzzyBook = TextBook(title: 'משנה ברורה', id: 2);
      final library = Library(
        categories: [
          _category('ספרים', [exactBook, fuzzyBook]),
        ],
      );

      final parsed = parseCategoryQuery(
        'מילה@בראשית@משנה ברורא@לאקייםבכלל',
        library,
      );
      expect(parsed.facets, [facetOf(exactBook), facetOf(fuzzyBook)]);
      expect(parsed.notFoundNames, ['לאקייםבכלל']);
    });

    test('התאמה מדויקת מחוץ לנתיב אינה מונעת התאמה מקורבת בתוכו', () {
      final book = TextBook(title: 'משנה ברורה', id: 1, categoryPath: '/הלכה');
      final outside = TextBook(
        title: 'משנה ברורא',
        id: 2,
        categoryPath: '/אחר',
      );
      final library = Library(
        categories: [
          _category('הלכה', [book]),
          _category('אחר', [outside]),
        ],
      );

      for (final path in ['הלכה/משנה ברורא', 'משנה ברורא/הלכה']) {
        expect(parseCategoryQuery('מילה@$path', library).facets, [
          facetOf(book),
        ], reason: path);
      }
    });

    test('ללא ספרייה או עם שם מנורמל ריק אין התאמות', () {
      expect(parseCategoryQuery('מילה@בראשית', null).notFoundNames, ['בראשית']);
      expect(
        parseCategoryQuery('מילה@!!!', Library(categories: [])).facets,
        isEmpty,
      );
    });

    test('נתיב תואם ספר תחת קטגוריה ששמה מכיל פסיק', () {
      final category = _category('נתיבות המשפט, ביאורים', []);
      final book = TextBook(
        title: 'נתיבות המשפט, ביאורים',
        id: 3831,
        category: category,
      );
      category.books.add(book);
      final library = Library(categories: [category]);

      for (final name in ['נתיבות המשפט/ביאורים', 'ביאורים/נתיבות המשפט']) {
        final parsed = parseCategoryQuery('מילה@$name', library);

        expect(parsed.categoryFound, isTrue, reason: name);
        expect(parsed.facets, [
          FacetHelper.buildBookFacet(
            FacetHelper.resolveCategoryPath(book),
            book,
          ),
        ], reason: name);
      }
    });

    test('נתיב ממשיך דרך תת קטגוריה מתחת לשם שמכיל פסיק', () {
      final child = _category('סימנים', [TextBook(title: 'ביאור', id: 1)]);
      final parent = _category('נתיבות המשפט, ביאורים', [], sub: [child]);
      child.parent = parent;
      final library = Library(categories: [parent]);

      final parsed = parseCategoryQuery('מילה@נתיבות המשפט/סימנים', library);

      expect(parsed.categoryFound, isTrue);
      // כמו באינדקס: הפסיק בשם התיקייה הוא מפריד ב-facet.
      expect(parsed.facets, ['/נתיבות המשפט/ביאורים/סימנים']);
    });

    group('נתיב (issue #2842)', () {
      // שתי קטגוריות "רשב"א" — כמו בספרייה: תחת הבבלי ותחת השו"ת.
      const bavliRashbaPath = '/תלמוד בבלי/ראשונים/רשב״א';
      final beitza = TextBook(
        title: 'רשב״א על ביצה',
        id: 10,
        categoryPath: bavliRashbaPath,
      );
      final shabbat = TextBook(
        title: 'רשב״א על שבת',
        id: 11,
        categoryPath: bavliRashbaPath,
      );
      final shut = TextBook(
        title: 'שו"ת הרשב"א חלק ה',
        id: 12,
        categoryPath: '/שו״ת/ראשונים/רשב״א',
      );
      final rashiBeitza = TextBook(
        title: 'רש"י על ביצה',
        id: 13,
        categoryPath: '/תלמוד בבלי/רש"י',
      );
      final bavliRashba = _category('רשב״א', [beitza, shabbat]);
      final shutRashba = _category('רשב״א', [shut]);
      final bavli = _category(
        'תלמוד בבלי',
        [],
        sub: [
          _category('ראשונים', [], sub: [bavliRashba]),
          _category('רש"י', [rashiBeitza]),
        ],
      );
      final shutCategory = _category(
        'שו״ת',
        [],
        sub: [
          _category('ראשונים', [], sub: [shutRashba]),
        ],
      );
      final library = Library(categories: [bavli, shutCategory]);
      // ספק הספרייה מקשר כל תת-קטגוריה לאביה; כאן מקשרים ידנית.
      void linkParents(Category category) {
        for (final sub in category.subCategories) {
          sub.parent = category;
          linkParents(sub);
        }
      }

      linkParents(library);

      String facetOf(Book book) => FacetHelper.buildBookFacet(
        FacetHelper.resolveCategoryPath(book),
        book,
      );

      // שם מחזיר גם ספרים שבתוך הקטגוריה שהותאמה; מה שקובע הוא היקף הסינון.
      Matcher onlyUnder(List<String> scopes) => everyElement(
        predicate<String>(
          (facet) => scopes.any(
            (scope) => facet == scope || facet.startsWith('$scope/'),
          ),
          'under one of $scopes',
        ),
      );

      test('ללא נתיב — שתי הקטגוריות בשם זהה נכללות', () {
        final parsed = parseCategoryQuery('מוקצה@רשבא', library);

        expect(parsed.facets, containsAll([bavliRashba.path, shutRashba.path]));
      });

      test('הורה/שם — מבחין בין קטגוריות בשם זהה', () {
        final parsed = parseCategoryQuery('מוקצה@בבלי/רשבא', library);

        expect(parsed.query, 'מוקצה');
        expect(parsed.categoryFound, isTrue);
        expect(parsed.facets, contains(bavliRashba.path));
        expect(parsed.facets, onlyUnder([bavliRashba.path]));
      });

      test('שם/ספר — רק הספר שמתחת לשם, לא ספרים מקבילים במקום אחר', () {
        final parsed = parseCategoryQuery('מוקצה@רשבא/ביצה', library);

        expect(parsed.facets, [facetOf(beitza)]);
      });

      test('סדר הפוך — ספר/שם מתפרש כמו שם/ספר', () {
        final parsed = parseCategoryQuery('מוקצה@ביצה/רשבא', library);

        expect(parsed.facets, [facetOf(beitza)]);
      });

      test('רווחים סביב המפריד ומקטעים ריקים נבלעים', () {
        final parsed = parseCategoryQuery('מוקצה@ שו"ת / / רשבא ', library);

        expect(parsed.facets, contains(shutRashba.path));
        expect(parsed.facets, onlyUnder([shutRashba.path]));
        expect(parsed.categoryNames, ['שו"ת / / רשבא']);
      });

      test('נתיב ללא התאמה — מדווח בשמו המלא', () {
        final parsed = parseCategoryQuery('מוקצה@שו"ת/ביצה', library);

        expect(parsed.categoryFound, isFalse);
        expect(parsed.notFoundNames, ['שו"ת/ביצה']);
      });

      test('נתיב לצד @ נוסף — הצמצומים מתאחדים', () {
        final parsed = parseCategoryQuery('מוקצה@רשבא/ביצה@רש"י', library);

        final rashiPath = rashiBeitza.categoryPath!;
        expect(parsed.facets, containsAll([facetOf(beitza), rashiPath]));
        expect(parsed.facets, onlyUnder([facetOf(beitza), rashiPath]));
      });
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
