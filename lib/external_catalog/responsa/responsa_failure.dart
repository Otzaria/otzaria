/// קוד שגיאה יציב של פעולה מול פרויקט השו"ת.
///
/// אוצריא מסתמכת על הקוד, לא על הטקסט: הטקסט הוא הודעה למשתמש והוא
/// משתנה, והקוד הוא מה שקובע איזו הודעה תוצג ומה הצעד הבא המוצע.
///
/// יושב מחוץ לתיקיית `native/` בכוונה. שכבת הספק ומסך ההגדרות צריכות
/// את הקוד כדי לנסח הודעה, ואין להן שום עניין ב-Win32; ייבוא של מודול
/// האוטומציה רק כדי לקרוא enum הוא בדיוק הקשר שמטשטש את הגבול.
enum ResponsaFailure {
  responsaNotRunning,
  citationDialogNotFound,
  resultsNotCleared,
  referenceNotParsed,
  openedWrongBook,
  mdiWindowLimitReached,
  timeout,
  cancelled,
}

/// כשל של פעולת אוטומציה, עם הקשר לאבחון.
class ResponsaAutomationException implements Exception {
  final ResponsaFailure failure;
  final String message;

  /// הקשר לאבחון — למשל `tried` עם כל ההפניות שנוסו.
  final Map<String, Object?> details;

  const ResponsaAutomationException(
    this.failure,
    this.message, [
    this.details = const {},
  ]);

  @override
  String toString() => '${failure.name}: $message';
}
