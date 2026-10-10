import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

void main() {
  Category makeCategory(
    String title, {
    List<Category> subCategories = const [],
    List<Book> books = const [],
  }) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: subCategories,
    books: books,
    parent: null,
  );

  /// מחבר את ההורים בעץ — [Category.path] נבנה מהשרשרת הזו.
  Library makeLibraryFrom(List<Category> topLevel) {
    final library = Library(categories: topLevel);
    void link(Category parent) {
      for (final sub in parent.subCategories) {
        sub.parent = parent;
        link(sub);
      }
    }

    for (final cat in topLevel) {
      cat.parent = library;
    }
    link(library);
    return library;
  }

  Library makeLibrary() => makeLibraryFrom([makeCategory('תנ"ך')]);

  /// ספר עם id — מפתח ה-facet שלו הוא `id:<id>`, ו-[categoryPath] קובע את
  /// הנתיב שרשימת הסינון השטוחה בונה ממנו את ה-facet.
  TextBook makeBook(int id, String title, String categoryPath) =>
      TextBook(id: id, title: title, categoryPath: categoryPath);

  Future<void> pumpTree(
    WidgetTester tester, {
    required Library library,
    Map<String, int> facetCounts = const {'/': 3, '/תנ"ך': 3},
    Set<String> selectedFacets = const {},
    Map<String, bool> expansion = const {},
    String filterQuery = '',
    bool isLoading = false,
    bool hasResults = true,
    void Function(String facet)? onSetFacet,
    void Function(String path, bool isExpanded)? onToggleExpand,
    VoidCallback? onClearAll,
    List<SearchTreeExtraCategory> extraRootCategories = const [],
    bool extraCategoriesFirst = false,
    SettingsLanguage language = SettingsLanguage.hebrew,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            SettingsTextScope(language: language, child: child!),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: SearchNavigationTree(
              library: library,
              facetCounts: facetCounts,
              selectedFacets: selectedFacets,
              expansion: expansion,
              filterQuery: filterQuery,
              isLoading: isLoading,
              hasResults: hasResults,
              onSetFacet: onSetFacet ?? (_) {},
              onToggleFacet: (_) {},
              onToggleExpand: onToggleExpand ?? (_, _) {},
              isMultiSelectPressed: () => false,
              onClearAll: onClearAll ?? () {},
              extraRootCategories: extraRootCategories,
              extraCategoriesFirst: extraCategoriesFirst,
            ),
          ),
        ),
      ),
    );
  }

  group('עץ הניווט — קטגוריות סינתטיות (ספק חיצוני)', () {
    SearchTreeExtraCategory extra({
      int count = 12,
      List<SearchTreeExtraBook> books = const [],
    }) => SearchTreeExtraCategory(
      title: 'עוד מהיברובוקס',
      facet: '/עוד מהיברובוקס',
      count: count,
      books: books,
    );

    const twoBooks = [
      SearchTreeExtraBook(
        title: 'שו"ת מהרש"ם',
        facet: '/עוד מהיברובוקס/#42',
        hits: 7,
      ),
      SearchTreeExtraBook(
        title: 'דרשות הר"ן',
        facet: '/עוד מהיברובוקס/#43',
        hits: 2,
      ),
    ];

    Finder chevron(String title) => find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(NavTreeTile),
      ),
      matching: find.byType(IconButton),
    );

    testWidgets('קטגוריה סינתטית מוצגת אחרי הקטגוריות ולחיצה בוחרת אותה', (
      tester,
    ) async {
      String? selected;
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra()],
        onSetFacet: (facet) => selected = facet,
      );

      expect(find.text('עוד מהיברובוקס'), findsOneWidget);
      expect(find.text('(12)'), findsOneWidget);
      // ברירת המחדל: הדלי אחרי קטגוריות הספרייה.
      expect(
        tester.getTopLeft(find.text('עוד מהיברובוקס')).dy,
        greaterThan(tester.getTopLeft(find.text('תנ"ך')).dy),
      );
      await tester.tap(find.text('עוד מהיברובוקס'));
      expect(selected, '/עוד מהיברובוקס');
    });

    testWidgets('extraCategoriesFirst מציב את הדלי לפני קטגוריות הספרייה', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra()],
        extraCategoriesFirst: true,
      );

      expect(
        tester.getTopLeft(find.text('עוד מהיברובוקס')).dy,
        lessThan(tester.getTopLeft(find.text('תנ"ך')).dy),
      );
    });

    testWidgets('קטגוריה סינתטית בספירה 0 מוסתרת אלא אם היא נבחרה', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(count: 0)],
      );
      expect(find.text('עוד מהיברובוקס'), findsNothing);

      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(count: 0)],
        selectedFacets: {'/עוד מהיברובוקס'},
      );
      expect(find.text('עוד מהיברובוקס'), findsOneWidget);
    });

    testWidgets('בלי ספרים מהספק אין חץ הרחבה', (tester) async {
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra()],
        expansion: const {'/עוד מהיברובוקס': true},
      );

      expect(chevron('עוד מהיברובוקס'), findsNothing);
    });

    testWidgets('פתיחה מציגה את ספרי הספק עם מספר המופעים בכל אחד', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(books: twoBooks)],
        expansion: const {'/עוד מהיברובוקס': true},
      );

      expect(find.text('שו"ת מהרש"ם'), findsOneWidget);
      expect(find.text('דרשות הר"ן'), findsOneWidget);
      expect(find.text('(7)'), findsOneWidget);
      expect(find.text('(2)'), findsOneWidget);
    });

    testWidgets('סגורה כברירת מחדל, והחץ מדווח על מצבה', (tester) async {
      final toggles = <(String, bool)>[];
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(books: twoBooks)],
        onToggleExpand: (path, isExpanded) => toggles.add((path, isExpanded)),
      );

      expect(find.text('שו"ת מהרש"ם'), findsNothing);
      await tester.tap(chevron('עוד מהיברובוקס'));
      await tester.pump();
      expect(toggles, [('/עוד מהיברובוקס', false)]);
    });

    testWidgets('לחיצה על ספר של הספק בוחרת את ה-facet שלו', (tester) async {
      String? selected;
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(books: twoBooks)],
        expansion: const {'/עוד מהיברובוקס': true},
        onSetFacet: (facet) => selected = facet,
      );

      await tester.tap(find.text('שו"ת מהרש"ם'));
      await tester.pump();
      expect(selected, '/עוד מהיברובוקס/#42');
    });

    testWidgets('ספר נבחר פותח את הדלי אוטומטית, וכיווץ ידני גובר', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(books: twoBooks)],
        selectedFacets: {'/עוד מהיברובוקס/#42'},
      );
      expect(find.text('שו"ת מהרש"ם'), findsOneWidget);

      await pumpTree(
        tester,
        library: makeLibrary(),
        extraRootCategories: [extra(books: twoBooks)],
        selectedFacets: {'/עוד מהיברובוקס/#42'},
        expansion: const {'/עוד מהיברובוקס': false},
      );
      expect(find.text('שו"ת מהרש"ם'), findsNothing);
    });
  });

  group('עץ הניווט — התנהגות בסיסית', () {
    testWidgets('ללא סינון: כותרת השורש היא "ספריית אוצריא" והקטגוריה מוצגת', (
      tester,
    ) async {
      await pumpTree(tester, library: makeLibrary());

      expect(find.text('ספריית אוצריא'), findsOneWidget);
      expect(find.text('תנ"ך'), findsOneWidget);
      expect(find.text('נקה סינון'), findsNothing);
    });

    testWidgets(
      'סינון ממד: כותרת השורש מציגה את שם הממד במקום "ספריית אוצריא"',
      (tester) async {
        await pumpTree(
          tester,
          library: makeLibrary(),
          selectedFacets: {'/era/ראשונים'},
        );

        expect(find.text('ראשונים'), findsOneWidget);
        expect(find.text('ספריית אוצריא'), findsNothing);
        expect(find.text('נקה סינון'), findsOneWidget);
      },
    );

    testWidgets('לחיצה על "נקה סינון" בשורש מפעילה onClearAll', (tester) async {
      var cleared = false;
      await pumpTree(
        tester,
        library: makeLibrary(),
        selectedFacets: {'/era/ראשונים'},
        onClearAll: () => cleared = true,
      );

      await tester.tap(find.text('נקה סינון'));
      await tester.pump();
      expect(cleared, isTrue);
    });

    testWidgets('לחיצה על קטגוריה מפעילה onSetFacet עם הנתיב שלה', (
      tester,
    ) async {
      String? facet;
      await pumpTree(
        tester,
        library: makeLibrary(),
        onSetFacet: (f) => facet = f,
      );

      await tester.tap(find.text('תנ"ך'));
      await tester.pump();
      expect(facet, '/תנ"ך');
    });

    testWidgets('קטגוריה ללא תוצאות אינה מוצגת', (tester) async {
      await pumpTree(
        tester,
        library: makeLibraryFrom([makeCategory('תנ"ך'), makeCategory('משנה')]),
        facetCounts: const {'/': 3, '/תנ"ך': 3},
      );

      expect(find.text('תנ"ך'), findsOneWidget);
      expect(find.text('משנה'), findsNothing);
    });
  });

  group('רשימת הסינון השטוחה — רק ספרים עם תוצאות', () {
    Library libraryWithBooks() => makeLibraryFrom([
      makeCategory(
        'תנ"ך',
        books: [
          makeBook(1, 'ויקרא', '/תנ"ך'),
          makeBook(2, 'רש"י על ויקרא', '/תנ"ך'),
          makeBook(3, 'תהילים', '/תנ"ך'),
        ],
      ),
    ]);

    testWidgets('ספר תואם ללא תוצאות אינו מוצג ברשימה', (tester) async {
      await pumpTree(
        tester,
        library: libraryWithBooks(),
        // רק לרש"י על ויקרא יש תוצאות; ל"ויקרא" עצמו אין.
        facetCounts: const {'/': 4, '/תנ"ך': 4, '/תנ"ך/id:2': 4},
        filterQuery: 'ויקרא',
      );

      expect(find.text('רש"י על ויקרא'), findsOneWidget);
      expect(find.text('ויקרא'), findsNothing);
      expect(find.text('תהילים'), findsNothing);
    });

    testWidgets(
      'כשלאף ספר תואם אין תוצאות מוצגת ההודעה "לא נמצאו ספרים עם תוצאות"',
      (tester) async {
        await pumpTree(
          tester,
          library: libraryWithBooks(),
          facetCounts: const {'/': 4, '/תנ"ך': 4, '/תנ"ך/id:3': 4},
          filterQuery: 'ויקרא',
        );

        expect(find.text('לא נמצאו ספרים עם תוצאות'), findsOneWidget);
        expect(find.byType(NavTreeTile), findsNothing);
      },
    );

    testWidgets('אין התאמת שם כלל — אותה הודעה', (tester) async {
      await pumpTree(
        tester,
        library: libraryWithBooks(),
        facetCounts: const {'/': 4, '/תנ"ך': 4, '/תנ"ך/id:1': 4},
        filterQuery: 'זוהר',
      );

      expect(find.text('לא נמצאו ספרים עם תוצאות'), findsOneWidget);
    });

    testWidgets('לחיצה על ספר ברשימה מפעילה onSetFacet עם facet הספר', (
      tester,
    ) async {
      String? facet;
      await pumpTree(
        tester,
        library: libraryWithBooks(),
        facetCounts: const {'/': 4, '/תנ"ך': 4, '/תנ"ך/id:1': 4},
        filterQuery: 'ויקרא',
        onSetFacet: (f) => facet = f,
      );

      await tester.tap(find.text('ויקרא'));
      await tester.pump();
      expect(facet, '/תנ"ך/id:1');
    });

    testWidgets('גרשיים בשאילתה מוצאים כותרת עם ״ (issue #2031)', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: makeLibraryFrom([
          makeCategory(
            'תנ"ך',
            books: [
              makeBook(1, 'רשב״א על ברכות', '/תנ"ך'),
              makeBook(2, 'רשב"א על בבא קמא', '/תנ"ך'),
            ],
          ),
        ]),
        facetCounts: const {
          '/': 4,
          '/תנ"ך': 4,
          '/תנ"ך/id:1': 2,
          '/תנ"ך/id:2': 2,
        },
        filterQuery: 'רשב"א',
      );

      expect(find.text('רשב״א על ברכות'), findsOneWidget);
      expect(find.text('רשב"א על בבא קמא'), findsOneWidget);
    });

    testWidgets('בטעינה ראשונית ללא תוצאות מוצג ספינר ולא ההודעה', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: libraryWithBooks(),
        facetCounts: const {},
        filterQuery: 'ויקרא',
        isLoading: true,
        hasResults: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('לא נמצאו ספרים עם תוצאות'), findsNothing);
    });

    testWidgets('הסינון זהה לנרמול הכותרת בכל הקשה (perf)', (tester) async {
      const alphabet = [
        'א',
        'ב',
        'ש',
        '"',
        '״',
        "'",
        '׳',
        '<',
        '>',
        ' ',
        '	',
        'A',
        'a',
      ];
      final random = Random(5);
      String randomText(int maxLength) => [
        for (var i = random.nextInt(maxLength) + 1; i > 0; i--)
          alphabet[random.nextInt(alphabet.length)],
      ].join();
      final books = [
        for (var id = 1; id <= 150; id++) makeBook(id, randomText(8), '/תנ"ך'),
      ];
      final library = makeLibraryFrom([makeCategory('תנ"ך', books: books)]);
      final counts = <String, int>{
        for (final book in books)
          FacetHelper.buildBookFacet(
            FacetHelper.resolveCategoryPath(book),
            book,
          ): book.id! % 5,
      };
      String oracle(String text) => normalizeBookTitle(text).toLowerCase();

      for (var i = 0; i < 80; i++) {
        final query = randomText(3) + alphabet[random.nextInt(3)];
        final expected = [
          for (final book in books)
            if (book.id! % 5 != 0 && oracle(book.title).contains(oracle(query)))
              book.title,
        ]..sort();
        // פעמיים: הראשונה ממלאת את המטמון והשנייה קוראת ממנו.
        for (var pass = 0; pass < 2; pass++) {
          await tester.pumpWidget(
            MaterialApp(
              // גובה שבו כל הספרים המסוננים נבנים, ולא רק הנראים במסך.
              home: OverflowBox(
                maxHeight: 100000,
                alignment: Alignment.topCenter,
                child: SearchNavigationTree(
                  library: library,
                  facetCounts: counts,
                  selectedFacets: const {},
                  expansion: const {},
                  filterQuery: query,
                  isLoading: false,
                  hasResults: true,
                  onSetFacet: (_) {},
                  onToggleFacet: (_) {},
                  onToggleExpand: (_, _) {},
                  isMultiSelectPressed: () => false,
                  onClearAll: () {},
                ),
              ),
            ),
          );
          final shown = [
            for (final tile in tester.widgetList<NavTreeTile>(
              find.byType(NavTreeTile),
            ))
              tile.title,
          ]..sort();
          expect(shown, expected, reason: 'query "$query" pass $pass');
        }
      }
    });
  });

  group('הסינון הפעיל חייב להישאר גלוי בעץ', () {
    Library nestedLibrary() => makeLibraryFrom([
      makeCategory(
        'תנ"ך',
        subCategories: [
          makeCategory(
            'כתובים',
            books: [makeBook(7, 'תהילים', '/תנ"ך/כתובים')],
          ),
        ],
      ),
      makeCategory('משנה'),
    ]);

    const nestedCounts = {
      '/': 5,
      '/תנ"ך': 5,
      '/תנ"ך/כתובים': 5,
      '/תנ"ך/כתובים/id:7': 5,
      '/משנה': 2,
    };

    testWidgets('ללא בחירה הענפים סגורים — הספר הפנימי אינו מוצג', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
      );

      expect(find.text('תנ"ך'), findsOneWidget);
      expect(find.text('כתובים'), findsNothing);
      expect(find.text('תהילים'), findsNothing);
    });

    testWidgets('בחירת ספר פותחת אוטומטית את ענף האבות עד אליו', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
        selectedFacets: {'/תנ"ך/כתובים/id:7'},
      );

      expect(find.text('תנ"ך'), findsOneWidget);
      expect(find.text('כתובים'), findsOneWidget);
      expect(find.text('תהילים'), findsOneWidget);
      // ענף שאינו בדרך אל הבחירה נשאר סגור.
      expect(find.text('משנה'), findsOneWidget);
    });

    testWidgets('כיווץ ידני גובר על הפתיחה האוטומטית', (tester) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
        selectedFacets: {'/תנ"ך/כתובים/id:7'},
        expansion: const {'/תנ"ך': false},
      );

      expect(find.text('כתובים'), findsNothing);
      expect(find.text('תהילים'), findsNothing);
    });

    testWidgets(
      'לחיצה על החץ בענף שנפתח אוטומטית מדווחת isExpanded=true (ולכן מכווצת)',
      (tester) async {
        final toggles = <(String, bool)>[];
        await pumpTree(
          tester,
          library: nestedLibrary(),
          facetCounts: nestedCounts,
          selectedFacets: {'/תנ"ך/כתובים/id:7'},
          onToggleExpand: (path, isExpanded) => toggles.add((path, isExpanded)),
        );

        final chevron = find.descendant(
          of: find.ancestor(
            of: find.text('תנ"ך'),
            matching: find.byType(NavTreeTile),
          ),
          matching: find.byType(IconButton),
        );
        await tester.tap(chevron);
        await tester.pump();

        expect(toggles, [('/תנ"ך', true)]);
      },
    );

    testWidgets('החץ בענף סגור מדווח isExpanded=false', (tester) async {
      final toggles = <(String, bool)>[];
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
        onToggleExpand: (path, isExpanded) => toggles.add((path, isExpanded)),
      );

      final chevron = find.descendant(
        of: find.ancestor(
          of: find.text('תנ"ך'),
          matching: find.byType(NavTreeTile),
        ),
        matching: find.byType(IconButton),
      );
      await tester.tap(chevron);
      await tester.pump();

      // לתנ"ך ילד גלוי יחיד (כתובים) — הפתיחה ממשיכה אליו.
      expect(toggles, [('/תנ"ך', false), ('/תנ"ך/כתובים', false)]);
    });

    testWidgets('פתיחה בשרשרת נעצרת ברמה שבה התוצאות מתפצלות', (tester) async {
      final toggles = <(String, bool)>[];
      await pumpTree(
        tester,
        library: makeLibraryFrom([
          makeCategory(
            'תנ"ך',
            subCategories: [
              makeCategory(
                'כתובים',
                subCategories: [
                  makeCategory(
                    'חמש מגילות',
                    books: [makeBook(8, 'רות', '/תנ"ך/כתובים/חמש מגילות')],
                  ),
                ],
                books: [makeBook(7, 'תהילים', '/תנ"ך/כתובים')],
              ),
            ],
          ),
        ]),
        facetCounts: const {
          '/': 5,
          '/תנ"ך': 5,
          '/תנ"ך/כתובים': 5,
          '/תנ"ך/כתובים/id:7': 3,
          '/תנ"ך/כתובים/חמש מגילות': 2,
          '/תנ"ך/כתובים/חמש מגילות/id:8': 2,
        },
        onToggleExpand: (path, isExpanded) => toggles.add((path, isExpanded)),
      );

      final chevron = find.descendant(
        of: find.ancestor(
          of: find.text('תנ"ך'),
          matching: find.byType(NavTreeTile),
        ),
        matching: find.byType(IconButton),
      );
      await tester.tap(chevron);
      await tester.pump();

      // בכתובים יש גם ספר וגם תת-קטגוריה — לא ממשיכים ל"חמש מגילות".
      expect(toggles, [('/תנ"ך', false), ('/תנ"ך/כתובים', false)]);
    });

    testWidgets('ספר נבחר שספירתו 0 עדיין מוצג יחד עם ענף האבות שלו', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        // הבחירה כבר לא מחזירה תוצאות — ובכל זאת חייבת להיראות בעץ.
        facetCounts: const {'/': 2, '/משנה': 2},
        selectedFacets: {'/תנ"ך/כתובים/id:7'},
      );

      expect(find.text('תנ"ך'), findsOneWidget);
      expect(find.text('כתובים'), findsOneWidget);
      expect(find.text('תהילים'), findsOneWidget);
    });

    testWidgets('קטגוריה נבחרת שספירתה 0 עדיין מוצגת', (tester) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: const {'/': 2, '/משנה': 2},
        selectedFacets: {'/תנ"ך'},
      );

      expect(find.text('תנ"ך'), findsOneWidget);
    });

    testWidgets('בחירת ספר מציגה "נקה סינון" בכותרת השורש', (tester) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
        selectedFacets: {'/תנ"ך/כתובים/id:7'},
      );

      expect(find.text('נקה סינון'), findsOneWidget);
    });

    testWidgets('כשאין ענף פתוח אין כפתור "כווץ הכל"', (tester) async {
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
      );

      expect(find.byTooltip('כווץ הכל'), findsNothing);
    });

    for (final (language, tooltip) in [
      (SettingsLanguage.hebrew, 'כווץ הכל'),
      (SettingsLanguage.english, 'Collapse all'),
    ]) {
      testWidgets('תיאור כפתור הכיווץ בשפת הממשק: ${language.code}', (
        tester,
      ) async {
        await pumpTree(
          tester,
          library: nestedLibrary(),
          facetCounts: nestedCounts,
          expansion: const {'/תנ"ך': true},
          language: language,
        );

        expect(find.byTooltip(tooltip), findsOneWidget);
      });
    }

    testWidgets('"כווץ הכל" סוגר גם ענפים שנפתחו אוטומטית וגם מוסתרים', (
      tester,
    ) async {
      final toggles = <(String, bool)>[];
      await pumpTree(
        tester,
        library: nestedLibrary(),
        facetCounts: nestedCounts,
        selectedFacets: {'/תנ"ך/כתובים/id:7'},
        expansion: const {'/משנה': true},
        onToggleExpand: (path, isExpanded) => toggles.add((path, isExpanded)),
      );

      await tester.tap(find.byTooltip('כווץ הכל'));
      await tester.pump();

      expect(toggles.toSet(), {
        ('/תנ"ך', true),
        ('/תנ"ך/כתובים', true),
        ('/משנה', true),
      });
    });
  });

  group('קטגוריה עם ספירה חיצונית בלבד — בלי חץ הרחבה', () {
    // ספירת היברובוקס יכולה לשבת על קטגוריה שאין תחתיה שום שורה נראית
    // (הענף העמוק לא בקטלוג, או שהספר אינו ספר ספרייה). חץ שנפתח לריק
    // מבלבל — לכן הוא מוצג רק כשיש ילד נראה; הלחיצה על השורה מסננת.
    Library twoBranchLibrary() => makeLibraryFrom([
      makeCategory(
        'תלמוד ירושלמי',
        subCategories: [makeCategory('סדר זרעים')],
      ),
      makeCategory(
        'תנ"ך',
        subCategories: [makeCategory('כתובים')],
      ),
    ]);

    Finder chevronOf(String title) => find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(NavTreeTile),
      ),
      matching: find.byType(IconButton),
    );

    testWidgets('ספירה על הקטגוריה בלבד — אין חץ; עם ילד בעל ספירה — יש', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: twoBranchLibrary(),
        facetCounts: const {
          '/': 3,
          // רק האב קיבל ספירה (הזרקת ספק חיצוני) — תת-הקטגוריה בספירה 0.
          '/תלמוד ירושלמי': 1,
          // ענף רגיל: גם הילד נספר.
          '/תנ"ך': 2,
          '/תנ"ך/כתובים': 2,
        },
      );

      expect(chevronOf('תלמוד ירושלמי'), findsNothing);
      expect(chevronOf('תנ"ך'), findsOneWidget);
    });

    testWidgets('קטגוריה בלי חץ אינה נפתחת גם כשהיא מסומנת כפתוחה', (
      tester,
    ) async {
      await pumpTree(
        tester,
        library: twoBranchLibrary(),
        facetCounts: const {'/': 1, '/תלמוד ירושלמי': 1},
        expansion: const {'/תלמוד ירושלמי': true},
      );

      expect(find.text('סדר זרעים'), findsNothing);
    });
  });
}
