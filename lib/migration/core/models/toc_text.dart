/// Represents a text used in table of contents entries.
class TocText {
  /// The unique identifier of the TOC text.
  final int id;

  /// The content of the TOC text.
  final String text;

  const TocText({
    this.id = 0,
    required this.text,
  });

  /// Creates a TocText instance from a map (e.g., a database row).
  factory TocText.fromMap(Map<String, dynamic> map) {
    return TocText(
      id: map['id'] as int,
      text: map['text'] as String,
    );
  }

  /// Creates a TocText instance from JSON.
  factory TocText.fromJson(Map<String, dynamic> json) {
    return TocText(
      id: json['id'] as int? ?? 0,
      text: json['text'] as String,
    );
  }

  /// Converts the TocText to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
    };
  }

  TocText copyWith({
    int? id,
    String? text,
  }) {
    return TocText(
      id: id ?? this.id,
      text: text ?? this.text,
    );
  }

  @override
  String toString() => 'TocText(id: $id, text: "$text")';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TocText && other.id == id && other.text == text;
  }

  @override
  int get hashCode => id.hashCode ^ text.hashCode;
}
