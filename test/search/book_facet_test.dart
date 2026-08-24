import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/book_facet.dart';

void main() {
  group('BookFacet.findMatchingBook', () {
    test('מעדיף מזהה יציב על פני כותרת בלבד כאשר יש ספרים כפולי-שם', () {
      final first = TextBook(
        id: 11,
        title: 'שבת',
        categoryPath: '/תלמוד בבלי/סדר מועד',
        fileType: 'txt',
      );
      final second = TextBook(
        id: 22,
        title: 'שבת',
        categoryPath: '/הלכה',
        fileType: 'txt',
      );

      final match = BookFacet.findMatchingBook(
        [first, second],
        title: 'שבת',
        type: TextBook,
        bookId: 22,
        categoryPath: '/הלכה',
        fileType: 'txt',
      );

      expect(match, same(second));
    });

    test('מעדיף נתיב קובץ עבור ספרי PDF עם אותו שם', () {
      final first = PdfBook(
        title: 'סידור',
        path: r'C:\books\a.pdf',
        fileType: 'pdf',
      );
      final second = PdfBook(
        title: 'סידור',
        path: r'C:\books\b.pdf',
        fileType: 'pdf',
      );

      final match = BookFacet.findMatchingBook(
        [first, second],
        title: 'סידור',
        type: PdfBook,
        fileType: 'pdf',
        filePath: r'C:\books\b.pdf',
      );

      expect(match, same(second));
    });

    test('מחזיר null כשיש כמה ספרים באותה כותרת ואף מזהה לא הכריע', () {
      final first = TextBook(
        id: 11,
        title: 'שבת',
        categoryPath: '/תלמוד בבלי/סדר מועד',
        fileType: 'txt',
      );
      final second = TextBook(
        id: 22,
        title: 'שבת',
        categoryPath: '/הלכה',
        fileType: 'txt',
      );

      final match = BookFacet.findMatchingBook(
        [first, second],
        title: 'שבת',
        type: TextBook,
      );

      expect(match, isNull);
    });

    test('מחזיר מועמד יחיד גם ללא מזהים נוספים', () {
      final only = TextBook(
        id: 11,
        title: 'שבת',
        categoryPath: '/תלמוד בבלי/סדר מועד',
        fileType: 'txt',
      );

      final match = BookFacet.findMatchingBook(
        [only],
        title: 'שבת',
        type: TextBook,
      );

      expect(match, same(only));
    });
  });

  group('BookFacet.resolveTopics fallback normalization', () {
    test('מנרמל categoryPath בפורמט /a/b ל-topics בפורמט a, b', () {
      final facetPath = BookFacet.buildFacetPath(
        title: 'בראשית',
        topics: 'תנ"ך, תורה',
        bookId: 1,
      );

      expect(facetPath, '/תנ"ך/תורה/id:1');
    });

    test('מעדיף categoryPath על פני topics כשהם לא תואמים', () {
      final facetPath = BookFacet.buildFacetPath(
        title: 'בראשית',
        topics: 'מקרא',
        categoryPath: '/תנ"ך/תורה',
        bookId: 1,
      );

      expect(facetPath, '/תנ"ך/תורה/id:1');
    });

    test('מנרמל categoryPath ללא לוכסן מוביל', () {
      final facetPath = BookFacet.buildFacetPath(
        title: 'בראשית',
        topics: '',
        categoryPath: 'תנ"ך/תורה',
        bookId: 1,
      );

      expect(facetPath, '/תנ"ך/תורה/id:1');
    });

    test('ספר אישי עם אותו id מקבל מפתח uid נפרד מספר רשמי', () {
      final official = BookFacet.buildFacetPath(
        title: 'שבת',
        topics: '',
        bookId: 5,
        categoryPath: '/תלמוד בבלי',
      );
      final userBook = BookFacet.buildFacetPath(
        title: 'הערות',
        topics: '',
        bookId: 5,
        isUserBook: true,
        categoryPath: '/ספרים אישיים',
      );

      expect(official, '/תלמוד בבלי/id:5');
      expect(userBook, '/ספרים אישיים/uid:5');
    });

    test('מנרמל categoryPath בפורמט פסיקים לנתיב facet עם לוכסנים', () {
      final facetPath = BookFacet.buildFacetPath(
        title: 'בראשית',
        topics: '',
        categoryPath: 'תנ"ך, תורה',
        bookId: 1,
      );

      expect(facetPath, '/תנ"ך/תורה/id:1');
    });
  });

  group('מפתח הספר ב-facet זהה ל-catalogueOrderKey', () {
    String facetPathOf(Book book) => BookFacet.buildFacetPath(
      title: book.title,
      topics: book.topics,
      externalLibraryId: book.externalLibraryId,
      bookId: book.id,
      isUserBook: book.isUserBook,
      categoryPath: book.category?.path ?? book.categoryPath,
      fileType: book.fileType,
      filePath: book is FileBook ? book.path : book.filePath,
    );

    final books = <Book>[
      TextBook(id: 5, title: 'שבת', categoryPath: '/תלמוד בבלי'),
      TextBook(
        id: 5,
        title: 'שבת',
        categoryPath: '/ספרים אישיים',
        isUserBook: true,
      ),
      ExternalLibraryBook(
        title: 'ספר חיצוני',
        id: 1234,
        link: 'https://example.org/1234',
        externalLibraryId: 'hb:1234',
        topics: 'הלכה',
      ),
      TextBook(title: 'ללא מזהה', categoryPath: '/הלכה', fileType: 'txt'),
    ];

    for (final book in books) {
      test('${book.title} (${book.id ?? 'ללא id'})', () {
        expect(
          facetPathOf(book),
          endsWith('/${IndexingRepository.catalogueOrderKey(book)}'),
        );
      });
    }
  });
}
