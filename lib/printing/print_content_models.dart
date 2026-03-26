enum PrintBlockKind {
  heading,
  text,
  commentaryTitle,
  commentaryGroupTitle,
  commentary,
}

class PrintFootnote {
  final String text;

  const PrintFootnote({required this.text});

  Map<String, Object?> toJson() {
    return {
      'text': text,
    };
  }

  factory PrintFootnote.fromJson(Map<String, Object?> json) {
    return PrintFootnote(
      text: json['text'] as String? ?? '',
    );
  }
}

class PrintBlock {
  final PrintBlockKind kind;
  final String text;
  final int? headingLevel;
  final List<PrintFootnote> footnotes;

  const PrintBlock({
    required this.kind,
    required this.text,
    this.headingLevel,
    this.footnotes = const [],
  });

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'text': text,
      'headingLevel': headingLevel,
      'footnotes': footnotes.map((footnote) => footnote.toJson()).toList(),
    };
  }

  factory PrintBlock.fromJson(Map<String, Object?> json) {
    final footnotesJson = json['footnotes'] as List<dynamic>? ?? const [];
    return PrintBlock(
      kind: PrintBlockKind.values.byName(json['kind']! as String),
      text: json['text'] as String? ?? '',
      headingLevel: json['headingLevel'] as int?,
      footnotes: footnotesJson
          .whereType<Map<String, Object?>>()
          .map(PrintFootnote.fromJson)
          .toList(growable: false),
    );
  }
}

class PreparedPrintDocument {
  final String bookName;
  final List<PrintBlock> blocks;

  const PreparedPrintDocument({
    required this.bookName,
    required this.blocks,
  });
}
