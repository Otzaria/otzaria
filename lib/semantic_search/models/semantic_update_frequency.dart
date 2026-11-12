/// מתי נתוני החיפוש החכם מתעדכנים ברקע אחרי עדכון ספרייה.
///
/// התדירות חלה רק על מעקב אחרי גרסת הספרייה. תיקון סט פגום והחלפת מודל
/// רצים תמיד, וגם "עדכן עכשיו" עוקף אותה.
enum SemanticUpdateFrequency {
  withLibrary('library'),
  monthly('monthly'),
  manual('manual');

  const SemanticUpdateFrequency(this.storageValue);

  /// הערך הנשמר ב-Settings.
  final String storageValue;

  /// ערך שמור לא מוכר נופל ל-[withLibrary], ההתנהגות שלפני ההגדרה.
  static SemanticUpdateFrequency fromStorage(String? value) =>
      values.firstWhere(
        (frequency) => frequency.storageValue == value,
        orElse: () => withLibrary,
      );
}

/// האם עדכון רקע של הנתונים לגרסת ספרייה חדשה מותר כעת.
///
/// [lastUpdate] הוא מועד ההתקנה המוצלחת האחרונה של וקטורים (null = לא ידוע).
bool isSemanticRoutineUpdateDue({
  required SemanticUpdateFrequency frequency,
  required DateTime? lastUpdate,
  required DateTime now,
}) {
  switch (frequency) {
    case SemanticUpdateFrequency.withLibrary:
      return true;
    case SemanticUpdateFrequency.manual:
      return false;
    case SemanticUpdateFrequency.monthly:
      if (lastUpdate == null) return true;
      final elapsed = now.difference(lastUpdate);
      // שעון שהוזז אחורה אסור שיחסום עדכונים לתמיד.
      return elapsed.isNegative || elapsed >= const Duration(days: 30);
  }
}
