/// Mapping between lines and table of contents entries.
class LineTocMapping {
  /// The identifier of the line.
  final int lineId;

  /// The identifier of the table of contents entry.
  final int tocEntryId;

  const LineTocMapping({
    required this.lineId,
    required this.tocEntryId,
  });

  /// Creates a LineTocMapping instance from a map (e.g., a database row).
  factory LineTocMapping.fromMap(Map<String, dynamic> map) {
    return LineTocMapping(
      lineId: map['lineId'] as int,
      tocEntryId: map['tocEntryId'] as int,
    );
  }

  LineTocMapping copyWith({
    int? lineId,
    int? tocEntryId,
  }) {
    return LineTocMapping(
      lineId: lineId ?? this.lineId,
      tocEntryId: tocEntryId ?? this.tocEntryId,
    );
  }

  @override
  String toString() =>
      'LineTocMapping(lineId: $lineId, tocEntryId: $tocEntryId)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LineTocMapping &&
        other.lineId == lineId &&
        other.tocEntryId == tocEntryId;
  }

  @override
  int get hashCode => lineId.hashCode ^ tocEntryId.hashCode;
}
