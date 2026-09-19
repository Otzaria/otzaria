import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/services/custom_folders/personal_books_import_service.dart';
import 'package:otzaria/utils/file/document_format.dart';

/// שומר על מקור-אמת אחד לרשימות הסיומות (§80).
///
/// לפני שהיה [DocumentFormat], כל הוספת פורמט דרשה עדכון של תשע רשימות
/// מפוזרות, ורשימה שנשכחה גרמה לספר שנסרק אך לא נפתח (או להפך). הבדיקות
/// כאן נכשלות ברגע שרשימה כלשהי מתפצלת מה-registry.
void main() {
  group('registry ↔ צרכנים', () {
    test('ייבוא ספרים אישיים משתמש בדיוק ברשימת ה-registry', () {
      expect(
        PersonalBooksImportService.supportedExtensions,
        kSupportedDottedBookExtensions.toSet(),
      );
    });

    test('isSupportedFile של הייבוא ו-isSupportedBookFile מסכימים', () {
      const paths = [
        'ספר.txt',
        'ספר.text',
        'ספר.pdf',
        'ספר.docx',
        'ספר.epub',
        'ספר.md',
        'ספר.markdown',
        'ספר.odt',
        'ספר.rtf',
        'ספר.doc',
        'ספר.html',
        'ספר.htm',
        'ספר.xhtml',
        'ספר.xyz',
        'ספר',
        'ספר.DOCX',
        'ספר.HTML',
      ];
      for (final path in paths) {
        expect(
          PersonalBooksImportService.isSupportedFile(path.toLowerCase()),
          isSupportedBookFile(path),
          reason: path,
        );
      }
    });
  });

  group('registry ↔ מודל הספר', () {
    test('כל פורמט production מיוצר למחלקת ספר תקינה', () {
      for (final format in kProductionBookFormats) {
        final book = buildBookForFileType(
          fileType: format.extension,
          title: 'ספר',
          path: 'C:/ספרים/ספר.${format.extension}',
          filePath: 'C:/ספרים/ספר.${format.extension}',
          categoryId: 7,
        );
        expect(book.fileType, format.extension, reason: format.name);
        if (format == DocumentFormat.pdf) {
          expect(book, isA<PdfBook>(), reason: format.name);
        } else {
          expect(book, isNot(isA<PdfBook>()), reason: format.name);
        }
      }
    });

    test('פורמט הדורש המרה מיוצר כספר-מסמך שניתן לעטוף ל-TextBook', () {
      for (final format in DocumentFormat.values) {
        if (!format.requiresConversion ||
            format == DocumentFormat.md ||
            format == DocumentFormat.markdown) {
          continue;
        }
        final book = buildBookForFileType(
          fileType: format.extension,
          title: 'ספר',
          path: 'C:/ספרים/ספר.${format.extension}',
          filePath: 'C:/ספרים/ספר.${format.extension}',
          categoryId: 7,
        );
        expect(book, isA<ConvertibleDocumentBook>(), reason: format.name);
      }
    });

    test('DOCX/EPUB ממשיכים לקבל את המחלקות הוותיקות (תאימות לאחור)', () {
      Book build(String fileType) => buildBookForFileType(
        fileType: fileType,
        title: 'ספר',
        path: 'C:/ספרים/ספר.$fileType',
        filePath: 'C:/ספרים/ספר.$fileType',
      );
      expect(build('docx'), isA<DocxBook>());
      expect(build('epub'), isA<EpubBook>());
      expect(build('txt'), isA<TextBook>());
      expect(build('md'), isA<TextBook>());
    });

    test('ספר בלי קובץ נשאר TextBook ושומר את fileType', () {
      final book = buildBookForFileType(
        fileType: 'docx',
        title: 'ספר',
        path: 'ספר',
      );
      expect(book, isA<TextBook>());
      expect(book.fileType, 'docx');
    });
  });

  group('toTextBook — שימור זהות (§16, §17)', () {
    for (final fileType in [
      'docx',
      'epub',
      'odt',
      'rtf',
      'docm',
      'html',
      'htm',
      'xhtml',
    ]) {
      test('$fileType שומר את כל שדות הזהות', () {
        final book =
            buildBookForFileType(
                  fileType: fileType,
                  id: 42,
                  title: 'ספר',
                  path: 'C:/ספרים/ספר.$fileType',
                  filePath: 'C:/ספרים/ספר.$fileType',
                  categoryId: 7,
                  source: BookSource.user,
                  externalLibraryId: 'hb:123',
                )
                as ConvertibleDocumentBook;

        final wrapped = book.toTextBook();

        expect(wrapped.id, book.id);
        expect(wrapped.categoryId, book.categoryId);
        expect(wrapped.externalLibraryId, book.externalLibraryId);
        expect(wrapped.fileType, book.fileType);
        expect(wrapped.filePath, book.filePath ?? book.path);
        expect(wrapped.isUserBook, book.isUserBook);
      });
    }

    test('filePath ריק נופל ל-path כדי שהממיר ימצא את הקובץ', () {
      final book = DocxBook(
        title: 'ספר',
        path: 'C:/ספרים/ספר.docx',
        categoryId: 7,
      );
      expect(book.toTextBook().filePath, 'C:/ספרים/ספר.docx');
    });
  });

  group('סיריאליזציה — תאימות לאחור (§18)', () {
    test('DocxBook/EpubBook שמורים ממשיכים להיטען', () {
      final docx = Book.fromJson({
        'type': 'DocxBook',
        'title': 'ספר',
        'path': 'C:/ספרים/ספר.docx',
        'filePath': 'C:/ספרים/ספר.docx',
      });
      expect(docx, isA<DocxBook>());
      expect(docx.fileType, 'docx');

      final epub = Book.fromJson({
        'type': 'EpubBook',
        'title': 'ספר',
        'path': 'C:/ספרים/ספר.epub',
      });
      expect(epub, isA<EpubBook>());
      expect(epub.fileType, 'epub');
    });

    test('DocumentBook עובר round-trip ושומר fileType', () {
      for (final fileType in [
        'odt',
        'rtf',
        'docm',
        'dotx',
        'html',
        'htm',
        'xhtml',
      ]) {
        final original = DocumentBook(
          id: 5,
          title: 'ספר',
          path: 'C:/ספרים/ספר.$fileType',
          filePath: 'C:/ספרים/ספר.$fileType',
          categoryId: 3,
          fileType: fileType,
          source: BookSource.user,
        );
        final restored = Book.fromJson(original.toJson());

        expect(restored, isA<DocumentBook>(), reason: fileType);
        expect(restored.fileType, fileType, reason: fileType);
        expect(restored.id, 5, reason: fileType);
        expect(restored.categoryId, 3, reason: fileType);
        expect(restored.isUserBook, isTrue, reason: fileType);
      }
    });
  });
}
