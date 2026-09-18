import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

Category _category(String title, {Category? parent}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(category);
  return category;
}

void main() {
  // מזהי seforim.db אינם ייחודיים מול user_books.db ומול ייצוגי PDF בעץ —
  // התאמת-id מקרית אסור שתסתיר את ספר הטקסט הרשמי או תוחזר במקומו.
  group('findOfficialTextBookById', () {
    test('מדלג על ספר אישי בעל אותו id ומחזיר את הרשמי', () {
      final root = _category('תלמוד בבלי');
      final personal = _category('ספרים אישיים');
      final userBook = TextBook(
        id: 7,
        title: 'ברכות שלי',
        source: BookSource.user,
      );
      final official = TextBook(id: 7, title: 'ברכות');
      personal.books.add(userBook);
      root.books.add(official);

      // הספר האישי ראשון בסדר המעבר — בלי הסינון הוא היה מוחזר.
      final library = Library(categories: [personal, root]);

      expect(findOfficialTextBookById(library, 7), same(official));
    });

    test('מדלג על PdfBook בעל אותו id ומחזיר את ספר הטקסט', () {
      final root = _category('תלמוד בבלי');
      final pdf = PdfBook(id: 7, title: 'ברכות', path: r'C:\ברכות.pdf');
      final text = TextBook(id: 7, title: 'ברכות');
      root.books.addAll([pdf, text]);

      final library = Library(categories: [root]);

      expect(findOfficialTextBookById(library, 7), same(text));
    });

    test('אין ספר רשמי מתאים — מחזיר null גם כשיש התנגשות id', () {
      final personal = _category('ספרים אישיים');
      personal.books.add(
        TextBook(id: 7, title: 'ברכות שלי', source: BookSource.user),
      );

      final library = Library(categories: [personal]);

      expect(findOfficialTextBookById(library, 7), isNull);
    });
  });

  // [LibraryBookIndex] מחליף סריקת-עץ לכל מפרש במעבר אחד. הוא חייב לבחור
  // בדיוק את אותו ספר שהסריקות בחרו — אחרת קליק על מפרש יפתח ספר אחר.
  group('LibraryBookIndex', () {
    test('מדלג על ספר אישי בעל אותו id ומחזיר את הרשמי', () {
      final personal = _category('ספרים אישיים');
      final root = _category('תלמוד בבלי');
      final userBook = TextBook(
        id: 7,
        title: 'ברכות שלי',
        source: BookSource.user,
      );
      final official = TextBook(id: 7, title: 'ברכות');
      personal.books.add(userBook);
      root.books.add(official);

      final library = Library(categories: [personal, root]);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('ברכות', bookId: 7),
        same(official),
      );
    });

    test('מדלג על PdfBook בעל אותו id ומחזיר את ספר הטקסט', () {
      final root = _category('תלמוד בבלי');
      final pdf = PdfBook(id: 7, title: 'ברכות', path: r'C:\ברכות.pdf');
      final text = TextBook(id: 7, title: 'ברכות');
      root.books.addAll([pdf, text]);

      final library = Library(categories: [root]);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('ברכות', bookId: 7),
        same(text),
      );
    });

    test('בלי id — נופל לכותרת ומעדיף ספר טקסט על PDF', () {
      final root = _category('תלמוד בבלי');
      final pdf = PdfBook(id: 1, title: 'רש"י', path: r'C:\rashi.pdf');
      final text = TextBook(id: 2, title: 'רש"י');
      // ה-PDF ראשון בסדר המעבר — ההעדפה לטקסט חייבת לגבור על הסדר.
      root.books.addAll([pdf, text]);

      final library = Library(categories: [root]);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('רש"י', bookId: null),
        same(text),
      );
    });

    test('כותרת שאין לה ספר טקסט — מוחזר הספר מכל סוג', () {
      final root = _category('תלמוד בבלי');
      final pdf = PdfBook(id: 1, title: 'תוספות', path: r'C:\tos.pdf');
      root.books.add(pdf);

      final library = Library(categories: [root]);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('תוספות', bookId: 9),
        same(pdf),
      );
    });

    test('id שאינו בעץ ואין כותרת תואמת — null', () {
      final root = _category('תלמוד בבלי');
      root.books.add(TextBook(id: 1, title: 'ברכות'));

      final library = Library(categories: [root]);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('שבת', bookId: 99),
        isNull,
      );
    });

    test('כותרות כפולות — נבחר הראשון בסדר המעבר, כמו הסריקה', () {
      final first = _category('ראשונים');
      final second = _category('אחרונים');
      final early = TextBook(id: 1, title: 'חידושים');
      final later = TextBook(id: 2, title: 'חידושים');
      first.books.add(early);
      second.books.add(later);

      final library = Library(categories: [first, second]);

      expect(
        LibraryBookIndex(
          library,
        ).resolveCommentatorBook('חידושים', bookId: null),
        same(early),
      );
    });

    test('שני ספרים רשמיים באותו id — נבחר הראשון בסדר המעבר', () {
      final first = _category('ראשונים');
      final second = _category('אחרונים');
      final early = TextBook(id: 5, title: 'חידושים א');
      first.books.add(early);
      second.books.add(TextBook(id: 5, title: 'חידושים ב'));

      final library = Library(categories: [first, second]);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('אין', bookId: 5),
        same(early),
      );
    });

    test('ספרי הקטגוריה נסרקים לפני תתי-הקטגוריות', () {
      // ספר אישי יושב ישירות על library.books ומצל על הרשמי לפי כותרת —
      // כמו ב-_appendUserBooksToLibrary. היפוך הסדר יפתח ספר אחר.
      final root = _category('תלמוד בבלי');
      root.books.add(TextBook(id: 1, title: 'ברכות'));
      final library = Library(categories: [root]);
      final personal = TextBook(id: 9, title: 'ברכות', source: BookSource.user);
      library.books.add(personal);

      expect(
        LibraryBookIndex(library).resolveCommentatorBook('ברכות', bookId: null),
        same(personal),
      );
    });

    test('מסכים עם הסריקה על כל מזהי העץ', () {
      final root = _category('תלמוד בבלי');
      final sub = _category('ראשונים', parent: root);
      final personal = _category('ספרים אישיים');
      root.books.addAll([
        TextBook(id: 1, title: 'ברכות'),
        PdfBook(id: 2, title: 'שבת', path: r'C:\shabat.pdf'),
      ]);
      sub.books.addAll([
        TextBook(id: 3, title: 'רש"י'),
        TextBook(id: 2, title: 'תוספות'),
      ]);
      personal.books.add(
        TextBook(id: 3, title: 'שלי', source: BookSource.user),
      );

      final library = Library(categories: [personal, root]);
      final index = LibraryBookIndex(library);

      for (var id = 0; id <= 5; id++) {
        expect(
          index.resolveCommentatorBook('אין כותרת כזו', bookId: id),
          same(findOfficialTextBookById(library, id)),
          reason: 'פתרון לפי id=$id חייב להיות זהה לסריקה',
        );
      }
    });
  });
}
