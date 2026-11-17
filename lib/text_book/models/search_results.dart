class TextSearchResult {
  final String snippet;
  final int index;
  final String query;
  final String address;

  /// היסט ההופעה בתוך השורה הנקייה — מבחין בין כמה הופעות באותה שורה
  /// לצורך גלילה מדויקת. null בתוצאות ממנוע החיפוש, שאינו מוסר מיקום.
  final int? matchOffset;

  /// היסט ההופעה הראשונה בקבוצת ההקשר בשורה; null בתוצאות ללא קיבוץ מפורש.
  final int? snippetGroupOffset;

  /// אורך השורה הנקייה, בקואורדינטות של [matchOffset]. מאפשר לגלול אל ההופעה
  /// גם כשתוכן הספר שוחרר מהזיכרון ואינו זמין לחישוב.
  final int? lineLength;

  /// ההתאמה מתחילה בסוף השורה [index] ונמשכת בתחילת השורה הבאה.
  final bool continuesToNextLine;

  TextSearchResult({
    required this.snippet,
    required this.index,
    required this.query,
    required this.address,
    this.matchOffset,
    this.snippetGroupOffset,
    this.lineLength,
    this.continuesToNextLine = false,
  });

  /// רק הופעות מאותה קבוצת מקור חולקות שורה; טקסט זהה אינו מזהה מיקום.
  bool sharesSnippetWith(TextSearchResult previous) =>
      snippetGroupOffset != null &&
      index == previous.index &&
      snippetGroupOffset == previous.snippetGroupOffset;
}
