import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
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
  // הבחנה זו היא הבסיס לפתיחת מסכת בבלי כ-PDF ב-find_ref: ספר המקור מזוהה
  // בעץ לפי id ומועבר עם צומת הקטגוריה שלו, כדי ש-getCompanionBook לא יבחר
  // שרירותית בין שני ספרים בעלי אותה כותרת.
  group('Library.getCompanionBook — הבחנה בין ספרים בעלי שם זהה', () {
    test('מעדיף PDF באותה קטגוריה על פני PDF בעל שם זהה בקטגוריה אחרת', () {
      final bavliRoot = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavliRoot);
      final other = _category('אחר');

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final sameCategoryPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\a\ברכות.pdf',
        category: seder,
      );
      final otherCategoryPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\b\ברכות.pdf',
        category: other,
      );
      seder.books.addAll([sourceText, sameCategoryPdf]);
      other.books.add(otherCategoryPdf);

      final library = Library(categories: [bavliRoot, other]);

      expect(
        library.getCompanionBook(sourceText, PdfBook),
        same(sameCategoryPdf),
      );
    });

    test('שני מועמדים בעלי שם זהה באותה קטגוריה — מחזיר null ולא מנחש', () {
      final bavliRoot = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavliRoot);

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final pdfA = PdfBook(
        title: 'ברכות',
        path: r'C:\a\ברכות.pdf',
        category: seder,
      );
      final pdfB = PdfBook(
        title: 'ברכות',
        path: r'C:\b\ברכות.pdf',
        category: seder,
      );
      seder.books.addAll([sourceText, pdfA, pdfB]);

      final library = Library(categories: [bavliRoot]);

      expect(library.getCompanionBook(sourceText, PdfBook), isNull);
    });

    test('בחיפוש גלובלי — מסנן התנגשות בבלי/ירושלמי', () {
      final bavli = _category('תלמוד בבלי');
      final bavliSeder = _category('סדר זרעים', parent: bavli);
      final yerushalmi = _category('תלמוד ירושלמי');
      final yerushalmiSeder = _category('סדר זרעים', parent: yerushalmi);

      // ספר המקור בבלי; ה-PDF המקביל יושב בשורש הבבלי (קטגוריה שונה מהמקור),
      // ולכן ההתאמה עוברת לחיפוש הגלובלי — שם המסנן דוחה את ה-PDF הירושלמי.
      // הירושלמי נרשם ראשון בעץ כדי שהבחירה תסתמך על המסנן ולא על סדר המעבר.
      final sourceText = TextBook(
        title: 'ברכות',
        category: bavliSeder,
        categoryPath: 'תלמוד בבלי, סדר זרעים',
      );
      final bavliPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\תלמוד בבלי\ברכות.pdf',
        category: bavli,
      );
      final yerushalmiPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\תלמוד ירושלמי\ברכות.pdf',
        category: yerushalmiSeder,
      );
      bavliSeder.books.add(sourceText);
      bavli.books.add(bavliPdf);
      yerushalmiSeder.books.add(yerushalmiPdf);

      // ירושלמי לפני בבלי בסדר הרשימה — בלי המסנן, החיפוש הגלובלי היה מחזיר
      // אותו ראשון.
      final library = Library(categories: [yerushalmi, bavli]);

      expect(library.getCompanionBook(sourceText, PdfBook), same(bavliPdf));
    });
  });
}
