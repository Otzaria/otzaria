import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text_with_inline_links.dart';

void main() {
  group('Inline Links Tests', () {
    test('adds single link to text', () {
      final text = 'זה טקסט לדוגמה עם קישור בתוכו';
      final link = Link(
        heRef: 'בראשית א, א',
        index1: 1,
        path2: 'בראשית.txt',
        index2: 1,
        connectionType: 'reference',
        start: 23,
        end: 29,
      );

      final result = addInlineLinksToText(text, [link]);

      expect(result, contains('<a href='));
      expect(result, contains('otzaria://inline-link'));
      expect(result, contains('קישור'));
      expect(result, contains('</a>'));
    });

    test('adds multiple links to text', () {
      final text = 'ראשון שני שלישי';
      final links = [
        Link(
          heRef: 'בראשית',
          index1: 1,
          path2: 'בראשית.txt',
          index2: 1,
          connectionType: 'reference',
          start: 0,
          end: 5,
        ),
        Link(
          heRef: 'שמות',
          index1: 1,
          path2: 'שמות.txt',
          index2: 1,
          connectionType: 'reference',
          start: 6,
          end: 9,
        ),
      ];

      final result = addInlineLinksToText(text, links);

      expect(result.split('<a href=').length - 1, equals(2));
    });

    test('ignores links without start/end', () {
      final text = 'טקסט רגיל';
      final link = Link(
        heRef: 'בראשית',
        index1: 1,
        path2: 'בראשית.txt',
        index2: 1,
        connectionType: 'reference',
      );

      final result = addInlineLinksToText(text, [link]);

      expect(result, equals(text));
      expect(result, isNot(contains('<a href=')));
    });

    test('returns text as-is when it already contains inline links', () {
      final text =
          'טקסט עם <a href="otzaria://inline-link?path=test">קישור</a> קיים';
      final link = Link(
        heRef: 'בראשית',
        index1: 1,
        path2: 'בראשית.txt',
        index2: 1,
        connectionType: 'reference',
        start: 0,
        end: 5,
      );

      final result = addInlineLinksToText(text, [link]);

      expect(result, equals(text));
    });

    test('handles overlapping links', () {
      final text = 'טקסט ארוך עם קישורים';
      final links = [
        Link(
          heRef: 'ראשון',
          index1: 1,
          path2: 'ספר1.txt',
          index2: 1,
          connectionType: 'reference',
          start: 0,
          end: 10,
        ),
        Link(
          heRef: 'שני',
          index1: 1,
          path2: 'ספר2.txt',
          index2: 1,
          connectionType: 'reference',
          start: 5,
          end: 15,
        ),
      ];

      final result = addInlineLinksToText(text, links);

      // רק הקישור הראשון צריך להתווסף
      expect(result.split('<a href=').length - 1, equals(1));
    });

    test('preserves existing content when adding links', () {
      final text = 'טקסט רגיל עם תוכן';
      final link = Link(
        heRef: 'בראשית',
        index1: 1,
        path2: 'בראשית.txt',
        index2: 1,
        connectionType: 'reference',
        start: 13,
        end: 17,
      );

      final result = addInlineLinksToText(text, [link]);

      // הטקסט המקורי צריך להישמר
      expect(result, contains('טקסט רגיל'));
      // הקישור צריך להתווסף
      expect(result, contains('<a href='));
      expect(result, contains('otzaria://inline-link'));
      // המילה שהקישור אמור לכסות
      expect(result, contains('</a>'));
    });

    test('validates link positions', () {
      final text = 'טקסט קצר';
      final invalidLinks = [
        Link(
          heRef: 'לא תקין',
          index1: 1,
          path2: 'ספר.txt',
          index2: 1,
          connectionType: 'reference',
          start: -1,
          end: 5,
        ),
        Link(
          heRef: 'מחוץ לטווח',
          index1: 1,
          path2: 'ספר.txt',
          index2: 1,
          connectionType: 'reference',
          start: 0,
          end: 100,
        ),
        Link(
          heRef: 'הפוך',
          index1: 1,
          path2: 'ספר.txt',
          index2: 1,
          connectionType: 'reference',
          start: 10,
          end: 5,
        ),
      ];

      final result = addInlineLinksToText(text, invalidLinks);

      // כל הקישורים הלא תקינים צריכים להידלג
      expect(result, equals(text));
    });
  });
}
