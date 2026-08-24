/// מיקום בגבול grapheme, ולצדו offsets שימושיים למנועים אחרים.
class PluginTextOffset {
  final int grapheme;
  final int codePoint;
  final int utf16;

  const PluginTextOffset({
    required this.grapheme,
    required this.codePoint,
    required this.utf16,
  });

  factory PluginTextOffset.fromJson(Map<String, dynamic> json) {
    final grapheme = json['grapheme'];
    final codePoint = json['codePoint'];
    final utf16 = json['utf16'];
    if (grapheme is! int ||
        codePoint is! int ||
        utf16 is! int ||
        grapheme < 0 ||
        codePoint < 0 ||
        utf16 < 0) {
      throw const FormatException(
        'grapheme, codePoint, and utf16 must be non-negative integers',
      );
    }
    return PluginTextOffset(
      grapheme: grapheme,
      codePoint: codePoint,
      utf16: utf16,
    );
  }

  Map<String, dynamic> toJson() => {
    'grapheme': grapheme,
    'codePoint': codePoint,
    'utf16': utf16,
  };
}

enum PluginTextSourceMapKind {
  identity,
  substitution,
  hidden,
  inserted;

  String get wireName => name;
}

class PluginTextSourceMapSegment {
  final PluginTextOffset sourceStart;
  final PluginTextOffset sourceEnd;
  final PluginTextOffset renderedStart;
  final PluginTextOffset renderedEnd;
  final PluginTextSourceMapKind kind;
  final String? description;

  const PluginTextSourceMapSegment({
    required this.sourceStart,
    required this.sourceEnd,
    required this.renderedStart,
    required this.renderedEnd,
    required this.kind,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'sourceStart': sourceStart.toJson(),
    'sourceEnd': sourceEnd.toJson(),
    'renderedStart': renderedStart.toJson(),
    'renderedEnd': renderedEnd.toJson(),
    'kind': kind.wireName,
    if (description != null) 'description': description,
  };
}

class PluginTextSourceMap {
  final int schemaVersion;
  final String bookId;
  final int sectionIndex;
  final String sourceText;
  final String renderedText;
  final String sourceTextHash;
  final String renderedTextHash;
  final List<PluginTextSourceMapSegment> mappings;

  /// אורכי הגרפמות נשמרים כאן כי `String.characters.length` הוא סריקה מלאה,
  /// ותרגום גבול בודד היה משלם אותה בכל קריאה.
  final int sourceGraphemeLength;
  final int renderedGraphemeLength;

  const PluginTextSourceMap({
    this.schemaVersion = 1,
    required this.bookId,
    required this.sectionIndex,
    required this.sourceText,
    required this.renderedText,
    required this.sourceTextHash,
    required this.renderedTextHash,
    required this.mappings,
    required this.sourceGraphemeLength,
    required this.renderedGraphemeLength,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'bookId': bookId,
    'sectionIndex': sectionIndex,
    'sourceTextHash': sourceTextHash,
    'renderedTextHash': renderedTextHash,
    'mappings': mappings.map((segment) => segment.toJson()).toList(),
  };
}
