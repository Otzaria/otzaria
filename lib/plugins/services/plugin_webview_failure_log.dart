import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart'
    show WindowsWebViewHwndFallback;
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/services/windows_arch_info.dart';

/// override לבדיקות בלבד: כתיבה לקובץ גם ב-debug (ברירת המחדל שם היא הדפסה).
@visibleForTesting
bool debugForcePluginWebViewFailureFileLog = false;

/// רישום כשלי שכבת ה-WebView של התוספים ל-errors.txt (best-effort).
///
/// כשלים אלה מסתיימים אצל המשתמש במסך ריק בלי שום עקבות — הרישום כאן הוא
/// הדרך היחידה לאבחן אותם מרחוק. ב-debug מודפס לקונסול בלבד.
/// [creationFailure] מוסיף ברקע אבחון של סביבת WebView2 (Windows בלבד).
void logPluginWebViewFailure(
  String title,
  Object error, {
  StackTrace? stackTrace,
  Map<String, String?> details = const {},
  bool creationFailure = false,
}) {
  if (kDebugMode && !debugForcePluginWebViewFailureFileLog) {
    debugPrint('Plugin WebView failure [$title]: $error');
    return;
  }
  try {
    ErrorLogFile.appendInBackground(
      title: title,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  } catch (_) {}
  if (creationFailure) WebView2CreationDiagnostics.recordCreationFailure(error);
}

bool _hwndFallbackLogged = false;

@visibleForTesting
void debugResetPluginWebViewHwndFallbackLog() => _hwndFallbackLogged = false;

/// רושם פעם אחת לתהליך שתוסף עלה במצב HWND כי ה-composition נכשל (התוסף עובד,
/// ואין לכך סימן אחר). נסיגה לא כפויה מריצה גם את [WebView2CreationDiagnostics].
void logPluginWebViewHwndFallback(WindowsWebViewHwndFallback fallback) {
  if (_hwndFallbackLogged) return;
  _hwndFallbackLogged = true;
  logPluginWebViewFailure(
    'Plugin WebView HWND fallback',
    'WebView composition hosting failed at ${fallback.stage} '
        '(HRESULT ${fallback.hresultHex ?? 'n/a'}); using HWND mode',
    details: {
      'Stage': fallback.stage,
      'HRESULT': fallback.hresultHex,
      'RequestedUrl': fallback.requestedUrl,
      'EmulatedOnArm': WindowsArchInfo.isEmulatedOnArm ? 'true' : 'false',
    },
    creationFailure: fallback.stage != 'forced',
  );
}
