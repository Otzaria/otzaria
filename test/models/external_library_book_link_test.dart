import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';

/// `link` הוא `String?` כדי שספק ללא נוכחות ברשת (פרויקט השו"ת) לא ייאלץ
/// להמציא URL; `null` חייב לשרוד round-trip.
void main() {
  group('ExternalLibraryBook ללא קישור', () {
    test('link: null שורד toJson/fromJson', () {
      final original = ExternalLibraryBook(
        title: 'ערוך השולחן יורה דעה',
        id: 1524,
        link: null,
        topics: 'הלכה',
        externalLibraryId: 'rp:1524',
      );

      final restored = Book.fromJson(original.toJson()) as ExternalLibraryBook;

      expect(restored.link, isNull);
      expect(restored.title, 'ערוך השולחן יורה דעה');
      expect(restored.id, 1524);
      expect(restored.externalLibraryId, 'rp:1524');
    });

    test('toJson כותב link: null ולא מחרוזת ריקה', () {
      final book = ExternalLibraryBook(title: 'ספר', id: 1, link: null);

      expect(book.toJson()['link'], isNull);
    });

    test('ספק עם קישור אינו מושפע', () {
      final original = ExternalLibraryBook(
        title: 'ספר אוצר',
        id: 42,
        link: 'https://tablet.otzar.org/book/book.php?book=42',
        externalLibraryId: 'oh:42',
      );

      final restored = Book.fromJson(original.toJson()) as ExternalLibraryBook;

      expect(restored.link, 'https://tablet.otzar.org/book/book.php?book=42');
      expect(restored.externalLibraryId, 'oh:42');
    });

    test('JSON ישן בלי המפתח link מתפענח ל-null ולא קורס', () {
      final restored =
          Book.fromJson({
                'type': 'ExternalLibraryBook',
                'title': 'ספר ישן',
                'otzarId': 7,
              })
              as ExternalLibraryBook;

      expect(restored.link, isNull);
      expect(restored.title, 'ספר ישן');
      expect(restored.id, 7);
    });
  });
}
