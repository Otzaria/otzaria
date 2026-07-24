import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/models/books.dart';

Category _category(
  String title, {
  int order = 999,
  List<Category> subCategories = const [],
  List<Book> books = const [],
}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: order,
    subCategories: List.of(subCategories),
    books: List.of(books),
    parent: null,
  );
  for (final sub in category.subCategories) {
    sub.parent = category;
  }
  return category;
}

Library _library(List<Category> categories) {
  final library = Library(categories: categories);
  for (final sub in library.subCategories) {
    sub.parent = library;
  }
  return library;
}

TextBook _book(String title, {int order = 999}) =>
    TextBook(title: title, order: order);

/// סדר קטגוריות עליונות לפי מיקום ברשימה קבועה — מדמה את
/// _getTopCategoryOrder של המסך בלי תלות ב-State.
int Function(Category) _topOrderOf(List<String> orderedTitles) => (category) {
  final idx = orderedTitles.indexOf(category.title);
  return idx >= 0 ? idx : orderedTitles.length + category.order;
};

int _normalizeOrder(int order) => order >= 0 ? order : 1000 + order.abs();

List<FlatLibraryRow> _rows(
  Category root, {
  Set<String> expanded = const {},
  List<String> topOrder = const [],
  Set<String> talmudTextTitles = const {},
}) => buildFlatLibraryRows(
  category: root,
  expandedPaths: expanded,
  topCategoryOrder: _topOrderOf(topOrder),
  normalizeOrder: _normalizeOrder,
  talmudTextTitles: talmudTextTitles,
);

void main() {
  group('buildFlatLibraryRows — עץ הספרייה המשוטח', () {
    test('קטגוריות מכווצות: שורת כותרת אחת לכל קטגוריה, עם שני דגלי קצה', () {
      final root = _library([
        _category('הלכה', books: [_book('ספר א')]),
        _category('תנ"ך', books: [_book('ספר ב')]),
      ]);

      final rows = _rows(root, topOrder: ['תנ"ך', 'הלכה']);

      expect(rows, hasLength(2));
      expect(rows[0].kind, FlatLibraryRowKind.categoryHeader);
      expect(
        rows[0].category!.title,
        'תנ"ך',
        reason: 'סדר קטגוריות עליונות לפי הרשימה הקבועה, לא לפי order',
      );
      expect(rows[1].category!.title, 'הלכה');
      for (final row in rows) {
        expect(row.isGroupStart, isTrue);
        expect(
          row.isGroupEnd,
          isTrue,
          reason: 'כרטיס מכווץ = קבוצה בת שורה אחת',
        );
      }
    });

    test('קטגוריה ללא ספרים (גם בעומק) מסוננת החוצה', () {
      final root = _library([
        _category('ריקה', subCategories: [_category('תת ריקה')]),
        _category('מלאה', books: [_book('ספר')]),
      ]);

      final rows = _rows(root);

      expect(rows, hasLength(1));
      expect(rows.single.category!.title, 'מלאה');
    });

    test(
      'קטגוריה מורחבת: תת-קטגוריות לפני ספרים, ממוינים, ודגלי קצה נכונים',
      () {
        final expanded = _category(
          'הלכה',
          subCategories: [
            _category('שו"ת', order: 2, books: [_book('שות א')]),
            _category('פסק', order: 1, books: [_book('פסק א')]),
          ],
          books: [
            _book('ספר מאוחר', order: 5),
            _book('ספר מוקדם', order: 1),
          ],
        );
        final root = _library([expanded]);

        final rows = _rows(root, expanded: {expanded.path});

        expect(
          rows.map((r) => r.kind).toList(),
          [
            FlatLibraryRowKind.categoryHeader, // הלכה
            FlatLibraryRowKind.categoryHeader, // פסק (order 1)
            FlatLibraryRowKind.categoryHeader, // שו"ת (order 2)
            FlatLibraryRowKind.book, // ספר מוקדם
            FlatLibraryRowKind.book, // ספר מאוחר
          ],
        );
        expect(rows[1].category!.title, 'פסק');
        expect(rows[2].category!.title, 'שו"ת');
        expect(rows[3].book!.title, 'ספר מוקדם');
        expect(rows[4].book!.title, 'ספר מאוחר');

        expect(rows.first.isGroupStart, isTrue);
        expect(rows.first.isGroupEnd, isFalse);
        expect(
          rows.sublist(1, 4).every((r) => !r.isGroupStart && !r.isGroupEnd),
          isTrue,
        );
        expect(
          rows.last.isGroupEnd,
          isTrue,
          reason: 'השורה האחרונה בקבוצה עליונה סוגרת את הכרטיס',
        );
      },
    );

    test('רמות: ספר ברמה 0 הוא rootBook, ספר בקטגוריה הוא book', () {
      final sub = _category('תת', books: [_book('פנימי')]);
      final root = _library([
        _category('עליונה', subCategories: [sub], books: [_book('אמצעי')]),
      ]);
      root.books.add(_book('שורש'));

      final rows = _rows(root, expanded: {root.subCategories.first.path});

      final byTitle = {
        for (final row in rows)
          if (row.book != null) row.book!.title: row,
      };
      expect(byTitle['שורש']!.kind, FlatLibraryRowKind.rootBook);
      expect(byTitle['שורש']!.level, 0);
      expect(byTitle['אמצעי']!.kind, FlatLibraryRowKind.book);
      expect(byTitle['אמצעי']!.level, 1);
    });

    test('מעל מכסת הספרים: בדיוק 500 שורות ספר ואז שורת "הצג עוד"', () {
      final books = List.generate(502, (i) => _book('ספר $i', order: i));
      final big = _category('גדולה', books: books);
      final root = _library([big]);

      final rows = _rows(root, expanded: {big.path});

      final bookRows = rows
          .where((r) => r.kind == FlatLibraryRowKind.book)
          .toList();
      expect(bookRows, hasLength(500));
      expect(bookRows.first.book!.title, 'ספר 0');
      expect(bookRows.last.book!.title, 'ספר 499');

      final showMore = rows.last;
      expect(showMore.kind, FlatLibraryRowKind.showMore);
      expect(
        showMore.showMoreBooks,
        hasLength(502),
        reason: 'דיאלוג "הצג עוד" מקבל את הרשימה המלאה',
      );
      expect(
        showMore.isGroupEnd,
        isTrue,
        reason: '"הצג עוד" היא השורה הסוגרת של הכרטיס',
      );
    });

    test('מהדורות PDF כפולות של מסכתות הבבלי מסוננות מהעץ', () {
      final pdf = PdfBook(
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
      );
      final orphanPdf = PdfBook(
        title: 'שבת',
        path: r'C:\books\תלמוד בבלי\שבת.pdf',
      );
      final seder = _category('סדר זרעים', books: [_book('ברכות')]);
      final bavli = _category(
        'תלמוד בבלי',
        subCategories: [seder],
        books: [pdf, orphanPdf],
      );
      final root = _library([bavli]);

      final rows = _rows(
        root,
        expanded: {bavli.path, seder.path},
        talmudTextTitles: {'ברכות'},
      );

      final pdfRows = rows.where((r) => r.book is PdfBook).toList();
      expect(
        pdfRows.single.book!.title,
        'שבת',
        reason:
            'מסכת עם מהדורת טקסט מוצגת פעם אחת — דרך הטקסט; '
            'PDF ללא מהדורת טקסט נשאר מוצג',
      );
      expect(rows.where((r) => r.book is TextBook).single.book!.title, 'ברכות');
    });

    test('parentPath משקף את הקטגוריה המכילה (ייחודיות keys)', () {
      final subA = _category('תת', books: [_book('ספר')]);
      final subB = _category('תת אחרת', books: [_book('ספר')]);
      final catA = _category('א', subCategories: [subA]);
      final catB = _category('ב', subCategories: [subB]);
      final root = _library([catA, catB]);

      final rows = _rows(
        root,
        expanded: {catA.path, catB.path, subA.path, subB.path},
      );

      final bookRows = rows
          .where((r) => r.kind == FlatLibraryRowKind.book)
          .toList();
      expect(bookRows, hasLength(2));
      expect(bookRows[0].parentPath, isNot(bookRows[1].parentPath));
    });
  });
}
