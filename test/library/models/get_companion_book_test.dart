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

  // תיקיית ספרים אישיים בעלת אותם שמות (למשל "תלמוד בבלי" שהורדה מתוסף
  // הורדת מאגר) הפכה את הבחירה לתלוית סדר העץ: המהדורה האישית נבחרה,
  // הסימניות שלה לא התאימו לתוכן העניינים, וה-PDF נפתח בעמוד הראשון.
  group('Library.getCompanionBook — מקור הספר', () {
    test('בחיפוש גלובלי — מעדיף מהדורה מובנית על ספר אישי בשם זהה', () {
      final bavli = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavli);
      final userRoot = _category('אישיים');
      final userBavli = _category('תלמוד בבלי', parent: userRoot);

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final builtInPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\otzaria\תלמוד בבלי\ברכות.pdf',
        category: bavli,
      );
      final userPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\תלמוד בבלי\ברכות.pdf',
        category: userBavli,
        isUserBook: true,
      );
      seder.books.add(sourceText);
      bavli.books.add(builtInPdf);
      userBavli.books.add(userPdf);

      // האישי ראשון בעץ — בלי העדפת המקור הוא היה נבחר.
      final library = Library(categories: [userRoot, bavli]);

      expect(library.getCompanionBook(sourceText, PdfBook), same(builtInPdf));
    });

    test('אין מהדורה מובנית — ספר אישי בעל שם זהה כן מוחזר', () {
      final bavli = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavli);
      final userRoot = _category('אישיים');

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final userPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\ברכות.pdf',
        category: userRoot,
        isUserBook: true,
      );
      seder.books.add(sourceText);
      userRoot.books.add(userPdf);

      final library = Library(categories: [bavli, userRoot]);

      expect(library.getCompanionBook(sourceText, PdfBook), same(userPdf));
    });

    test('ספר מקור אישי — מעדיף מלווה אישי על המובנה בקטגוריה אחרת', () {
      final bavli = _category('תלמוד בבלי');
      final userRoot = _category('אישיים');
      final userBavli = _category('תלמוד בבלי', parent: userRoot);

      final sourceText = TextBook(
        title: 'ברכות',
        category: userRoot,
        isUserBook: true,
      );
      final builtInPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\otzaria\תלמוד בבלי\ברכות.pdf',
        category: bavli,
      );
      final userPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\תלמוד בבלי\ברכות.pdf',
        category: userBavli,
        isUserBook: true,
      );
      userRoot.books.add(sourceText);
      bavli.books.add(builtInPdf);
      userBavli.books.add(userPdf);

      // המובנה ראשון בעץ — בלי העדפת המקור הוא היה נבחר.
      final library = Library(categories: [bavli, userRoot]);

      expect(library.getCompanionBook(sourceText, PdfBook), same(userPdf));
    });

    test('מועמד באותה קטגוריה קודם למועמד מאותו מקור בקטגוריה אחרת', () {
      final bavli = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavli);
      final other = _category('אחר');

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final userPdfSameCategory = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\ברכות.pdf',
        category: seder,
        isUserBook: true,
      );
      final builtInPdfElsewhere = PdfBook(
        title: 'ברכות',
        path: r'C:\otzaria\אחר\ברכות.pdf',
        category: other,
      );
      seder.books.addAll([sourceText, userPdfSameCategory]);
      other.books.add(builtInPdfElsewhere);

      final library = Library(categories: [bavli, other]);

      expect(
        library.getCompanionBook(sourceText, PdfBook),
        same(userPdfSameCategory),
      );
    });

    test('שני מועמדים אישיים באותה קטגוריה — מוותר ולא מנחש', () {
      final bavli = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavli);

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final userPdfA = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\א\ברכות.pdf',
        category: seder,
        isUserBook: true,
      );
      final userPdfB = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\ב\ברכות.pdf',
        category: seder,
        isUserBook: true,
      );
      seder.books.addAll([sourceText, userPdfA, userPdfB]);

      final library = Library(categories: [bavli]);

      expect(library.getCompanionBook(sourceText, PdfBook), isNull);
    });

    test('מובנה ואישי באותה קטגוריה — מחזיר את המובנה ולא מוותר', () {
      final bavli = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavli);

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final userPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\אישיים\ברכות.pdf',
        category: seder,
        isUserBook: true,
      );
      final builtInPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\otzaria\ברכות.pdf',
        category: seder,
      );
      seder.books.addAll([sourceText, userPdf, builtInPdf]);

      final library = Library(categories: [bavli]);

      expect(library.getCompanionBook(sourceText, PdfBook), same(builtInPdf));
    });

    test('ספר מקטלוג חיצוני — לא נבחר עבור ספר מקומי בשם זהה', () {
      final bavli = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavli);
      final externalRoot = _category('קטלוג חיצוני');

      final sourceText = TextBook(title: 'ברכות', category: seder);
      final externalPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\external\ברכות.pdf',
        category: externalRoot,
        externalLibraryId: 'hebrewbooks',
      );
      final builtInPdf = PdfBook(
        title: 'ברכות',
        path: r'C:\otzaria\תלמוד בבלי\ברכות.pdf',
        category: bavli,
      );
      seder.books.add(sourceText);
      externalRoot.books.add(externalPdf);
      bavli.books.add(builtInPdf);

      final library = Library(categories: [externalRoot, bavli]);

      expect(library.getCompanionBook(sourceText, PdfBook), same(builtInPdf));
    });
  });
}
