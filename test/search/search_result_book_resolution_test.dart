import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';

void main() {
  group('SearchBloc.bookForIndexedFilePathMap', () {
    late Library library;
    late TextBook official;
    late TextBook personal;
    late PdfBook pdf;

    setUp(() {
      official = TextBook(id: 5, title: 'שבת');
      personal = TextBook(id: 5, title: 'שבת', source: BookSource.user);
      pdf = PdfBook(title: 'שבת', path: r'C:\books\shabbat.pdf');
      library = Library(categories: []);
      library.books.addAll([official, personal, pdf]);
    });

    test('ספר אישי החולק כותרת ו-id עם ספר רשמי נפתר לספר האישי', () {
      // רגרסיה: פתיחת תוצאת חיפוש לפי כותרת בלבד פתחה את הספר הרשמי
      // במקום האישי — הזהות חייבת להשתחזר ממפתח האינדקס היציב.
      final booksByPath = SearchBloc.bookForIndexedFilePathMap(library);

      expect(
        booksByPath[IndexingRepository.buildIndexedBookFilePath(official)],
        same(official),
      );
      final resolved =
          booksByPath[IndexingRepository.buildIndexedBookFilePath(personal)];
      expect(resolved, same(personal));
      expect(resolved!.isUserBook, isTrue);
    });

    test('תוצאת PDF נפתרת לפי נתיב הקובץ', () {
      final booksByPath = SearchBloc.bookForIndexedFilePathMap(library);

      expect(booksByPath[pdf.path], same(pdf));
    });

    test('מפתח שאינו בקטלוג מחזיר null', () {
      final booksByPath = SearchBloc.bookForIndexedFilePathMap(library);

      expect(booksByPath['uid:999'], isNull);
    });
  });

  // האינדקס הוא מטמון של ה-DB ומפתחו הוא מזהה שורה. החלפת ספרייה מקצה את
  // המזהה לספר אחר, בעוד הכרטיס עדיין מציג את הכותרת מהמסמך הישן.
  group('IndexingRepository.bookForIndexedDocument — שער סנכרון האינדקס', () {
    late Library library;
    late TextBook rashiIsaiah;
    late Map<String, Book> booksByPath;

    setUp(() {
      rashiIsaiah = TextBook(id: 1234, title: 'רש"י על ישעיהו');
      library = Library(categories: []);
      library.books.addAll([
        rashiIsaiah,
        TextBook(id: 4321, title: 'רבינו חננאל על מועד קטן'),
      ]);
      booksByPath = SearchBloc.bookForIndexedFilePathMap(library);
    });

    test('מפתח שכותרתו תואמת מחזיר את הספר עצמו', () {
      expect(
        IndexingRepository.bookForIndexedDocument(
          booksByPath,
          indexedFilePath: IndexingRepository.buildIndexedBookFilePath(
            rashiIsaiah,
          ),
          indexedTitle: 'רש"י על ישעיהו',
        ),
        same(rashiIsaiah),
      );
    });

    test('רגרסיה #774/#712: מפתח שהוסב לספר אחר אינו נפתח', () {
      // האינדקס נבנה כש-id:1234 היה רש"י על ישעיהו; אחרי החלפת ה-DB המזהה
      // שייך לספר אחר, והלחיצה על הכרטיס הקפיצה לספר לא קשור.
      final staleLibrary = Library(categories: []);
      staleLibrary.books.add(
        TextBook(id: 1234, title: 'רבינו חננאל על מועד קטן'),
      );

      expect(
        IndexingRepository.bookForIndexedDocument(
          SearchBloc.bookForIndexedFilePathMap(staleLibrary),
          indexedFilePath: 'id:1234',
          indexedTitle: 'רש"י על ישעיהו',
        ),
        isNull,
      );
    });

    test('מפתח שאינו בקטלוג מחזיר null', () {
      expect(
        IndexingRepository.bookForIndexedDocument(
          booksByPath,
          indexedFilePath: 'id:999999',
          indexedTitle: 'רש"י על ישעיהו',
        ),
        isNull,
      );
    });

    test('מפה שטרם נבנתה (הספרייה בטעינה) מחזירה null ואינה זורקת', () {
      expect(
        IndexingRepository.bookForIndexedDocument(
          null,
          indexedFilePath: 'id:1234',
          indexedTitle: 'רש"י על ישעיהו',
        ),
        isNull,
      );
    });

    test('ההתאמה מדויקת — רווח נוסף בכותרת אינו נחשב תואם', () {
      expect(
        IndexingRepository.bookForIndexedDocument(
          booksByPath,
          indexedFilePath: 'id:1234',
          indexedTitle: 'רש"י על ישעיהו ',
        ),
        isNull,
      );
    });

    test('כותרת ריקה במסמך אינה פותחת ספר אקראי', () {
      expect(
        IndexingRepository.bookForIndexedDocument(
          booksByPath,
          indexedFilePath: 'id:1234',
          indexedTitle: '',
        ),
        isNull,
      );
    });

    test('השער אינו פוגע בהבחנה בין ספר אישי לרשמי בעלי כותרת זהה', () {
      // הכותרות זהות ולכן השער עובר, וזהות הספר האישי נשמרת.
      final official = TextBook(id: 5, title: 'שבת');
      final personal = TextBook(id: 5, title: 'שבת', source: BookSource.user);
      final mixed = Library(categories: []);
      mixed.books.addAll([official, personal]);
      final byPath = SearchBloc.bookForIndexedFilePathMap(mixed);

      final resolvedPersonal = IndexingRepository.bookForIndexedDocument(
        byPath,
        indexedFilePath: IndexingRepository.buildIndexedBookFilePath(personal),
        indexedTitle: 'שבת',
      );
      expect(resolvedPersonal, same(personal));
      expect(resolvedPersonal!.isUserBook, isTrue);

      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: IndexingRepository.buildIndexedBookFilePath(
            official,
          ),
          indexedTitle: 'שבת',
        ),
        same(official),
      );
    });

    test('PDF: נתיב תואם נפתר, ונתיב שהוסב לספר אחר מוחזר כ-null', () {
      const path = r'C:\books\shabbat.pdf';
      final pdf = PdfBook(title: 'שבת', path: path);
      final pdfLibrary = Library(categories: []);
      pdfLibrary.books.add(pdf);
      final byPath = SearchBloc.bookForIndexedFilePathMap(pdfLibrary);

      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: path,
          indexedTitle: 'שבת',
        ),
        same(pdf),
      );
      // אותו נתיב, קובץ שהוחלף בספר אחר — הכרטיס לא יפתח את החדש.
      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: path,
          indexedTitle: 'עירובין',
        ),
        isNull,
      );
    });

    test('ספר בלי id נפתר לפי המפתח המורכב, והכותרת מאמתת אותו', () {
      final fileBook = TextBook(
        title: 'ספר אישי',
        categoryPath: 'אישי',
        fileType: 'txt',
        filePath: r'C:\books\personal.txt',
      );
      final fileLibrary = Library(categories: []);
      fileLibrary.books.add(fileBook);
      final key = IndexingRepository.buildIndexedBookFilePath(fileBook);
      final byPath = SearchBloc.bookForIndexedFilePathMap(fileLibrary);

      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: key,
          indexedTitle: 'ספר אישי',
        ),
        same(fileBook),
      );
      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: key,
          indexedTitle: 'ספר אחר',
        ),
        isNull,
      );
    });

    test('ספר חיצוני נפתר לפי מפתח ext, והכותרת מאמתת אותו', () {
      final external = TextBook(
        title: 'ספר חיצוני',
        externalLibraryId: 'hb:77',
      );
      final externalLibrary = Library(categories: []);
      externalLibrary.books.add(external);
      final byPath = SearchBloc.bookForIndexedFilePathMap(externalLibrary);

      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: 'ext:hb:77',
          indexedTitle: 'ספר חיצוני',
        ),
        same(external),
      );
      expect(
        IndexingRepository.bookForIndexedDocument(
          byPath,
          indexedFilePath: 'ext:hb:77',
          indexedTitle: 'ספר שהוחלף',
        ),
        isNull,
      );
    });

    test('מפה ריקה מחזירה null', () {
      expect(
        IndexingRepository.bookForIndexedDocument(
          const {},
          indexedFilePath: 'id:1234',
          indexedTitle: 'רש"י על ישעיהו',
        ),
        isNull,
      );
    });
  });

  // השער משווה את כותרת הקטלוג לכותרת שבמסמך. Docx/Epub מאונדקסים דרך
  // toTextBook, ועטיפה שתשנה את הכותרת הייתה מפילה אותם על ספר תקין.
  group('שימור הכותרת בעטיפת toTextBook', () {
    test('DocxBook: הכותרת נשמרת בעטיפה', () {
      final docx = DocxBook(
        id: 42,
        title: 'שו"ת מהרש"ל',
        path: r'C:\books\maharshal.docx',
      );

      expect(docx.toTextBook().title, docx.title);
    });

    test('EpubBook: הכותרת נשמרת בעטיפה', () {
      final epub = EpubBook(
        id: 43,
        title: 'ספר האגדה',
        path: r'C:\books\aggada.epub',
      );

      expect(epub.toTextBook().title, epub.title);
    });

    test('ספר Docx בלי id: הכותרת נשמרת גם במסלול המפתח המורכב', () {
      final docx = DocxBook(
        title: 'חיבור אישי',
        path: r'C:\books\personal.docx',
        categoryPath: 'אישי',
      );

      expect(docx.toTextBook().title, docx.title);
    });
  });
}
