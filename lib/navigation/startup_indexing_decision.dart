/// ההחלטה שצריך לקבל בסטארטאפ עבור אינדקס החיפוש,
/// בהינתן האם נדרש איפוס ידני והאם עדכון אוטומטי פעיל.
enum StartupIndexingDecision {
  /// נדרש איפוס וגם עדכון אוטומטי פעיל - לאפס ולהתחיל אינדוקס בלי דיאלוג.
  autoReindexThenStart,

  /// נדרש איפוס אך עדכון אוטומטי כבוי - להציג דיאלוג ולחכות לאישור.
  promptManualReindex,

  /// אין צורך באיפוס ועדכון אוטומטי פעיל - להתחיל אינדוקס רגיל.
  startIndexing,

  /// אין צורך באיפוס ועדכון אוטומטי כבוי - רק לבדוק את סטטוס האינדקס.
  checkIndexStatus,
}

/// מחזירה את ההחלטה לזרימת ה-startup לפי שני פרמטרים:
/// [requiresManualReindex] - האם נדרש איפוס ובנייה מחדש של האינדקס.
/// [autoUpdateIndex] - האם המשתמש הפעיל עדכון אינדקס אוטומטי.
StartupIndexingDecision decideStartupIndexing({
  required bool requiresManualReindex,
  required bool autoUpdateIndex,
}) {
  if (requiresManualReindex) {
    return autoUpdateIndex
        ? StartupIndexingDecision.autoReindexThenStart
        : StartupIndexingDecision.promptManualReindex;
  }
  return autoUpdateIndex
      ? StartupIndexingDecision.startIndexing
      : StartupIndexingDecision.checkIndexStatus;
}
