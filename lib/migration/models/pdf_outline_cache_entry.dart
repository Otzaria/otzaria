import 'dart:convert';

/// רשומת cache מתמשך ל-outline של קובץ PDF חיצוני.
class PdfOutlineCacheEntry {
  /// גרסת הסכמה הנוכחית של מבנה ה-outline המסודר ב-[outlineJson].
  ///
  /// העלאת הערך כאן (בעקבות שינוי שדות/מפתחות במבנה של פריט outline)
  /// גורמת לכך ש-[decodeOutlineEntries] יזרוק `FormatException` על רשומות
  /// שנשמרו בגרסה ישנה. ה-self-healing ב-ReferenceBooksCache תופס את החריגה,
  /// מוחק את הרשומה הישנה ובונה אותה מחדש דרך parser של pdfrx.
  static const int currentSchemaVersion = 1;

  final String filePath;
  final int fileSize;
  final int lastModified;
  final String outlineJson;
  final int createdAt;
  final int accessedAt;

  const PdfOutlineCacheEntry({
    required this.filePath,
    required this.fileSize,
    required this.lastModified,
    required this.outlineJson,
    required this.createdAt,
    required this.accessedAt,
  });

  factory PdfOutlineCacheEntry.fromMap(Map<String, dynamic> map) {
    return PdfOutlineCacheEntry(
      filePath: map['filePath'] as String,
      fileSize: map['fileSize'] as int? ?? 0,
      lastModified: map['lastModified'] as int? ?? 0,
      outlineJson: map['outlineJson'] as String,
      createdAt: map['createdAt'] as int? ?? 0,
      accessedAt: map['accessedAt'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filePath': filePath,
      'fileSize': fileSize,
      'lastModified': lastModified,
      'outlineJson': outlineJson,
      'createdAt': createdAt,
      'accessedAt': accessedAt,
    };
  }

  PdfOutlineCacheEntry copyWith({
    String? filePath,
    int? fileSize,
    int? lastModified,
    String? outlineJson,
    int? createdAt,
    int? accessedAt,
  }) {
    return PdfOutlineCacheEntry(
      filePath: filePath ?? this.filePath,
      fileSize: fileSize ?? this.fileSize,
      lastModified: lastModified ?? this.lastModified,
      outlineJson: outlineJson ?? this.outlineJson,
      createdAt: createdAt ?? this.createdAt,
      accessedAt: accessedAt ?? this.accessedAt,
    );
  }

  /// ממיר את ה-JSON השמור לרשימת outline entries.
  List<(String, String, int)> decodeEntries() =>
      decodeOutlineEntries(outlineJson);

  /// ממיר רשימת outline entries ל-JSON יציב לשמירה ב-DB.
  ///
  /// פורמט: `{"v": <גרסה>, "entries": [{"n": ..., "o": ..., "p": ...}, ...]}`.
  static String encodeOutlineEntries(List<(String, String, int)> entries) {
    return jsonEncode({
      'v': currentSchemaVersion,
      'entries': [
        for (final (normalizedTitle, originalTitle, pageNumber) in entries)
          {
            'n': normalizedTitle,
            'o': originalTitle,
            'p': pageNumber,
          },
      ],
    });
  }

  /// מפענח outline entries מ-JSON שמור.
  ///
  /// תומך בשני פורמטים:
  /// - הפורמט הנוכחי: `{"v": <גרסה>, "entries": [...]}`.
  /// - פורמט legacy מלפני הוספת שדה הגרסה: רשימה בלבד `[...]` — מטופל
  ///   כגרסה 1 בלבד. כש-[currentSchemaVersion] גדול מ-1, רשומות בפורמט
  ///   הזה ייחשבו לא תקפות וייבנו מחדש.
  ///
  /// בכל מקרה של אי-התאמת גרסה או corruption (מעטפה תקפה עם `entries`
  /// שאינו רשימה) נזרק `FormatException`, כך שהקוד הקורא ימחק את הרשומה
  /// ויבנה מחדש מתוך ה-PDF.
  static List<(String, String, int)> decodeOutlineEntries(String outlineJson) {
    final decoded = jsonDecode(outlineJson);

    final List<dynamic> rawEntries;
    if (decoded is List) {
      if (currentSchemaVersion != 1) {
        throw FormatException(
          'Unsupported pdf_outline_cache legacy format (implicit v=1, '
          'expected $currentSchemaVersion)',
        );
      }
      rawEntries = decoded;
    } else if (decoded is Map) {
      final version = decoded['v'];
      if (version is! int || version != currentSchemaVersion) {
        throw FormatException(
          'Unsupported pdf_outline_cache schema version: $version '
          '(expected $currentSchemaVersion)',
        );
      }
      final entries = decoded['entries'];
      if (entries is! List) {
        throw const FormatException(
          'Malformed pdf_outline_cache payload: "entries" is not a list',
        );
      }
      rawEntries = entries;
    } else {
      throw const FormatException(
        'Malformed pdf_outline_cache payload: top-level value is not '
        'a list or object',
      );
    }

    return [
      for (final item in rawEntries)
        if (item is Map)
          (
            item['n'] as String? ?? '',
            item['o'] as String? ?? '',
            item['p'] as int? ?? 0,
          ),
    ];
  }

  @override
  String toString() =>
      'PdfOutlineCacheEntry(filePath: $filePath, fileSize: $fileSize, '
      'lastModified: $lastModified, createdAt: $createdAt, accessedAt: $accessedAt)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PdfOutlineCacheEntry &&
        other.filePath == filePath &&
        other.fileSize == fileSize &&
        other.lastModified == lastModified &&
        other.outlineJson == outlineJson &&
        other.createdAt == createdAt &&
        other.accessedAt == accessedAt;
  }

  @override
  int get hashCode => Object.hash(
    filePath,
    fileSize,
    lastModified,
    outlineJson,
    createdAt,
    accessedAt,
  );
}
