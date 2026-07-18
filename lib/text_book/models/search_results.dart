class TextSearchResult {
  final String snippet;
  final int index;
  final String query;
  final String address;

  /// היסט ההופעה בתוך השורה הנקייה — מבחין בין כמה הופעות באותה שורה
  /// לצורך גלילה מדויקת. null בתוצאות ממנוע החיפוש, שאינו מוסר מיקום.
  final int? matchOffset;

  TextSearchResult({
    required this.snippet,
    required this.index,
    required this.query,
    required this.address,
    this.matchOffset,
  });
}
