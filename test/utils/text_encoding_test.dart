import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/text_encoding.dart';

void main() {
  group('decodeTextBytesSmart', () {
    test('קובץ ריק', () {
      expect(decodeTextBytesSmart(Uint8List(0)), '');
    });

    test('UTF-8 רגיל', () {
      final bytes = Uint8List.fromList(utf8.encode('שלום עולם'));
      expect(decodeTextBytesSmart(bytes), 'שלום עולם');
    });

    test('UTF-8 עם BOM', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('בראשית'),
      ]);
      expect(decodeTextBytesSmart(bytes), 'בראשית');
    });

    test('Windows-1255 — אותיות עבריות', () {
      // "שלום" ב-cp1255: ש=0xF9 ל=0xEC ו=0xE5 ם=0xED
      final bytes = Uint8List.fromList([0xF9, 0xEC, 0xE5, 0xED]);
      expect(decodeTextBytesSmart(bytes), 'שלום');
    });

    test('Windows-1255 — עברית עם ASCII וסימני פיסוק', () {
      // "דעת תורה, פרק א." — אותיות cp1255 ורווחים/פיסוק ASCII
      final bytes = Uint8List.fromList([
        0xE3, 0xF2, 0xFA, 0x20, // דעת
        0xFA, 0xE5, 0xF8, 0xE4, 0x2C, 0x20, // תורה,
        0xF4, 0xF8, 0xF7, 0x20, 0xE0, 0x2E, // פרק א.
      ]);
      expect(decodeTextBytesSmart(bytes), 'דעת תורה, פרק א.');
    });

    test('Windows-1255 — ניקוד וגרשיים', () {
      // קמץ=0xC8→U+05B8, גרש=0xD7→U+05F3, גרשיים=0xD8→U+05F4
      final bytes = Uint8List.fromList([0xE0, 0xC8, 0xD7, 0xD8]);
      expect(decodeTextBytesSmart(bytes), 'אָ׳״');
    });

    test('UTF-16LE עם BOM', () {
      final content = 'חומש ויקרא';
      final bytes = BytesBuilder()..add([0xFF, 0xFE]);
      for (final unit in content.codeUnits) {
        bytes.add([unit & 0xFF, unit >> 8]);
      }
      expect(decodeTextBytesSmart(bytes.toBytes()), content);
    });

    test('UTF-16BE עם BOM', () {
      final content = 'מוסר';
      final bytes = BytesBuilder()..add([0xFE, 0xFF]);
      for (final unit in content.codeUnits) {
        bytes.add([unit >> 8, unit & 0xFF]);
      }
      expect(decodeTextBytesSmart(bytes.toBytes()), content);
    });

    test('UTF-16LE בלי BOM — היוריסטיקת יחידות קוד', () {
      final content = 'ספר בדיקה ארוך מספיק כדי שההיוריסטיקה תעבוד';
      final bytes = BytesBuilder();
      for (final unit in content.codeUnits) {
        bytes.add([unit & 0xFF, unit >> 8]);
      }
      expect(decodeTextBytesSmart(bytes.toBytes()), content);
    });

    test('ASCII טהור נשאר כמו שהוא', () {
      final bytes = Uint8List.fromList('hello world'.codeUnits);
      expect(decodeTextBytesSmart(bytes), 'hello world');
    });
  });
}
