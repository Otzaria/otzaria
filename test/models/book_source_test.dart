import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';

void main() {
  group('BookSource', () {
    test('wireKey ופענוח הדדיים', () {
      final attached = BookSource.attached('my-lib');
      expect(BookSource.official.wireKey, 'o');
      expect(BookSource.user.wireKey, 'u');
      expect(attached.wireKey, 'd:my-lib');

      for (final source in [BookSource.official, BookSource.user, attached]) {
        expect(BookSource.tryParse(source.wireKey), source);
      }
    });

    test('שוויון מסד מצורף לפי slug', () {
      expect(BookSource.attached('a'), BookSource.attached('a'));
      expect(
        BookSource.attached('a').hashCode,
        BookSource.attached('a').hashCode,
      );
      expect(BookSource.attached('a'), isNot(BookSource.attached('b')));
      expect(BookSource.attached('o'), isNot(BookSource.official));
    });

    test('ערך לא מוכר או slug לא חוקי אינו מתפענח', () {
      expect(BookSource.tryParse(null), isNull);
      expect(BookSource.tryParse(''), isNull);
      expect(BookSource.tryParse('x'), isNull);
      expect(BookSource.tryParse('d:'), isNull);
      expect(BookSource.tryParse('d:a|b'), isNull);
      expect(BookSource.tryParse('d:a:b'), isNull);
      expect(() => BookSource.attached('a b'), throwsArgumentError);
    });

    test('slug עברי מותר', () {
      expect(BookSource.isValidSlug('ספרייה_1'), isTrue);
      expect(
        BookSource.tryParse('d:ספרייה_1'),
        BookSource.attached('ספרייה_1'),
      );
    });

    test('סיומת הזהות: רשמי ריק, אישי ללא שינוי, מצורף לפי slug', () {
      expect(BookSource.official.identitySuffix, '');
      expect(BookSource.user.identitySuffix, '|src:u');
      expect(BookSource.attached('x').identitySuffix, '|src:d:x');
    });

    test('סדר ברירת המחדל: רשמי, אישי, מצורף', () {
      expect(BookSource.official.rank, lessThan(BookSource.user.rank));
      expect(BookSource.user.rank, lessThan(BookSource.attached('x').rank));
    });

    test('fromJson: source גובר, ובלעדיו הדגל הישן', () {
      expect(BookSource.fromJson({'source': 'd:x'}), BookSource.attached('x'));
      expect(
        BookSource.fromJson({'source': 'o', 'isUserBook': true}),
        BookSource.official,
      );
      expect(BookSource.fromJson({'isUserBook': true}), BookSource.user);
      expect(BookSource.fromJson({}), BookSource.official);
      expect(
        BookSource.fromJson({'source': 42, 'isUserBook': true}),
        BookSource.user,
      );
    });
  });

  group('Book JSON — תאימות לאחור', () {
    test('JSON ישן בלי source נקרא לפי isUserBook', () {
      final user = Book.fromJson({
        'type': 'TextBook',
        'title': 'ספר',
        'isUserBook': true,
      });
      final official = Book.fromJson({'type': 'TextBook', 'title': 'ספר'});

      expect(user.source, BookSource.user);
      expect(user.isUserBook, isTrue);
      expect(official.source, BookSource.official);
    });

    test('JSON חדש כותב גם source וגם isUserBook לגרסה ישנה', () {
      final attached = TextBook(title: 'א', source: BookSource.attached('x'));
      final user = PdfBook(title: 'ב', path: 'b.pdf', source: BookSource.user);

      expect(attached.toJson()['source'], 'd:x');
      expect(attached.toJson()['isUserBook'], isFalse);
      expect(user.toJson()['source'], 'u');
      expect(user.toJson()['isUserBook'], isTrue);
    });

    test('round-trip שומר את המקור בכל סוגי הספרים', () {
      final source = BookSource.attached('lib');
      final books = <Book>[
        TextBook(title: 'ט', source: source),
        PdfBook(title: 'פ', path: 'p.pdf', source: source),
        DocxBook(title: 'ד', path: 'd.docx', source: source),
        EpubBook(title: 'א', path: 'a.epub', source: source),
        DocumentBook(
          title: 'מ',
          path: 'm.odt',
          fileType: 'odt',
          source: source,
        ),
        ExternalLibraryBook(title: 'ח', id: 3, link: 'l', source: source),
      ];
      for (final book in books) {
        expect(Book.fromJson(book.toJson()).source, source, reason: book.title);
      }
    });

    test('toTextBook ו-copyWith שומרים את המקור', () {
      final source = BookSource.attached('lib');
      final docx = DocxBook(title: 'ד', path: 'd.docx', source: source);
      expect(docx.toTextBook().source, source);
      expect(
        TextBook(title: 'ט', source: source).copyWith(id: 4).source,
        source,
      );
    });
  });

  group('Book.isOfficialLibraryBook', () {
    test('רשמי בלי מזהה חיצוני או עם מסכת PDF מצורפת', () {
      expect(TextBook(title: 'א').isOfficialLibraryBook, isTrue);
      expect(
        TextBook(title: 'א', externalLibraryId: '').isOfficialLibraryBook,
        isTrue,
      );
      expect(
        PdfBook(
          title: 'שבת',
          path: 'shabbat.pdf',
          externalLibraryId: 'talmud-pdf:שבת',
        ).isOfficialLibraryBook,
        isTrue,
      );
    });

    test('אישי, מצורף וקטלוג חיצוני אינם ספרייה רשמית', () {
      expect(
        TextBook(title: 'א', source: BookSource.user).isOfficialLibraryBook,
        isFalse,
      );
      expect(
        TextBook(
          title: 'א',
          source: BookSource.attached('x'),
        ).isOfficialLibraryBook,
        isFalse,
      );
      expect(
        ExternalLibraryBook(
          title: 'א',
          id: 1,
          link: 'l',
          externalLibraryId: 'oh:1',
        ).isOfficialLibraryBook,
        isFalse,
      );
    });
  });

  group('BookCompositeKey — מסד מצורף', () {
    test('סיריאליזציה ופענוח עם d:<slug>', () {
      final key = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 3,
        fileType: 'txt',
        source: BookSource.attached('lib'),
      );
      expect(key.toStorageKey(), 'ספר|3|txt|d:lib');
      expect(BookCompositeKey.tryParse(key.toStorageKey()), key);
    });

    test('אותו ספר ממקורות שונים הוא מפתח שונה', () {
      BookCompositeKey keyFor(BookSource source) => BookCompositeKey.create(
        title: 'ספר',
        categoryId: 3,
        source: source,
      );
      final keys = {
        keyFor(BookSource.official),
        keyFor(BookSource.user),
        keyFor(BookSource.attached('a')),
        keyFor(BookSource.attached('b')),
      };
      expect(keys, hasLength(4));
    });
  });

  group('personalNotesBookKey', () {
    test('רשמי ואישי ממופתחים לפי הכותרת בלבד, כמו הערות קיימות', () {
      expect(personalNotesBookKey(TextBook(title: 'בראשית')), 'בראשית');
      expect(
        personalNotesBookKey(
          TextBook(title: 'בראשית', source: BookSource.user),
        ),
        'בראשית',
      );
    });

    test('מסד מצורף מקבל סיומת ומתפרק חזרה', () {
      final book = TextBook(title: 'בראשית', source: BookSource.attached('x'));
      final key = personalNotesBookKey(book);
      expect(key, 'בראשית|db:x');

      final parsed = parsePersonalNotesBookKey(key);
      expect(parsed.title, 'בראשית');
      expect(parsed.source, BookSource.attached('x'));
    });

    test('מפתח בלי סיומת מחזיר את הכותרת כמות שהיא', () {
      final parsed = parsePersonalNotesBookKey('ספר | עם קו');
      expect(parsed.title, 'ספר | עם קו');
      expect(parsed.source, isNull);
    });
  });
}
