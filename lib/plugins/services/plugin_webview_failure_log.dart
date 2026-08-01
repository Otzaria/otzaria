import 'package:flutter/foundation.dart';
import 'package:otzaria/core/error_log_file.dart';

/// override לבדיקות בלבד: כתיבה לקובץ גם ב-debug (ברירת המחדל שם היא הדפסה).
@visibleForTesting
bool debugForcePluginWebViewFailureFileLog = false;

/// רישום כשלי שכבת ה-WebView של התוספים ל-errors.txt (best-effort).
///
/// כשלים אלה מסתיימים אצל המשתמש במסך ריק בלי שום עקבות — הרישום כאן הוא
/// הדרך היחידה לאבחן אותם מרחוק. ב-debug מודפס לקונסול בלבד.
void logPluginWebViewFailure(
  String title,
  Object error, {
  StackTrace? stackTrace,
  Map<String, String?> details = const {},
}) {
  if (kDebugMode && !debugForcePluginWebViewFailureFileLog) {
    debugPrint('Plugin WebView failure [$title]: $error');
    return;
  }
  try {
    ErrorLogFile.append(
      title: title,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  } catch (_) {}
}
