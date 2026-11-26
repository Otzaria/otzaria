import 'dart:async';
import 'dart:developer' as developer;

/// ניקוי אינו מחליף כשל פעולה קודמת; כשל ניקוי משני מדווח בנפרד.
Future<T> withPdfFileCleanup<T>(
  FutureOr<T> Function() action,
  FutureOr<void> Function() cleanup,
) async {
  var failed = false;
  try {
    return await action();
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    try {
      await cleanup();
    } catch (error, stack) {
      if (!failed) rethrow;
      _reportCleanup(error, stack);
    }
  }
}

/// אותה מדיניות עבור callbacks סינכרוניים של PdfStream.
T withPdfFileCleanupSync<T>(T Function() action, void Function() cleanup) {
  var failed = false;
  try {
    return action();
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    try {
      cleanup();
    } catch (error, stack) {
      if (!failed) rethrow;
      _reportCleanup(error, stack);
    }
  }
}

void _reportCleanup(Object error, StackTrace stack) {
  developer.log(
    'PDF file cleanup failed after an earlier operation failure.',
    name: 'otzaria.printing',
    level: 1000,
    error: error,
    stackTrace: stack,
  );
}
