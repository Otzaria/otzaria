import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';

void main() {
  ExternalLibraryBook catalogBook(int id, {String title = 'ספר'}) {
    return ExternalLibraryBook(
      title: title,
      id: id,
      author: 'מחבר',
      pubPlace: 'מקום',
      pubDate: 'שנה',
      topics: 'נושא',
      link: 'https://hebrewbooks.org/$id',
      externalLibraryId: 'hb:$id',
    );
  }

  group('mapHebrewBooksToLocal', () {
    test('ממיר ל-PdfBook כשקיים קובץ בתבנית Hebrewbooks_org_<id>.pdf', () {
      final books = [catalogBook(123)];
      final result = FileSystemData.mapHebrewBooksToLocal(books, {
        'hebrewbooks_org_123.pdf': r'C:\hb\Hebrewbooks_org_123.pdf',
      });

      expect(result.single, isA<PdfBook>());
      final pdf = result.single as PdfBook;
      expect(pdf.path, r'C:\hb\Hebrewbooks_org_123.pdf');
      expect(pdf.id, 123);
      expect(pdf.title, 'ספר');
      // שימור מטא-דאטה: המזהה החיצוני נשמר בהמרה ל-PdfBook.
      expect(pdf.externalLibraryId, 'hb:123');
      expect(pdf.author, 'מחבר');
      expect(pdf.pubDate, 'שנה');
    });

    test('ממיר ל-PdfBook כשקיים קובץ בתבנית <id>.pdf בלבד', () {
      final books = [catalogBook(456)];
      final result = FileSystemData.mapHebrewBooksToLocal(books, {
        '456.pdf': r'C:\hb\456.pdf',
      });

      expect(result.single, isA<PdfBook>());
      expect((result.single as PdfBook).path, r'C:\hb\456.pdf');
    });

    test('מעדיף את התבנית Hebrewbooks_org_ על פני <id>.pdf', () {
      final books = [catalogBook(789)];
      final result = FileSystemData.mapHebrewBooksToLocal(books, {
        'hebrewbooks_org_789.pdf': r'C:\hb\Hebrewbooks_org_789.pdf',
        '789.pdf': r'C:\hb\789.pdf',
      });

      expect((result.single as PdfBook).path, r'C:\hb\Hebrewbooks_org_789.pdf');
    });

    test('משאיר ExternalLibraryBook כשאין קובץ מקומי תואם', () {
      final books = [catalogBook(111)];
      final result = FileSystemData.mapHebrewBooksToLocal(books, {
        '222.pdf': r'C:\hb\222.pdf',
      });

      expect(result.single, isA<ExternalLibraryBook>());
      expect(result.single.id, 111);
    });

    test('מטפל בערבוב: חלק מקומיים וחלק חיצוניים', () {
      final books = [catalogBook(1), catalogBook(2), catalogBook(3)];
      final result = FileSystemData.mapHebrewBooksToLocal(books, {
        'hebrewbooks_org_1.pdf': r'C:\hb\Hebrewbooks_org_1.pdf',
        '3.pdf': r'C:\hb\3.pdf',
      });

      expect(result[0], isA<PdfBook>());
      expect(result[1], isA<ExternalLibraryBook>());
      expect(result[2], isA<PdfBook>());
    });
  });

  group('extractHebrewBookIds', () {
    test('מחלץ מזהים משתי תבניות השמות', () {
      final ids = FileSystemData.extractHebrewBookIds([
        'hebrewbooks_org_123.pdf',
        '456.pdf',
      ]);
      expect(ids, {123, 456});
    });

    test('מתעלם משמות שאינם תואמים תבנית', () {
      final ids = FileSystemData.extractHebrewBookIds([
        '1.pdf',
        'notes.pdf',
        'book_abc.pdf',
        'readme.txt',
        '12.epub',
      ]);
      expect(ids, {1});
    });

    test('ממזג כפילויות (אותו מזהה בשתי התבניות)', () {
      final ids = FileSystemData.extractHebrewBookIds([
        'hebrewbooks_org_50.pdf',
        '50.pdf',
      ]);
      expect(ids, {50});
    });

    test('מחזיר קבוצה ריקה כשאין קבצים תואמים', () {
      expect(FileSystemData.extractHebrewBookIds(const []), isEmpty);
      expect(FileSystemData.extractHebrewBookIds(['x.pdf']), isEmpty);
    });
  });

  // #2964: קבצים שלא יוצגו נספרים כדי להפנות את המשתמש ל"ספרים אישיים".
  group('countUnrecognizedHebrewBookFiles', () {
    test('סופר שמות שאינם בתבנית ומזהים שאינם בקטלוג', () {
      final count = FileSystemData.countUnrecognizedHebrewBookFiles(
        [
          '123.pdf',
          'hebrewbooks_org_456.pdf',
          'שולחן ערוך.pdf',
          'book_789.pdf',
          '999.pdf',
        ],
        {123, 456},
      );
      expect(count, 3);
    });

    test('אפס כשכל הקבצים מזוהים', () {
      expect(
        FileSystemData.countUnrecognizedHebrewBookFiles(
          [
            '50.pdf',
            'hebrewbooks_org_50.pdf',
          ],
          {50},
        ),
        0,
      );
      expect(FileSystemData.countUnrecognizedHebrewBookFiles(const [], {}), 0);
    });
  });
}
