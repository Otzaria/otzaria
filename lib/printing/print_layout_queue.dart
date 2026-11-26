import 'dart:async';

import 'pdf_export_cancellation.dart';

/// פריסת ספר מלא ל-PDF אחת בכל התהליך: כל פריסה היא isolate עם הספר כולו בזיכרון.
class PrintLayoutQueue {
  PrintLayoutQueue._();

  static Future<void>? _tail;

  /// מסתיים כשהפריסות שבתור הסתיימו.
  static Future<void>? get idle => _tail;

  /// מריץ את [layout] אחרי הפריסות הקודמות; אם [isCancelled] נכון כשהגיע תורו,
  /// הפריסה אינה מתחילה ונזרק [PdfExportCancelledException].
  static Future<T> run<T>(
    Future<T> Function() layout, {
    required bool Function() isCancelled,
  }) async {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    try {
      if (previous != null) await previous;
      if (isCancelled()) throw const PdfExportCancelledException();
      return await layout();
    } finally {
      if (identical(_tail, completer.future)) _tail = null;
      completer.complete();
    }
  }
}
