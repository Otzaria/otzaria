import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';

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
  group('isTalmudBavliBook', () {
    test('זיהוי לפי categoryPath', () {
      expect(
        isTalmudBavliBook(
          TextBook(title: 'ברכות', categoryPath: 'תלמוד בבלי/סדר זרעים'),
        ),
        isTrue,
      );
      expect(
        isTalmudBavliBook(
          TextBook(title: 'ברכות', categoryPath: 'משנה/סדר זרעים'),
        ),
        isFalse,
      );
    });

    test('זיהוי לפי עץ הקטגוריות', () {
      final root = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: root);
      expect(
        isTalmudBavliBook(TextBook(title: 'ברכות', category: seder)),
        isTrue,
      );

      final otherRoot = _category('הלכה');
      expect(
        isTalmudBavliBook(
          TextBook(
            title: 'ברכות',
            category: _category('ברכות', parent: otherRoot),
          ),
        ),
        isFalse,
      );
    });

    test('מפרשים תחת שורש תלמוד בבלי — אינם מסכתות', () {
      final root = _category('תלמוד בבלי');
      final rishonim = _category('ראשונים', parent: root);
      expect(
        isTalmudBavliBook(TextBook(title: 'רשב"א', category: rishonim)),
        isFalse,
      );
      expect(
        isTalmudBavliBook(
          TextBook(title: 'רש"י', categoryPath: 'תלמוד בבלי/ראשונים'),
        ),
        isFalse,
      );
    });

    test('PDF בקטגוריית השורש תלמוד בבלי (מסכתות סרוקות) — מסכת', () {
      expect(
        isTalmudBavliBook(
          PdfBook(
            title: 'ברכות',
            path: r'C:\books\תלמוד בבלי\ברכות.pdf',
            category: _category('תלמוד בבלי'),
          ),
        ),
        isTrue,
      );
    });

    test('PDF ללא קטגוריה — זיהוי לפי נתיב הקובץ', () {
      expect(
        isTalmudBavliBook(
          PdfBook(title: 'ברכות', path: r'C:\books\תלמוד בבלי\ברכות.pdf'),
        ),
        isTrue,
      );
      expect(
        isTalmudBavliBook(
          PdfBook(title: 'ברכות', path: r'C:\books\הלכה\ברכות.pdf'),
        ),
        isFalse,
      );
      // קובץ בתת-תיקייה של תלמוד בבלי אינו מסכת.
      expect(
        isTalmudBavliBook(
          PdfBook(title: 'רש"י', path: r'C:\books\תלמוד בבלי\מפרשים\רשי.pdf'),
        ),
        isFalse,
      );
    });
  });

  group('isTalmudBavliPdfLibraryDuplicate', () {
    const textTitles = {'ברכות'};

    test('PDF נלווה של מסכת עם מהדורת טקסט הוא כפילות-תצוגה; טקסט אינו', () {
      expect(
        isTalmudBavliPdfLibraryDuplicate(
          PdfBook(title: 'ברכות', path: r'C:\books\תלמוד בבלי\ברכות.pdf'),
          textTitles,
        ),
        isTrue,
      );
      expect(
        isTalmudBavliPdfLibraryDuplicate(
          TextBook(title: 'ברכות', categoryPath: 'תלמוד בבלי/סדר זרעים'),
          textTitles,
        ),
        isFalse,
      );
    });

    test(
      'התאמת כותרות מנורמלת — גרשיים ורווחים כפולים לא שוברים את הסינון',
      () {
        final bavliRoot = _category('תלמוד בבלי');
        final seder = _category('סדר זרעים', parent: bavliRoot);
        seder.books.add(TextBook(title: 'ע״ז', category: seder));
        final titles = talmudBavliTextTitles(Library(categories: [bavliRoot]));

        expect(
          isTalmudBavliPdfLibraryDuplicate(
            PdfBook(title: 'ע"ז', path: r'C:\books\תלמוד בבלי\עז.pdf'),
            titles,
          ),
          isTrue,
        );
        expect(
          isTalmudBavliPdfLibraryDuplicate(
            PdfBook(
              title: 'בבא  קמא',
              path: r'C:\books\תלמוד בבלי\בבא קמא.pdf',
            ),
            {normalizeBookTitle('בבא קמא')},
          ),
          isTrue,
        );
      },
    );

    test('PDF של מסכת ללא מהדורת טקסט — לא מוסתר (לא נעלם מהספרייה)', () {
      expect(
        isTalmudBavliPdfLibraryDuplicate(
          PdfBook(title: 'שבת', path: r'C:\books\תלמוד בבלי\שבת.pdf'),
          textTitles,
        ),
        isFalse,
      );
    });

    test('ספרי משתמש, קטלוג חיצוני ומפרשי PDF — אינם מסוננים', () {
      expect(
        isTalmudBavliPdfLibraryDuplicate(
          PdfBook(
            title: 'ברכות',
            path: r'C:\books\תלמוד בבלי\ברכות.pdf',
            isUserBook: true,
          ),
          textTitles,
        ),
        isFalse,
      );
      expect(
        isTalmudBavliPdfLibraryDuplicate(
          PdfBook(
            title: 'ברכות',
            path: r'C:\books\תלמוד בבלי\ברכות.pdf',
            externalLibraryId: 'otzar',
          ),
          textTitles,
        ),
        isFalse,
      );
      expect(
        isTalmudBavliPdfLibraryDuplicate(
          PdfBook(title: 'רש"י', path: r'C:\books\תלמוד בבלי\מפרשים\רשי.pdf'),
          {'רש"י', ...textTitles},
        ),
        isFalse,
      );
    });

    test('talmudBavliTextTitles אוסף רק מהדורות טקסט רשמיות של מסכתות', () {
      final bavliRoot = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavliRoot);
      seder.books.add(TextBook(title: 'ברכות', category: seder));
      // טקסט אישי לא מייצג את ה-PDF המובנה — אסור שיגרום להסתרתו.
      seder.books.add(
        TextBook(title: 'עירובין', category: seder, isUserBook: true),
      );
      bavliRoot.books.add(
        PdfBook(
          title: 'שבת',
          path: r'C:\books\תלמוד בבלי\שבת.pdf',
          category: bavliRoot,
        ),
      );
      final halacha = _category('הלכה');
      halacha.books.add(TextBook(title: 'משנה ברורה', category: halacha));
      final library = Library(categories: [bavliRoot, halacha]);

      expect(talmudBavliTextTitles(library), {'ברכות'});
    });
  });

  group('findTextBookByExactCategory', () {
    Library buildLibrary() {
      final bavliRoot = _category('תלמוד בבלי');
      final seder = _category('סדר זרעים', parent: bavliRoot);
      final otherRoot = _category('הלכה');
      final otherCat = _category('ענייני ברכות', parent: otherRoot);
      seder.books.add(
        TextBook(title: 'ברכות', category: seder, categoryId: 10),
      );
      otherCat.books.add(
        TextBook(title: 'ברכות', category: otherCat, categoryId: 20),
      );
      return Library(categories: [bavliRoot, otherRoot]);
    }

    test('התאמת categoryId מדויקת מבחינה בין ספרים בעלי שם זהה', () {
      final library = buildLibrary();
      final bavli = findTextBookByExactCategory(library, 'ברכות', 10);
      expect(bavli, isNotNull);
      expect(isTalmudBavliBook(bavli!), isTrue);

      final other = findTextBookByExactCategory(library, 'ברכות', 20);
      expect(other, isNotNull);
      expect(isTalmudBavliBook(other!), isFalse);
    });

    test('ללא categoryId או בהיעדר התאמה — null (אין נפילה לכותרת)', () {
      final library = buildLibrary();
      expect(findTextBookByExactCategory(library, 'ברכות', null), isNull);
      expect(findTextBookByExactCategory(library, 'ברכות', 99), isNull);
    });
  });
}
