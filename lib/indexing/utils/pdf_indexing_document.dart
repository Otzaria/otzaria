import 'dart:async';

import 'package:otzaria/core/error_log_file.dart';
import 'package:pdfrx/pdfrx.dart';

/// פתיחה מוגבלת בזמן שבעלותה נשמרת עד שהמסמך נמסר לצרכן או נסגר.
/// מסמך שנפתח אחרי ביטול או timeout נסגר בלי להתחיל לחלץ ממנו טקסט.
Future<PdfDocument?> openIndexingPdf({
  required Future<PdfDocument> Function() open,
  required bool Function() isCancelled,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (isCancelled()) return null;
  var abandoned = false;
  final ownedOpen = () async {
    final document = await open();
    if (!abandoned && !isCancelled()) return document;
    try {
      await document.dispose();
    } catch (error, stackTrace) {
      if (!abandoned) rethrow;
      ErrorLogFile.append(
        title: 'PDF indexing: late document cleanup failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }();
  return ownedOpen.timeout(
    timeout,
    onTimeout: () {
      abandoned = true;
      throw TimeoutException('PDF indexing: document open timed out', timeout);
    },
  );
}
