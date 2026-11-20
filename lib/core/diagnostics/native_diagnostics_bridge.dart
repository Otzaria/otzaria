import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// FFI לפונקציות שה-runner של Windows מייצא (`crash_record.cpp`,
/// `accessibility_probe.cpp`). מחוץ ל-runner אין מופע.
class NativeDiagnosticsBridge {
  NativeDiagnosticsBridge._(this._setContext, this._firstAccessibilityRequest);

  /// null כשהפונקציות אינן זמינות.
  static final NativeDiagnosticsBridge? instance = _load();

  /// גודל החוצץ ב-`CrashWerContext::context`, כולל התו המסיים.
  static const int maxContextBytes = 255;

  final void Function(Pointer<Uint8>, int) _setContext;
  final int Function(Pointer<Int64>) _firstAccessibilityRequest;
  final Pointer<Uint8> _buffer = malloc<Uint8>(maxContextBytes);

  static NativeDiagnosticsBridge? _load() {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final exe = DynamicLibrary.executable();
      if (!exe.providesSymbol('OtzariaSetDiagnosticContext') ||
          !exe.providesSymbol('OtzariaFirstAccessibilityRequest')) {
        return null;
      }
      return NativeDiagnosticsBridge._(
        exe.lookupFunction<
          Void Function(Pointer<Uint8>, Int32),
          void Function(Pointer<Uint8>, int)
        >('OtzariaSetDiagnosticContext', isLeaf: true),
        exe.lookupFunction<
          Int32 Function(Pointer<Int64>),
          int Function(Pointer<Int64>)
        >('OtzariaFirstAccessibilityRequest', isLeaf: true),
      );
    } catch (_) {
      return null;
    }
  }

  /// מעתיק את [context] לחוצץ שרשומות התקיעה והקריסה קוראות.
  void setContext(String context) {
    final bytes = encodeContext(context);
    _buffer.asTypedList(maxContextBytes).setRange(0, bytes.length, bytes);
    _setContext(_buffer, bytes.length);
  }

  /// בקשת הנגישות הראשונה שהגיעה לתצוגה: `uia` / `msaa` והזמן מההפעלה.
  ({String kind, int msSinceLaunch})? firstAccessibilityRequest() {
    final ms = calloc<Int64>();
    try {
      final kind = _firstAccessibilityRequest(ms);
      return switch (kind) {
        1 => (kind: 'uia', msSinceLaunch: ms.value),
        2 => (kind: 'msaa', msSinceLaunch: ms.value),
        _ => null,
      };
    } finally {
      calloc.free(ms);
    }
  }

  /// UTF-8 בשורה אחת, קטוע בגבול תו עד [maxContextBytes].
  @visibleForTesting
  static Uint8List encodeContext(String context) {
    final bytes = utf8.encode(context.replaceAll(RegExp(r'[\r\n]+'), ' '));
    if (bytes.length <= maxContextBytes) return bytes;
    var end = maxContextBytes;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return Uint8List.sublistView(bytes, 0, end);
  }
}
