import 'dart:math';

import 'package:otzaria/data/book_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
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
        source: BookSource.user,
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

  group('BookFacet.resolveFacetCategoryPath — נתיב שכבר מנורמל', () {
    // הפיצול ב-RegExp, שהמסלול המהיר חייב להחזיר בדיוק את תוצאתו.
    String splitReference(String value) {
      final parts = value
          .trim()
          .split(RegExp(r'\s*(?:/|,)\s*'))
          .where((part) => part.isNotEmpty)
          .toList();
      return parts.isEmpty ? '' : '/${parts.join('/')}';
    }

    List<String> mismatches(Iterable<String> inputs) => [
      for (final input in inputs)
        if (BookFacet.resolveFacetCategoryPath(categoryPath: input) !=
            splitReference(input))
          input.codeUnits.join(','),
    ];

    test('זהה לפיצול בקצוות: פסיקים, רווחים ליד לוכסן, לוכסן כפול או בסוף', () {
      const inputs = [
        '/תנ"ך/תורה',
        '/תלמוד בבלי/סדר מועד',
        '/א ב ג/ד',
        '',
        ' ',
        '/',
        '//',
        '/א/',
        '//א',
        '/א//ב',
        '/א /ב',
        '/א/ ב',
        ' /א',
        '/א ',
        '/א,ב',
        '/א, ב',
        '/א,',
        'א/ב',
        'א',
        '/א\u00a0/ב',
        '/\u00a0א',
        '/א\u0085',
        '/א\ufeff',
        '/א\u2003/ב',
        '\t/א',
        '/א\n/ב',
      ];
      expect(mismatches(inputs), isEmpty);
    });

    test('זהה לפיצול על מחרוזות אקראיות', () {
      // כל תו יחידת UTF-16 אחת, ולכן הגרלת אינדקס מגרילה תו.
      const alphabet = '/, \t\u00a0\u0085\u180e\u2028\ufeffאב"';
      final random = Random(19);
      final inputs = List.generate(
        20000,
        (_) => List.generate(
          random.nextInt(8),
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join(),
      );
      expect(mismatches(inputs), isEmpty);
    });

    test('זהה לפיצול לכל תו ש-trim() או \\s בולעים, בקצה ולצד לוכסן', () {
      final whitespace = RegExp(r'^\s$');
      final spaces = [
        for (var c = 0; c <= 0xFFFF; c++)
          if (String.fromCharCode(c).trim().isEmpty ||
              whitespace.hasMatch(String.fromCharCode(c)))
            String.fromCharCode(c),
      ];
      expect(spaces, contains('　'));
      expect(
        mismatches([
          for (final s in spaces) ...['/א$s', '/א$s/ב', '/א/$sב', '$s/א'],
        ]),
        isEmpty,
      );
    });
  });

  group('מפתח הספר ב-facet זהה ל-BookIdentity.keyOf', () {
    String facetPathOf(Book book) => BookFacet.buildFacetPath(
      title: book.title,
      topics: book.topics,
      externalLibraryId: book.externalLibraryId,
      bookId: book.id,
      source: book.source,
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
        source: BookSource.user,
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
          endsWith('/${BookIdentity.keyOf(book)}'),
        );
      });
    }
  });
}
