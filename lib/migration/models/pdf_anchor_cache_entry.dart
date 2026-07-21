import 'dart:convert';

/// רשומת cache מתמשך לעוגני outline של קובץ PDF — הקלט של בניית מיפוי
/// העמודים (טקסט↔PDF) — כדי לחסוך פתיחת קובץ ה-PDF המלא בכל המרה.
class PdfAnchorCacheEntry {
  /// גרסת הסכמה של [anchorsJson]. העלאה (למשל בעקבות שינוי בנירמול ה-ref)
  /// גורמת ל-[decodeAnchors] לזרוק `FormatException` על רשומות ישנות —
  /// הקורא מוחק אותן ובונה מחדש מתוך ה-PDF.
  static const int currentSchemaVersion = 1;

  final String filePath;
  final int fileSize;
  final int lastModified;
  final String anchorsJson;
  final int createdAt;
  final int accessedAt;

  const PdfAnchorCacheEntry({
    required this.filePath,
    required this.fileSize,
    required this.lastModified,
    required this.anchorsJson,
    required this.createdAt,
    required this.accessedAt,
  });

  factory PdfAnchorCacheEntry.fromMap(Map<String, dynamic> map) {
    return PdfAnchorCacheEntry(
      filePath: map['filePath'] as String,
      fileSize: map['fileSize'] as int? ?? 0,
      lastModified: map['lastModified'] as int? ?? 0,
      anchorsJson: map['anchorsJson'] as String,
      createdAt: map['createdAt'] as int? ?? 0,
      accessedAt: map['accessedAt'] as int? ?? 0,
    );
  }

  /// ממיר את ה-JSON השמור לרשימת עוגנים (עמוד + ref מנורמל).
  List<({int page, String ref})> decodeAnchors() => decode(anchorsJson);

  /// מקודד רשימת עוגנים ל-JSON יציב לשמירה ב-DB.
  ///
  /// פורמט: `{"v": <גרסה>, "anchors": [{"p": ..., "r": ...}, ...]}`.
  static String encode(List<({int page, String ref})> anchors) {
    return jsonEncode({
      'v': currentSchemaVersion,
      'anchors': [
        for (final anchor in anchors) {'p': anchor.page, 'r': anchor.ref},
      ],
    });
  }

  /// מפענח עוגנים מ-JSON שמור. זורק `FormatException` על גרסה לא תואמת או
  /// מבנה פגום — כדי שהקורא ימחק את הרשומה ויבנה מחדש מתוך ה-PDF.
  static List<({int page, String ref})> decode(String anchorsJson) {
    final decoded = jsonDecode(anchorsJson);
    if (decoded is! Map) {
      throw const FormatException(
        'Malformed pdf_anchor_cache payload: top-level value is not an object',
      );
    }
    final version = decoded['v'];
    if (version is! int || version != currentSchemaVersion) {
      throw FormatException(
        'Unsupported pdf_anchor_cache schema version: $version '
        '(expected $currentSchemaVersion)',
      );
    }
    final anchors = decoded['anchors'];
    if (anchors is! List) {
      throw const FormatException(
        'Malformed pdf_anchor_cache payload: "anchors" is not a list',
      );
    }
    // פריט או שדה פגומים חייבים לזרוק — רשומה שמפוענחת "בשקט" הייתה מחזירה
    // מיפוי שגוי ועוקפת את ה-self-healing (מחיקה ובנייה מחדש מה-PDF).
    final result = <({int page, String ref})>[];
    for (final item in anchors) {
      if (item is! Map) {
        throw const FormatException(
          'Malformed pdf_anchor_cache payload: anchor item is not an object',
        );
      }
      final page = item['p'];
      final ref = item['r'];
      if (page is! int || ref is! String) {
        throw const FormatException(
          'Malformed pdf_anchor_cache payload: invalid anchor fields',
        );
      }
      result.add((page: page, ref: ref));
    }
    return result;
  }
}
