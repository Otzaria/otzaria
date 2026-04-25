/// טווח שורות שעובד ב-cache (גבולות inclusive).
class ProcessedRange {
  final int startLine;
  final int endLine;

  const ProcessedRange(this.startLine, this.endLine);

  Map<String, dynamic> toJson() => {
        'startLine': startLine,
        'endLine': endLine,
      };

  factory ProcessedRange.fromJson(Map<String, dynamic> json) => ProcessedRange(
        json['startLine'] as int,
        json['endLine'] as int,
      );

  bool contains(int lineIndex) =>
      lineIndex >= startLine && lineIndex <= endLine;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProcessedRange &&
          startLine == other.startLine &&
          endLine == other.endLine;

  @override
  int get hashCode => Object.hash(startLine, endLine);
}
