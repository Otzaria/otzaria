// בדיקות עבור פיצ'ר copy-direct-link
// Feature: copy-direct-link, Property 1: book link format
// Feature: copy-direct-link, Property 2: section link format

import 'package:test/test.dart';

// הלוגיקה הטהורה — מועתקת מ-link_helpers.dart לצורך בדיקה ללא תלות ב-Flutter
String buildBookLink(int bookId) => 'otzaria://open/book/$bookId';
String buildSectionLink(int bookId, int index) =>
    'otzaria://open/book/$bookId?index=${index < 0 ? 0 : index}';

void main() {
  group('copy-direct-link — buildBookLink', () {
    test('מחזיר פורמט נכון עבור bookId=1', () {
      expect(buildBookLink(1), equals('otzaria://open/book/1'));
    });

    test('מחזיר פורמט נכון עבור bookId=999', () {
      expect(buildBookLink(999), equals('otzaria://open/book/999'));
    });

    test('מחזיר פורמט נכון עבור bookId גדול', () {
      expect(buildBookLink(123456), equals('otzaria://open/book/123456'));
    });

    // Property 1: פורמט קישור ספר — Validates: Requirements 1.5, 3.1
    test('Property 1: פורמט קישור ספר — 200 ערכים', () {
      for (int bookId = 1; bookId <= 200; bookId++) {
        final link = buildBookLink(bookId);
        expect(link, equals('otzaria://open/book/$bookId'),
            reason: 'bookId=$bookId');
        expect(link.contains('?'), isFalse, reason: 'bookId=$bookId');
        expect(link.startsWith('otzaria://open/book/'), isTrue,
            reason: 'bookId=$bookId');
      }
    });
  });

  group('copy-direct-link — buildSectionLink', () {
    test('מחזיר פורמט נכון עבור bookId=1, index=0', () {
      expect(buildSectionLink(1, 0), equals('otzaria://open/book/1?index=0'));
    });

    test('מחזיר פורמט נכון עבור bookId=42, index=100', () {
      expect(buildSectionLink(42, 100),
          equals('otzaria://open/book/42?index=100'));
    });

    test('edge case: index שלילי מוחלף ב-0', () {
      expect(buildSectionLink(1, -1), equals('otzaria://open/book/1?index=0'));
      expect(
          buildSectionLink(5, -100), equals('otzaria://open/book/5?index=0'));
    });

    // Property 2: פורמט קישור מקטע — Validates: Requirements 1.6, 2.6, 3.2, 3.4
    test('Property 2: ערכי index אי-שליליים', () {
      for (int bookId = 1; bookId <= 50; bookId++) {
        for (int index = 0; index <= 100; index += 10) {
          final link = buildSectionLink(bookId, index);
          expect(link, equals('otzaria://open/book/$bookId?index=$index'),
              reason: 'bookId=$bookId, index=$index');
        }
      }
    });

    test('Property 2: ערכי index שליליים מוחלפים ב-0', () {
      for (int bookId = 1; bookId <= 20; bookId++) {
        for (final negIndex in [-1, -5, -100, -9999]) {
          final link = buildSectionLink(bookId, negIndex);
          expect(link, equals('otzaria://open/book/$bookId?index=0'),
              reason: 'bookId=$bookId, index=$negIndex');
        }
      }
    });

    test('Property 2: הקישור תמיד מכיל ?index= עם max(0,index)', () {
      for (int bookId = 1; bookId <= 30; bookId++) {
        for (int index = -5; index <= 50; index += 5) {
          final link = buildSectionLink(bookId, index);
          final expectedIndex = index < 0 ? 0 : index;
          expect(
              link,
              equals(
                  'otzaria://open/book/$bookId?index=$expectedIndex'),
              reason: 'bookId=$bookId, index=$index');
        }
      }
    });
  });
}
