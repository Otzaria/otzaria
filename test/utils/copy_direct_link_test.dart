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
        expect(
          link,
          equals('otzaria://open/book/$bookId'),
          reason: 'bookId=$bookId',
        );
        expect(link.contains('?'), isFalse, reason: 'bookId=$bookId');
        expect(
          link.startsWith('otzaria://open/book/'),
          isTrue,
          reason: 'bookId=$bookId',
        );
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
        expect(
          link,
          equals('otzaria://open/pdf/$bookId'),
          reason: 'bookId=$bookId',
        );
        expect(link.contains('?'), isFalse, reason: 'bookId=$bookId');
        expect(
          link.startsWith('otzaria://open/pdf/'),
          isTrue,
          reason: 'bookId=$bookId',
        );
      }
    });
  });

  group('copy-direct-link — buildPdfPageLink', () {
    test('מחזיר פורמט נכון עבור bookId=1, page=1 (1-based)', () {
      expect(buildPdfPageLink(1, 1), equals('otzaria://open/pdf/1?index=1'));
    });

    test('מחזיר פורמט נכון עבור bookId=42, page=100', () {
      expect(
        buildPdfPageLink(42, 100),
        equals('otzaria://open/pdf/42?index=100'),
      );
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
          expect(
            link,
            equals('otzaria://open/pdf/$bookId?index=$page'),
            reason: 'bookId=$bookId, page=$page',
          );
        }
      }
    });

    test('Property: ערכי page < 1 מוחלפים ב-1', () {
      for (int bookId = 1; bookId <= 20; bookId++) {
        for (final badPage in [0, -1, -5, -100, -9999]) {
          final link = buildPdfPageLink(bookId, badPage);
          expect(
            link,
            equals('otzaria://open/pdf/$bookId?index=1'),
            reason: 'bookId=$bookId, page=$badPage',
          );
        }
      }
    });

    test('Property: הקישור תמיד מכיל ?index= עם max(1,page)', () {
      for (int bookId = 1; bookId <= 30; bookId++) {
        for (int page = -5; page <= 50; page += 5) {
          final link = buildPdfPageLink(bookId, page);
          final expectedPage = page < 1 ? 1 : page;
          expect(
            link,
            equals('otzaria://open/pdf/$bookId?index=$expectedPage'),
            reason: 'bookId=$bookId, page=$page',
          );
        }
      }
    });
  });

  group('copy-direct-link — buildSectionLink', () {
    test('מחזיר פורמט נכון עבור bookId=1, index=0', () {
      expect(buildSectionLink(1, 0), equals('otzaria://open/book/1?index=0'));
    });

    test('מחזיר פורמט נכון עבור bookId=42, index=100', () {
      expect(
        buildSectionLink(42, 100),
        equals('otzaria://open/book/42?index=100'),
      );
    });

    test('edge case: index שלילי מוחלף ב-0', () {
      expect(buildSectionLink(1, -1), equals('otzaria://open/book/1?index=0'));
      expect(
        buildSectionLink(5, -100),
        equals('otzaria://open/book/5?index=0'),
      );
    });

    // Property 2: פורמט קישור מקטע — Validates: Requirements 1.6, 2.6, 3.2, 3.4
    test('Property 2: ערכי index אי-שליליים', () {
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

    test('Property 2: הקישור תמיד מכיל ?index= עם max(0,index)', () {
      for (int bookId = 1; bookId <= 30; bookId++) {
        for (int index = -5; index <= 50; index += 5) {
          final link = buildSectionLink(bookId, index);
          final expectedIndex = index < 0 ? 0 : index;
          expect(
            link,
            equals('otzaria://open/book/$bookId?index=$expectedIndex'),
            reason: 'bookId=$bookId, index=$index',
          );
        }
      }
    });
  });

  group('copy-direct-link — buildSectionMarkLink', () {
    // Property 2: פורמט קישור הדגשת מקטע — Validates: Requirements 4.3
    test('Property 2: פורמט קישור הדגשת מקטע — 100+ איטרציות', () {
      for (int bookId = 1; bookId <= 100; bookId++) {
        for (int index = 0; index <= 100; index += 10) {
          final link = buildSectionMarkLink(bookId, index);
          expect(
            link,
            equals('otzaria://open/book/$bookId?index=$index&mark'),
            reason: 'bookId=$bookId, index=$index',
          );
        }
      }
    });

    test('edge case: index=0', () {
      expect(
        buildSectionMarkLink(1, 0),
        equals('otzaria://open/book/1?index=0&mark'),
      );
    });

    test('edge case: bookId=42, index=100', () {
      expect(
        buildSectionMarkLink(42, 100),
        equals('otzaria://open/book/42?index=100&mark'),
      );
    });

    // Property 5: index שלילי ב-buildSectionMarkLink מוחלף ב-0 — Validates: Requirements 4.3 (edge-case)
    test('Property 5: index שלילי מוחלף ב-0', () {
      for (int bookId = 1; bookId <= 20; bookId++) {
        for (final negIndex in [-1, -5, -100, -9999]) {
          final link = buildSectionMarkLink(bookId, negIndex);
          expect(
            link,
            equals('otzaria://open/book/$bookId?index=0&mark'),
            reason: 'bookId=$bookId, index=$negIndex',
          );
        }
      }
    });
  });

  group('copy-direct-link — buildTextMarkLink', () {
    // Property 3: פורמט קישור הדגשת טקסט עם קידוד URL — Validates: Requirements 5.3, 5.4
    test('Property 3: קידוד URL בקישור הדגשת טקסט — 100+ איטרציות', () {
      for (int bookId = 1; bookId <= 50; bookId++) {
        for (int index = 0; index <= 50; index += 5) {
          final link = buildTextMarkLink(bookId, index, 'בראשית');
          expect(link, isNotNull, reason: 'bookId=$bookId, index=$index');
          expect(
            link!,
            contains('?index=$index&m='),
            reason: 'bookId=$bookId, index=$index',
          );
          expect(
            link,
            contains('%D7%91'),
            reason: 'ב מקודד — bookId=$bookId, index=$index',
          );
        }
      }
    });

    test('מחזיר קישור עם קידוד URL לטקסט עברי', () {
      final link = buildTextMarkLink(1, 0, 'בראשית');
      expect(link, isNotNull);
      expect(link!, contains('&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA'));
    });

    test('מחזיר קישור עם קידוד URL לטקסט עם רווחים', () {
      final link = buildTextMarkLink(1, 5, 'בראשית ברא');
      expect(link, isNotNull);
      expect(link!, startsWith('otzaria://open/book/1?index=5&m='));
    });

    // Property 4: טקסט ריק מחזיר null — Validates: Requirements 5.5
    test('Property 4: טקסט ריק מחזיר null', () {
      for (final emptyText in ['', ' ', '   ', '\t', '\n', '\r\n']) {
        expect(
          buildTextMarkLink(1, 0, emptyText),
          isNull,
          reason:
              'text="${emptyText.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}"',
        );
      }
    });

    // Property 6: index שלילי ב-buildTextMarkLink מוחלף ב-0 — Validates: Requirements 5.4 (edge-case)
    test('Property 6: index שלילי מוחלף ב-0', () {
      for (int bookId = 1; bookId <= 20; bookId++) {
        for (final negIndex in [-1, -5, -100]) {
          final link = buildTextMarkLink(bookId, negIndex, 'טקסט');
          expect(link, isNotNull, reason: 'bookId=$bookId, index=$negIndex');
          expect(
            link!,
            contains('?index=0&m='),
            reason: 'bookId=$bookId, index=$negIndex',
          );
        }
      }
    });
  });

  group('copy-direct-link — buildDirectLinkSubmenuEntries', () {
    // Property 1: מספר אפשרויות בתת-תפריט — הקישור לספר עבר לתפריט "אפשרויות
    // נוספות" בסרגל העליון, ולכן כאן יש מקטע/הדגשת מקטע (+הדגשת טקסט אם סומן).
    test('Property 1: 2 אפשרויות ללא טקסט מסומן', () {
      final entries = buildDirectLinkSubmenuEntries(
        bookId: 1,
        index: 0,
        selectedText: null,
      );
      expect(entries.length, equals(2));
    });

    test('Property 1: 2 אפשרויות עם טקסט ריק', () {
      final entries = buildDirectLinkSubmenuEntries(
        bookId: 1,
        index: 0,
        selectedText: '',
      );
      expect(entries.length, equals(2));
    });

    test('Property 1: 2 אפשרויות עם טקסט רווחים בלבד', () {
      final entries = buildDirectLinkSubmenuEntries(
        bookId: 1,
        index: 0,
        selectedText: '   ',
      );
      expect(entries.length, equals(2));
    });

    test('Property 1: 3 אפשרויות עם טקסט מסומן לא-ריק', () {
      final entries = buildDirectLinkSubmenuEntries(
        bookId: 1,
        index: 0,
        selectedText: 'בראשית',
      );
      expect(entries.length, equals(3));
    });

    test('כל הקישורים ברשימה מכילים את אותו index', () {
      const bookId = 42;
      const index = 17;
      final entries = buildDirectLinkSubmenuEntries(
        bookId: bookId,
        index: index,
        selectedText: 'טקסט',
      );
      for (final entry in entries) {
        if (entry.link != null && entry.link!.contains('?')) {
          expect(
            entry.link!,
            contains('index=$index'),
            reason: 'label=${entry.label}',
          );
        }
      }
    });

    test('הקישור הראשון הוא קישור למקטע עם index', () {
      final entries = buildDirectLinkSubmenuEntries(
        bookId: 5,
        index: 10,
        selectedText: null,
      );
      expect(entries.first.link, equals('otzaria://open/book/5?index=10'));
    });
  });
}
