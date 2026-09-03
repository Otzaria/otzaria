/// ההחלטה שצריך לקבל בסטארטאפ עבור אינדקס החיפוש, בהינתן האם נדרש
/// איפוס ידני, האם עדכון אוטומטי פעיל, והאם נמצאו ספרים לא מאונדקסים.
enum StartupIndexingDecision {
  /// נדרש איפוס וגם עדכון אוטומטי פעיל - לאפס ולהתחיל אינדוקס בלי דיאלוג.
  autoReindexThenStart,

  /// נדרש איפוס אך עדכון אוטומטי כבוי - להציג דיאלוג ולחכות לאישור.
  promptManualReindex,

  /// אין צורך באיפוס, עדכון אוטומטי פעיל ויש ספרים לא מאונדקסים -
  /// להתחיל אינדוקס רגיל.
  startIndexing,

  /// רק לבדוק את סטטוס האינדקס - כשהעדכון האוטומטי כבוי, או שכל
  /// הספרים כבר מאונדקסים ואין עבודה אמיתית להריץ.
  checkIndexStatus,
}

/// מחזירה את ההחלטה לזרימת ה-startup לפי שלושה פרמטרים:
/// [requiresManualReindex] - האם נדרש איפוס ובנייה מחדש של האינדקס.
/// [autoUpdateIndex] - האם המשתמש הפעיל עדכון אינדקס אוטומטי.
/// [hasUnindexedBooks] - האם נמצאו ספרים בני-אינדוקס שאינם באינדקס
/// (השוואה זולה בזיכרון - ראה IndexingRepository.hasUnindexedBooks).
StartupIndexingDecision decideStartupIndexing({
  required bool requiresManualReindex,
  required bool autoUpdateIndex,
  required bool hasUnindexedBooks,
}) {
  if (requiresManualReindex) {
    return autoUpdateIndex
        ? StartupIndexingDecision.autoReindexThenStart
        : StartupIndexingDecision.promptManualReindex;
  }
  return autoUpdateIndex && hasUnindexedBooks
      ? StartupIndexingDecision.startIndexing
      : StartupIndexingDecision.checkIndexStatus;
}
