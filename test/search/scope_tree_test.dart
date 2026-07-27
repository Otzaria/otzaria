import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/scope_tree.dart';

/// בונה ספריית בדיקה: תנ״ך, משנה, ותחת "מדרש" יש "הלכה" ו"אגדה".
/// תחת "תנ״ך" יש שני ספרים ("בראשית", "שמות").
Library _buildLibrary() {
  Category mkCat(
    String title, {
    List<Category> children = const [],
    List<Book> books = const [],
  }) {
    final cat = Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 10,
      subCategories: List<Category>.from(children),
      books: List<Book>.from(books),
      parent: null,
    );
    for (final child in cat.subCategories) {
      child.parent = cat;
    }
    return cat;
  }

  final tanach = mkCat(
    'תנ״ך',
    books: [
      TextBook(title: 'בראשית'),
      TextBook(title: 'שמות'),
    ],
  );
  final mishna = mkCat('משנה');
  final halacha = mkCat('הלכה');
  final aggada = mkCat('אגדה');
  final midrash = mkCat('מדרש', children: [halacha, aggada]);

  final library = Library(categories: [tanach, mishna, midrash]);
  for (final cat in library.subCategories) {
    cat.parent = library;
  }
  return library;
}

Category _mkCat(
  String title, {
  List<Category> children = const [],
  List<Book> books = const [],
}) {
  final cat = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: List<Category>.from(children),
    books: List<Book>.from(books),
    parent: null,
  );
  for (final child in cat.subCategories) {
    child.parent = cat;
  }
  return cat;
}

Library _lib(List<Category> categories) {
  final library = Library(categories: categories);
  for (final cat in library.subCategories) {
    cat.parent = library;
  }
  return library;
}

void main() {
  late ScopeTree tree;

  setUp(() {
    tree = ScopeTree.fromLibrary(_buildLibrary());
  });

  group('ScopeTree — מצב בחירה', () {
    test('isAllSelected מזהה את "/"', () {
      expect(tree.isAllSelected({'/'}), isTrue);
      expect(tree.isAllSelected({'/תנ״ך'}), isFalse);
      expect(tree.isAllSelected(<String>{}), isFalse);
    });

    test('categoryCheckState: נבחר ישירות / אב נבחר / צאצא חלקי', () {
      expect(tree.categoryCheckState('/תנ״ך', {'/'}), isTrue);
      expect(tree.categoryCheckState('/תנ״ך', {'/תנ״ך'}), isTrue);
      expect(tree.categoryCheckState('/מדרש/הלכה', {'/מדרש'}), isTrue);
      // אב עם צאצא נבחר בלבד → מצב חלקי (null)
      expect(tree.categoryCheckState('/מדרש', {'/מדרש/הלכה'}), isNull);
      expect(tree.categoryCheckState('/משנה', {'/תנ״ך'}), isFalse);
    });

    test('isFacetCovered: נבחר ישירות או תחת אב נבחר', () {
      expect(tree.isFacetCovered('/מדרש/הלכה', {'/'}), isTrue);
      expect(tree.isFacetCovered('/מדרש/הלכה', {'/מדרש'}), isTrue);
      expect(tree.isFacetCovered('/מדרש/הלכה', {'/מדרש/אגדה'}), isFalse);
    });
  });

  group('ScopeTree — בחירה/ביטול', () {
    test('בחירת כל הקטגוריות העליונות מתמצה ל-"/"', () {
      var selection = <String>{};
      selection = tree.selectFacet('/תנ״ך', selection);
      selection = tree.selectFacet('/משנה', selection);
      selection = tree.selectFacet('/מדרש', selection);
      expect(selection, equals({'/'}));
    });

    test(
      'ביטול סימון תת-קטגוריה לא בוחר את הקטגוריות העליונות האחרות (רגרסיה)',
      () {
        // "מדרש" מסומן; ביטול "הלכה" משאיר רק "אגדה" — בלי לקפוץ לתנ״ך/משנה.
        final selection = tree.deselectFacet('/מדרש/הלכה', {'/מדרש'});
        expect(selection, equals({'/מדרש/אגדה'}));
        expect(selection.contains('/תנ״ך'), isFalse);
        expect(selection.contains('/משנה'), isFalse);
      },
    );

    test('ביטול קטגוריה שנבחרה ישירות מסיר אותה', () {
      final selection = tree.deselectFacet('/תנ״ך', {'/תנ״ך', '/משנה'});
      expect(selection, equals({'/משנה'}));
    });
  });

  group('ScopeTree — ספרים וחיפוש', () {
    test('allBookNodes מחזיר את כל צמתי הספרים', () {
      final books = tree.allBookNodes();
      final titles = books.map((b) => b.title).toSet();
      expect(titles, equals({'בראשית', 'שמות'}));
    });

    test('search מוצא קטגוריות וספרים לפי מחרוזת מנורמלת', () {
      final results = tree.search('בראשית');
      expect(results.any((r) => r.title == 'בראשית' && r.isBook), isTrue);

      final catResults = tree.search('מדרש');
      expect(catResults.any((r) => r.title == 'מדרש' && !r.isBook), isTrue);
    });

    test('search על מחרוזת ריקה מחזיר רשימה ריקה', () {
      expect(tree.search(''), isEmpty);
    });
  });

  group('ScopeTree — סדר תיקיות ראשיות (כמו מסך הספרייה)', () {
    test('rootNodes ממויין לפי topCategoryOrder ולא לפי סדר ההכנסה', () {
      // הכנסה בסדר משנה→תנ״ך→מדרש; הצפי לפי הסדר הקטלוגי: תנ״ך, מדרש, משנה.
      final t = ScopeTree.fromLibrary(
        _lib([_mkCat('משנה'), _mkCat('תנ״ך'), _mkCat('מדרש')]),
      );
      expect(
        t.rootNodes.map((n) => n.title).toList(),
        equals(['תנ״ך', 'מדרש', 'משנה']),
      );
    });
  });

  group('ScopeTree — ניווט אקורדיון וקיפול ילד-יחיד', () {
    late ScopeTree t;
    late String bookAFacet;

    setUp(() {
      // "יחיד" → "רק" → [ספר בודד]  (שרשרת ילד-יחיד שמסתיימת בספר)
      // "מרובה" → {"א"→[ספר א], "ב"→[ספר ב]}
      // "שרשרת" → "פנימי" → [x, y]  (שרשרת תת-תיקיה יחידה שמסתיימת ב-2 ספרים)
      final single = _mkCat(
        'יחיד',
        children: [
          _mkCat('רק', books: [TextBook(title: 'ספר בודד')]),
        ],
      );
      final many = _mkCat(
        'מרובה',
        children: [
          _mkCat('א', books: [TextBook(title: 'ספר א')]),
          _mkCat('ב', books: [TextBook(title: 'ספר ב')]),
        ],
      );
      final chain = _mkCat(
        'שרשרת',
        children: [
          _mkCat(
            'פנימי',
            books: [
              TextBook(title: 'x'),
              TextBook(title: 'y'),
            ],
          ),
        ],
      );
      t = ScopeTree.fromLibrary(_lib([single, many, chain]));
      bookAFacet = t.allBookNodes().firstWhere((b) => b.title == 'ספר א').facet;
    });

    ScopeNode top(String title) =>
        t.rootNodes.firstWhere((n) => n.title == title);

    test('singleBookOf מקפל שרשרת ילד-יחיד לספר בודד', () {
      final single = t.singleBookOf(top('יחיד'));
      expect(single, isNotNull);
      expect(single!.title, equals('ספר בודד'));
    });

    test('singleBookOf מחזיר null לתיקיה עם כמה ילדים', () {
      expect(t.singleBookOf(top('מרובה')), isNull);
      expect(t.singleBookOf(top('שרשרת')), isNull);
    });

    test('expandedChildren יורד בשרשרת תת-תיקיה-יחידה', () {
      final kids = t.expandedChildren(top('שרשרת'));
      expect(kids.map((n) => n.title).toList(), equals(['x', 'y']));
    });

    test('expandedChildren של תיקיה מרובה מחזיר את תתי-התיקיות', () {
      final kids = t.expandedChildren(top('מרובה'));
      expect(kids.map((n) => n.title).toList(), equals(['א', 'ב']));
    });

    test('visibleChildren מסנן לפי onlyBooks', () {
      final only = {bookAFacet};
      final roots = t.visibleChildren(null, onlyBooks: only);
      expect(roots.map((n) => n.title).toList(), equals(['מרובה']));

      final manyKids = t.visibleChildren(top('מרובה'), onlyBooks: only);
      expect(manyKids.map((n) => n.title).toList(), equals(['א']));
    });

    test('singleBookOf עם onlyBooks מקפל לפי הסינון', () {
      // תחת הסינון, ל"מרובה" יש רק את "א" עם "ספר א" → מתקפל לספר בודד.
      final single = t.singleBookOf(top('מרובה'), onlyBooks: {bookAFacet});
      expect(single?.title, equals('ספר א'));
    });
  });

  group('ScopeTree — מטמון לפי זהות הספרייה', () {
    test('קריאה חוזרת על אותה ספרייה מחזירה את אותו מופע', () {
      final library = _buildLibrary();
      final first = ScopeTree.fromLibrary(library);
      final second = ScopeTree.fromLibrary(library);
      expect(identical(first, second), isTrue);
    });

    test('ספרייה אחרת בונה עץ חדש עם התוכן שלה', () {
      final first = ScopeTree.fromLibrary(_buildLibrary());
      final other = ScopeTree.fromLibrary(
        _lib([
          _mkCat('הלכה', books: [TextBook(title: 'שולחן ערוך')]),
        ]),
      );
      expect(identical(first, other), isFalse);
      expect(other.rootNodes.map((n) => n.title).toList(), equals(['הלכה']));
      expect(
        other.allBookNodes().map((b) => b.title).toList(),
        equals(['שולחן ערוך']),
      );
    });

    test('החלפת ספרייה ובחזרה אליה בונה מחדש תוכן נכון', () {
      final libraryA = _buildLibrary();
      final libraryB = _lib([
        _mkCat('קבלה', books: [TextBook(title: 'ספר הזהר')]),
      ]);

      final firstA = ScopeTree.fromLibrary(libraryA);
      ScopeTree.fromLibrary(libraryB);
      final secondA = ScopeTree.fromLibrary(libraryA);

      expect(
        secondA.rootNodes.map((n) => n.title).toList(),
        equals(firstA.rootNodes.map((n) => n.title).toList()),
      );
      expect(
        secondA.allBookNodes().map((b) => b.facet).toSet(),
        equals(firstA.allBookNodes().map((b) => b.facet).toSet()),
      );
    });
  });

  group('BookScopeNode — facet וכתובית מנתיב הקטגוריה', () {
    /// עוטף ספר בקטגוריה עם הנתיב הנתון, כפי שבונה אותה ספק הספרייה.
    Library libWithBook(Book book, String categoryTitle) => _lib([
      _mkCat(categoryTitle, books: [book]),
    ]);

    test('facet של ספר נבנה תחת נתיב הקטגוריה שלו', () {
      final node = ScopeTree.fromLibrary(
        libWithBook(
          TextBook(title: 'בראשית', id: 7, categoryPath: '/תנ״ך/תורה'),
          'תורה',
        ),
      ).allBookNodes().single;
      expect(node.facet, equals('/תנ״ך/תורה/id:7'));
    });

    test('הכתובית מציגה את נתיב הקטגוריה ואת המחבר', () {
      final node = ScopeTree.fromLibrary(
        libWithBook(
          TextBook(
            title: 'משנה תורה',
            author: 'הרמב״ם',
            categoryPath: '/הלכה',
          ),
          'הלכה',
        ),
      ).allBookNodes().single;
      expect(node.subtitle, equals('הלכה • הרמב״ם'));
    });

    test('ספר בלי מחבר מציג את נתיב הקטגוריה בלבד', () {
      final node = ScopeTree.fromLibrary(
        libWithBook(
          TextBook(title: 'ילקוט שמעוני', categoryPath: '/מדרש/אגדה'),
          'אגדה',
        ),
      ).allBookNodes().single;
      expect(node.subtitle, equals('מדרש/אגדה'));
    });

    test('ספר בלי נתיב קטגוריה מציג את המחבר בלבד', () {
      final node = ScopeTree.fromLibrary(
        libWithBook(TextBook(title: 'ספר יתום', author: 'פלוני'), 'ריק'),
      ).allBookNodes().single;
      expect(node.subtitle, equals('פלוני'));
    });

    test('נתיב הקטגוריה נגזר מ-topics כשאין categoryPath', () {
      final node = ScopeTree.fromLibrary(
        libWithBook(
          TextBook(
            title: 'ברכות',
            topics: 'תלמוד בבלי, סדר זרעים',
            author: 'חז״ל',
          ),
          'סדר זרעים',
        ),
      ).allBookNodes().single;
      expect(node.subtitle, equals('תלמוד בבלי/סדר זרעים • חז״ל'));
      expect(node.facet, startsWith('/תלמוד בבלי/סדר זרעים/'));
    });
  });
}
