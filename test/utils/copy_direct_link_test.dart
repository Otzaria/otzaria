// בדיקות עבור פיצ'ר copy-direct-link
// Feature: copy-direct-link, Property 1: book link format
// Feature: copy-direct-link, Property 2: section link format

import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/utils/book_link_builder.dart';
import 'package:test/test.dart';

void main() {
  group('copy-direct-link — מקור הספר', () {
    test('ספר משתמש מקבל source=user בכל סוגי הקישורים', () {
      expect(
        buildBookLink(7, source: BookSource.user),
        equals('otzaria://open/book/7?source=user'),
      );
      expect(
        buildSectionLink(7, 3, source: BookSource.user),
        equals('otzaria://open/book/7?source=user&index=3'),
      );
      expect(
        buildPdfPageLink(7, 2, source: BookSource.user),
        equals('otzaria://open/pdf/7?source=user&index=2'),
      );
    });

    test('ברירת המחדל משמרת קישור רשמי ישן', () {
      expect(buildBookLink(7), equals('otzaria://open/book/7'));
    });

    test('מסד מצורף מקבל source=db:<slug> מקודד', () {
      final source = BookSource.attached('my-lib');
      expect(
        buildBookLink(7, source: source),
        equals('otzaria://open/book/7?source=db%3Amy-lib'),
      );
      expect(
        buildSectionLink(7, 3, source: source),
        equals('otzaria://open/book/7?source=db%3Amy-lib&index=3'),
      );
      final parsed = Uri.parse(buildBookLink(7, source: source));
      expect(
        parseBookLinkSourceParam(parsed.queryParameters['source']),
        source,
      );
    });

    test('parseBookLinkSourceParam: ערכים מוכרים, ריק ולא מוכר', () {
      expect(parseBookLinkSourceParam(null), BookSource.official);
      expect(parseBookLinkSourceParam('official'), BookSource.official);
      expect(parseBookLinkSourceParam('USER'), BookSource.user);
      expect(
        parseBookLinkSourceParam('db:ספרייה'),
        BookSource.attached('ספרייה'),
      );
      expect(parseBookLinkSourceParam(''), isNull);
      expect(parseBookLinkSourceParam('db:'), isNull);
      expect(parseBookLinkSourceParam('db:a|b'), isNull);
      expect(parseBookLinkSourceParam('other'), isNull);
    });
  });

  group('copy-direct-link — buildBookLink', () {
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
