import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_content_models.dart';

void main() {
  // ─── PrintFootnote ─────────────────────────────────────────────────────────
  group('PrintFootnote - סריאליזציה', () {
    test('toJson מכיל את השדה text', () {
      const footnote = PrintFootnote(text: 'הערת שוליים');
      expect(footnote.toJson(), {'text': 'הערת שוליים'});
    });

    test('fromJson roundtrip', () {
      const original = PrintFootnote(text: 'בדיקה');
      final restored = PrintFootnote.fromJson(original.toJson());
      expect(restored.text, 'בדיקה');
    });

    test('fromJson עם text חסר → מחזיר מחרוזת ריקה', () {
      final footnote = PrintFootnote.fromJson({});
      expect(footnote.text, '');
    });

    test('fromJson עם text=null → מחזיר מחרוזת ריקה', () {
      final footnote = PrintFootnote.fromJson({'text': null});
      expect(footnote.text, '');
    });

    test('toJson שמירת תווים מיוחדים', () {
      const footnote = PrintFootnote(text: 'a & b < c > d " e \' f');
      final json = footnote.toJson();
      expect(json['text'], 'a & b < c > d " e \' f');
    });
  });

  // ─── PrintBlock - בנייה ────────────────────────────────────────────────────
  group('PrintBlock - בנייה', () {
    test('ברירות מחדל נכונות', () {
      const block = PrintBlock(kind: PrintBlockKind.text, text: 'טקסט');
      expect(block.headingLevel, isNull);
      expect(block.footnotes, isEmpty);
    });

    test('כל ערכי PrintBlockKind נבנים', () {
      for (final kind in PrintBlockKind.values) {
        final block = PrintBlock(kind: kind, text: 'בדיקה');
        expect(block.kind, kind);
      }
    });
  });

  // ─── PrintBlock - toJson ───────────────────────────────────────────────────
  group('PrintBlock - toJson', () {
    test('שמירת kind כ-name', () {
      const block = PrintBlock(kind: PrintBlockKind.heading, text: 'פרק א');
      expect(block.toJson()['kind'], 'heading');
    });

    test('כל ערכי kind נשמרים כ-name נכון', () {
      final expected = {
        PrintBlockKind.heading: 'heading',
        PrintBlockKind.text: 'text',
        PrintBlockKind.commentaryTitle: 'commentaryTitle',
        PrintBlockKind.commentaryGroupTitle: 'commentaryGroupTitle',
        PrintBlockKind.commentary: 'commentary',
      };
      for (final entry in expected.entries) {
        final block = PrintBlock(kind: entry.key, text: 'x');
        expect(
          block.toJson()['kind'],
          entry.value,
          reason: 'kind ${entry.key} שגוי',
        );
      }
    });

    test('שמירת headingLevel', () {
      const block = PrintBlock(
        kind: PrintBlockKind.heading,
        text: 'פרק',
        headingLevel: 2,
      );
      expect(block.toJson()['headingLevel'], 2);
    });

    test('headingLevel=null נשמר כ-null', () {
      const block = PrintBlock(kind: PrintBlockKind.text, text: 'טקסט');
      expect(block.toJson()['headingLevel'], isNull);
    });

    test('footnotes ריק נשמר כרשימה ריקה', () {
      const block = PrintBlock(kind: PrintBlockKind.text, text: 'טקסט');
      expect(block.toJson()['footnotes'], isEmpty);
    });

    test('footnotes נשמרים כרשימת json', () {
      const block = PrintBlock(
        kind: PrintBlockKind.text,
        text: 'טקסט',
        footnotes: [
          PrintFootnote(text: 'הערה 1'),
          PrintFootnote(text: 'הערה 2'),
        ],
      );
      final json = block.toJson();
      final footnotesList = json['footnotes'] as List;
      expect(footnotesList.length, 2);
      expect((footnotesList[0] as Map)['text'], 'הערה 1');
      expect((footnotesList[1] as Map)['text'], 'הערה 2');
    });
  });

  // ─── PrintBlock - fromJson ─────────────────────────────────────────────────
  group('PrintBlock - fromJson', () {
    test('roundtrip בסיסי', () {
      const original = PrintBlock(
        kind: PrintBlockKind.text,
        text: 'פסקה',
        headingLevel: null,
        footnotes: [],
      );
      final restored = PrintBlock.fromJson(original.toJson());
      expect(restored.kind, original.kind);
      expect(restored.text, original.text);
      expect(restored.headingLevel, isNull);
      expect(restored.footnotes, isEmpty);
    });

    test('roundtrip עם headingLevel', () {
      const original = PrintBlock(
        kind: PrintBlockKind.heading,
        text: 'כותרת',
        headingLevel: 3,
      );
      final restored = PrintBlock.fromJson(original.toJson());
      expect(restored.headingLevel, 3);
    });

    test('roundtrip עם footnotes', () {
      const original = PrintBlock(
        kind: PrintBlockKind.text,
        text: 'פסקה',
        footnotes: [
          PrintFootnote(text: 'הערה'),
        ],
      );
      final restored = PrintBlock.fromJson(original.toJson());
      expect(restored.footnotes.length, 1);
      expect(restored.footnotes.first.text, 'הערה');
    });

    test('roundtrip עם מספר footnotes', () {
      const original = PrintBlock(
        kind: PrintBlockKind.text,
        text: 'טקסט',
        footnotes: [
          PrintFootnote(text: 'הערה א'),
          PrintFootnote(text: 'הערה ב'),
          PrintFootnote(text: 'הערה ג'),
        ],
      );
      final restored = PrintBlock.fromJson(original.toJson());
      expect(restored.footnotes.length, 3);
      expect(restored.footnotes[2].text, 'הערה ג');
    });

    test('fromJson ללא footnotes → רשימה ריקה', () {
      final json = {'kind': 'text', 'text': 'פסקה'};
      final block = PrintBlock.fromJson(json);
      expect(block.footnotes, isEmpty);
    });

    test('fromJson ללא text → מחרוזת ריקה', () {
      final json = {'kind': 'text'};
      final block = PrintBlock.fromJson(json);
      expect(block.text, '');
    });

    test('fromJson ללא headingLevel → null', () {
      final json = {'kind': 'heading', 'text': 'כותרת'};
      final block = PrintBlock.fromJson(json);
      expect(block.headingLevel, isNull);
    });

    test('roundtrip כל ערכי PrintBlockKind', () {
      for (final kind in PrintBlockKind.values) {
        final block = PrintBlock(kind: kind, text: 'בדיקה $kind');
        final restored = PrintBlock.fromJson(block.toJson());
        expect(restored.kind, kind, reason: 'kind $kind לא שוחזר');
      }
    });
  });

  // ─── PreparedPrintDocument ─────────────────────────────────────────────────
  group('PreparedPrintDocument - בנייה', () {
    test('שדות נכונים', () {
      const doc = PreparedPrintDocument(
        bookName: 'ספר הבדיקה',
        blocks: [
          PrintBlock(kind: PrintBlockKind.text, text: 'פסקה'),
        ],
      );
      expect(doc.bookName, 'ספר הבדיקה');
      expect(doc.blocks.length, 1);
    });

    test('blocks ריק', () {
      const doc = PreparedPrintDocument(bookName: 'ספר', blocks: []);
      expect(doc.blocks, isEmpty);
    });
  });
}
