import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/pdf_anchor_cache_entry.dart';

void main() {
  group('PdfAnchorCacheEntry', () {
    test('קידוד ופענוח roundtrip משמרים את העוגנים', () {
      final anchors = [
        (page: 3, ref: 'דף ב/עמוד א'),
        (page: 4, ref: 'דף ב/עמוד ב'),
        (page: 120, ref: 'הדרן'),
      ];

      final decoded = PdfAnchorCacheEntry.decode(
        PdfAnchorCacheEntry.encode(anchors),
      );

      expect(decoded, anchors);
    });

    test('רשימה ריקה עוברת roundtrip', () {
      expect(
        PdfAnchorCacheEntry.decode(PdfAnchorCacheEntry.encode(const [])),
        isEmpty,
      );
    });

    test('גרסת סכמה לא תואמת זורקת FormatException', () {
      final stale = jsonEncode({
        'v': PdfAnchorCacheEntry.currentSchemaVersion + 1,
        'anchors': const [],
      });

      expect(
        () => PdfAnchorCacheEntry.decode(stale),
        throwsFormatException,
      );
    });

    test('מבנה פגום זורק FormatException', () {
      expect(
        () => PdfAnchorCacheEntry.decode('[]'),
        throwsFormatException,
      );
      expect(
        () => PdfAnchorCacheEntry.decode('{"v": 1, "anchors": "לא רשימה"}'),
        throwsFormatException,
      );
    });

    test('פריט עוגן פגום זורק FormatException', () {
      expect(
        () => PdfAnchorCacheEntry.decode('{"v": 1, "anchors": [5]}'),
        throwsFormatException,
      );
      expect(
        () => PdfAnchorCacheEntry.decode(
          '{"v": 1, "anchors": [{"p": "לא מספר", "r": "דף ב"}]}',
        ),
        throwsFormatException,
      );
      expect(
        () => PdfAnchorCacheEntry.decode('{"v": 1, "anchors": [{"p": 3}]}'),
        throwsFormatException,
      );
    });

    test('decodeAnchors פועל על רשומה מלאה', () {
      final entry = PdfAnchorCacheEntry(
        filePath: r'C:\books\ברכות.pdf',
        fileSize: 1000,
        lastModified: 123456,
        anchorsJson: PdfAnchorCacheEntry.encode([(page: 7, ref: 'דף ג')]),
        createdAt: 1,
        accessedAt: 2,
      );

      expect(entry.decodeAnchors(), [(page: 7, ref: 'דף ג')]);
    });
  });
}
