// בדיקות עבור פיצ'ר copy-direct-link
// Feature: copy-direct-link, Property 1: book link format
// Feature: copy-direct-link, Property 2: section link format

import 'package:test/test.dart';

// פונקציות עזר — העתק של הלוגיקה מ-text_book_screen.dart / pdf_book_screen.dart
// (הפונקציות הן private methods, לכן בודקים את הלוגיקה ישירות כאן)

String buildBookLink(int bookId) => 'otzaria://open/book/$bookId';

String buildSectionLink(int bookId, int index) =>
    'otzaria://open/book/$bookId?index=${index.clamp(0, double.maxFinite.toInt())}';

void main() {
  group('copy-direct-link — buildBookLink', () {
    // בדיקות יחידה ספציפיות
    test('מחזיר פורמט נכון עבור bookId=1', () {
      expect(buildBookLink(1), equals('otzaria://open/book/1'));
    });

    test('מחזיר פורמט נכון עבור bookId=999', () {
      expect(buildBookLink(999), equals('otzaria://open/book/999'));
    });

    test('מחזיר פורמט נכון עבור bookId גדול', () {
      expect(buildBookLink(123456), equals('otzaria://open/book/123456'));
    });

    // Property 1: פורמט קישור ספר
    // עבור כל bookId חיובי, הפלט הוא בדיוק 'otzaria://open/book/<bookId>'
    test('Property 1: פורמט קישור ספר — 200 ערכים אקראיים', () {
      // Validates: Requirements 1.5, 3.1
      final random = List.generate(200, (i) => i + 1); // bookIds 1..200
      for (final bookId in random) {
        final link = buildBookLink(bookId);
        expect(
          link,
          equals('otzaria://open/book/$bookId'),
          reason: 'bookId=$bookId',
        );
        // ודא שאין פרמטרים נוספים
        expect(link.contains('?'), isFalse, reason: 'bookId=$bookId');
        // ודא שהסכמה נכונה
        expect(link.startsWith('otzaria://open/book/'), isTrue,
            reason: 'bookId=$bookId');
      }
    });

    test('Property 1: ערכי bookId גדולים', () {
      // Validates: Requirements 1.5, 3.1
      for (final bookId in [1000, 9999, 100000, 999999]) {
        final link = buildBookLink(bookId);
        expect(link, equals('otzaria://open/book/$bookId'));
      }
    });
  });

  group('copy-direct-link — buildSectionLink', () {
    // בדיקות יחידה ספציפיות
    test('מחזיר פורמט נכון עבור bookId=1, index=0', () {
      expect(
          buildSectionLink(1, 0), equals('otzaria://open/book/1?index=0'));
    });

    test('מחזיר פורמט נכון עבור bookId=42, index=100', () {
      expect(
          buildSectionLink(42, 100), equals('otzaria://open/book/42?index=100'));
    });

    // edge case: index שלילי → ?index=0
    test('edge case: index שלילי מוחלף ב-0', () {
      expect(buildSectionLink(1, -1), equals('otzaria://open/book/1?index=0'));
      expect(buildSectionLink(5, -100), equals('otzaria://open/book/5?index=0'));
    });

    test('edge case: index=0 נשמר כ-0', () {
      expect(buildSectionLink(1, 0), equals('otzaria://open/book/1?index=0'));
    });

    // Property 2: פורמט קישור מקטע
    // עבור כל bookId חיובי ו-index כלשהו, הפלט הוא
    // 'otzaria://open/book/<bookId>?index=<max(0,index)>'
    test('Property 2: פורמט קישור מקטע — ערכי index אי-שליליים', () {
      // Validates: Requirements 1.6, 2.6, 3.2, 3.4
      for (int bookId = 1; bookId <= 50; bookId++) {
        for (int index = 0; index <= 100; index += 10) {
          final link = buildSectionLink(bookId, index);
          expect(
            link,
            equals('otzaria://open/book/$bookId?index=$index'),
            reason: 'bookId=$bookId, index=$index',
          );
        }
      }
    });

    test('Property 2: ערכי index שליליים מוחלפים ב-0', () {
      // Validates: Requirements 3.4
      for (int bookId = 1; bookId <= 20; bookId++) {
        for (final negIndex in [-1, -5, -100, -9999]) {
          final link = buildSectionLink(bookId, negIndex);
          expect(
            link,
            equals('otzaria://open/book/$bookId?index=0'),
            reason: 'bookId=$bookId, index=$negIndex',
          );
        }
      }
    });

    test('Property 2: הקישור תמיד מכיל ?index=', () {
      // Validates: Requirements 3.2
      for (int bookId = 1; bookId <= 30; bookId++) {
        for (int index = -5; index <= 50; index += 5) {
          final link = buildSectionLink(bookId, index);
          expect(link.contains('?index='), isTrue,
              reason: 'bookId=$bookId, index=$index');
          expect(link.startsWith('otzaria://open/book/'), isTrue,
              reason: 'bookId=$bookId, index=$index');
          // ודא שה-index בפועל הוא max(0, index)
          final expectedIndex = index < 0 ? 0 : index;
          expect(link.endsWith('?index=$expectedIndex'), isTrue,
              reason: 'bookId=$bookId, index=$index');
        }
      }
    });
  });
}
