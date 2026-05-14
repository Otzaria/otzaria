// בדיקות עבור פיצ'ר copy-direct-link
// Feature: copy-direct-link, Property 1: book link format
// Feature: copy-direct-link, Property 2: section link format

import 'package:otzaria/utils/book_link_builder.dart';
import 'package:test/test.dart';

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

  group('copy-direct-link — buildPdfBookLink', () {
    test('מחזיר פורמט נכון עבור bookId=1', () {
      expect(buildPdfBookLink(1), equals('otzaria://open/pdf/1'));
    });

    test('מחזיר פורמט נכון עבור bookId=999', () {
      expect(buildPdfBookLink(999), equals('otzaria://open/pdf/999'));
    });

    test('מחזיר פורמט נכון עבור bookId גדול', () {
      expect(buildPdfBookLink(123456), equals('otzaria://open/pdf/123456'));
    });

    test('Property: פורמט קישור PDF — 200 ערכים, ללא ?', () {
      for (int bookId = 1; bookId <= 200; bookId++) {
        final link = buildPdfBookLink(bookId);
        expect(link, equals('otzaria://open/pdf/$bookId'),
            reason: 'bookId=$bookId');
        expect(link.contains('?'), isFalse, reason: 'bookId=$bookId');
        expect(link.startsWith('otzaria://open/pdf/'), isTrue,
            reason: 'bookId=$bookId');
      }
    });
  });

  group('copy-direct-link — buildPdfPageLink', () {
    test('מחזיר פורמט נכון עבור bookId=1, page=1 (1-based)', () {
      expect(buildPdfPageLink(1, 1), equals('otzaria://open/pdf/1?index=1'));
    });

    test('מחזיר פורמט נכון עבור bookId=42, page=100', () {
      expect(
          buildPdfPageLink(42, 100), equals('otzaria://open/pdf/42?index=100'));
    });

    test('edge case: page=0 מוחלף ב-1 (PDF הוא 1-based)', () {
      expect(buildPdfPageLink(1, 0), equals('otzaria://open/pdf/1?index=1'));
    });

    test('edge case: page שלילי מוחלף ב-1', () {
      expect(buildPdfPageLink(1, -1), equals('otzaria://open/pdf/1?index=1'));
      expect(buildPdfPageLink(5, -100), equals('otzaria://open/pdf/5?index=1'));
    });

    test('Property: ערכי page חיוביים', () {
      for (int bookId = 1; bookId <= 50; bookId++) {
        for (int page = 1; page <= 100; page += 10) {
          final link = buildPdfPageLink(bookId, page);
          expect(link, equals('otzaria://open/pdf/$bookId?index=$page'),
              reason: 'bookId=$bookId, page=$page');
        }
      }
    });

    test('Property: ערכי page < 1 מוחלפים ב-1', () {
      for (int bookId = 1; bookId <= 20; bookId++) {
        for (final badPage in [0, -1, -5, -100, -9999]) {
          final link = buildPdfPageLink(bookId, badPage);
          expect(link, equals('otzaria://open/pdf/$bookId?index=1'),
              reason: 'bookId=$bookId, page=$badPage');
        }
      }
    });

    test('Property: הקישור תמיד מכיל ?index= עם max(1,page)', () {
      for (int bookId = 1; bookId <= 30; bookId++) {
        for (int page = -5; page <= 50; page += 5) {
          final link = buildPdfPageLink(bookId, page);
          final expectedPage = page < 1 ? 1 : page;
          expect(link, equals('otzaria://open/pdf/$bookId?index=$expectedPage'),
              reason: 'bookId=$bookId, page=$page');
        }
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
              link, equals('otzaria://open/book/$bookId?index=$expectedIndex'),
              reason: 'bookId=$bookId, index=$index');
        }
      }
    });
  });
}
