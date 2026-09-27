/// ההחלטות נשענות על הקוד ולא על טקסט ההודעה. מחוץ ל-`native/` בכוונה,
/// כדי ששכבת הספק והממשק לא ייבאו את מודול ה-Win32 בשביל enum.
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
