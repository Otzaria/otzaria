import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/models/books.dart';

void main() {
  group('BookCompositeKey.toStorageKey', () {
    test('משלב את הסיומת "o" כשמדובר בספר רשמי', () {
      final key = BookCompositeKey.create(
        title: 'בראשית',
        categoryId: 7,
        fileType: 'txt',
      );

      expect(key.toStorageKey(), 'בראשית|7|txt|o');
    });

    test('משלב את הסיומת "u" כשמדובר בספר משתמש', () {
      final key = BookCompositeKey.create(
        title: 'ספר המשתמש',
        categoryId: 7,
        fileType: 'txt',
        isUserBook: true,
      );

      expect(key.toStorageKey(), 'ספר המשתמש|7|txt|u');
    });

    test('מנרמל סוג קובץ ריק ל-"txt"', () {
      final key = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 1,
        fileType: '',
      );

      expect(key.fileType, 'txt');
      expect(key.toStorageKey(), 'ספר|1|txt|o');
    });

    test('מנרמל סוג קובץ Mixed-case ורווחים', () {
      final key = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 1,
        fileType: '  PDF  ',
      );

      expect(key.fileType, 'pdf');
    });
  });

  group('BookCompositeKey.tryParse', () {
    test('מחזיר null עבור מחרוזת בלי מספיק חלקים', () {
      expect(BookCompositeKey.tryParse('title|7'), isNull);
      expect(BookCompositeKey.tryParse('only-title'), isNull);
    });

    test('מחזיר null עבור categoryId לא חוקי', () {
      expect(BookCompositeKey.tryParse('title|abc|txt'), isNull);
    });

    test('פורמט חדש: מזהה ספר רשמי לפי הסיומת "o"', () {
      final key = BookCompositeKey.tryParse('בראשית|7|txt|o');

      expect(key, isNotNull);
      expect(key!.title, 'בראשית');
      expect(key.categoryId, 7);
      expect(key.fileType, 'txt');
      expect(key.isUserBook, isFalse);
    });

    test('פורמט חדש: מזהה ספר משתמש לפי הסיומת "u"', () {
      final key = BookCompositeKey.tryParse('ספר אישי|7|txt|u');

      expect(key, isNotNull);
      expect(key!.isUserBook, isTrue);
    });

    test('תאימות לאחור: מחרוזת ישנה בלי סיומת מתפרשת כספר רשמי', () {
      // לפני PR284 הפורמט היה רק `title|categoryId|fileType` בלי הדגל.
      final key = BookCompositeKey.tryParse('בראשית|7|txt');

      expect(key, isNotNull);
      expect(key!.isUserBook, isFalse,
          reason: 'מחרוזת בלי סיומת = ספר רשמי לתאימות לאחור');
    });

    test('סיומת לא מוכרת מתפרשת כ-isUserBook=false', () {
      // כל ערך שאינו "u" → seforim. ה-API לא דורש "o" קשיח.
      final key = BookCompositeKey.tryParse('title|7|txt|x');

      expect(key, isNotNull);
      expect(key!.isUserBook, isFalse);
    });

    test('round-trip: toStorageKey ואז tryParse שומרים את כל השדות', () {
      final original = BookCompositeKey.create(
        title: 'ספר מבחן',
        categoryId: 42,
        fileType: 'PDF',
        isUserBook: true,
      );

      final parsed = BookCompositeKey.tryParse(original.toStorageKey());

      expect(parsed, equals(original));
    });
  });

  group('BookCompositeKey equality & hashCode', () {
    test('שווים כאשר כל השדות זהים — כולל isUserBook', () {
      final a = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 5,
        fileType: 'txt',
        isUserBook: true,
      );
      final b = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 5,
        fileType: 'txt',
        isUserBook: true,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('שונים כאשר רק isUserBook שונה', () {
      final official = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 5,
        fileType: 'txt',
      );
      final userBook = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 5,
        fileType: 'txt',
        isUserBook: true,
      );

      expect(official, isNot(equals(userBook)),
          reason:
              'אותו title+categoryId+fileType משני DBs חייבים להיות מפתחות שונים');
    });

    test('שונים כאשר רק categoryId שונה', () {
      final a = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 5,
        fileType: 'txt',
      );
      final b = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 6,
        fileType: 'txt',
      );

      expect(a, isNot(equals(b)));
    });
  });

  group('BookCompositeKey.fromBook', () {
    test('מחזיר null כשאין categoryId', () {
      final book = TextBook(title: 'ללא קטגוריה');

      expect(BookCompositeKey.fromBook(book), isNull);
    });

    test('מעתיק isUserBook מהספר', () {
      final userBook = TextBook(
        title: 'אישי',
        categoryId: 3,
        fileType: 'txt',
        isUserBook: true,
      );

      final key = BookCompositeKey.fromBook(userBook);

      expect(key, isNotNull);
      expect(key!.isUserBook, isTrue);
      expect(key.title, 'אישי');
      expect(key.categoryId, 3);
    });

    test('ספר רגיל נכנס עם isUserBook=false', () {
      final book = TextBook(
        title: 'רגיל',
        categoryId: 4,
        fileType: 'txt',
      );

      final key = BookCompositeKey.fromBook(book);

      expect(key, isNotNull);
      expect(key!.isUserBook, isFalse);
    });
  });

  group('BookCompositeKey.matches', () {
    test('matchesTitle משווה רק כותרת', () {
      final key = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 7,
        fileType: 'txt',
      );

      expect(key.matchesTitle('ספר'), isTrue);
      expect(key.matchesTitle('ספר אחר'), isFalse);
    });

    test('matches מקבל סוג קובץ אופציונלי ומנרמל אותו', () {
      final key = BookCompositeKey.create(
        title: 'ספר',
        categoryId: 7,
        fileType: 'txt',
      );

      expect(key.matches('ספר'), isTrue);
      expect(key.matches('ספר', otherFileType: 'TXT'), isTrue);
      expect(key.matches('ספר', otherFileType: 'pdf'), isFalse);
      expect(key.matches('שונה', otherFileType: 'txt'), isFalse);
    });
  });
}
