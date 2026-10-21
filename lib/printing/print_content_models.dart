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

/// איך בלוק בעל צבע מודפס: [filled] — על רקע בצבע, [detail] — שורת פרטים
/// קטנה, [body] — טקסט רגיל. לכולם פס בצבע בצד, כך שבלוקים רצופים נראים יחד.
enum PrintAccentStyle { filled, detail, body }

class PrintAccent {
  final int argb;
  final PrintAccentStyle style;

  const PrintAccent(this.argb, this.style);
}

class PrintBlock {
  final PrintBlockKind kind;
  final String text;
  final int? headingLevel;
  final List<PrintFootnote> footnotes;
  final PrintAccent? accent;

  const PrintBlock({
    required this.kind,
    required this.text,
    this.headingLevel,
    this.footnotes = const [],
    this.accent,
  });

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'text': text,
      'headingLevel': headingLevel,
      'footnotes': footnotes.map((footnote) => footnote.toJson()).toList(),
      if (accent case final accent?) ...{
        'accent': accent.argb,
        'accentStyle': accent.style.name,
      },
    };
  }

  factory PrintBlock.fromJson(Map<String, Object?> json) {
    final footnotesJson = json['footnotes'] as List<dynamic>? ?? const [];
    final accent = json['accent'];
    return PrintBlock(
      kind: PrintBlockKind.values.byName(json['kind']! as String),
      text: json['text'] as String? ?? '',
      headingLevel: json['headingLevel'] as int?,
      footnotes: footnotesJson
          .whereType<Map<String, Object?>>()
          .map(PrintFootnote.fromJson)
          .toList(growable: false),
      accent: accent is int
          ? PrintAccent(
              accent,
              PrintAccentStyle.values.asNameMap()[json['accentStyle']] ??
                  PrintAccentStyle.body,
            )
          : null,
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
