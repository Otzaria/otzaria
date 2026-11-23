import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// ביטול ייצוא שניתן לבדוק גם מתוך callback סינכרוני ב-worker.
class PdfExportCancellationToken {
  Pointer<Bool>? _flag;
  var _leases = 0;
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _flag?.value = true;
  }

  /// מחזיק את הדגל עד סיום ה-worker; יש לשחרר ב-finally אחרי ה-await.
  PdfExportCancellationLease acquire() {
    if (_cancelled) throw const PdfExportCancelledException();
    final flag = _flag ??= calloc<Bool>();
    _leases++;
    return PdfExportCancellationLease._(this, flag.address);
  }

  /// ביטול אינו משחרר כתובת ש-worker עדיין קורא ממנה.
  void dispose() => cancel();

  void _release() {
    if (--_leases == 0) {
      calloc.free(_flag!);
      _flag = null;
    }
  }

  /// הכתובת תקפה רק כל עוד ה-lease המקורי חי; אפס מציין שאין ביטול.
  static bool isCancelledAt(int address) =>
      address != 0 && Pointer<Bool>.fromAddress(address).value;

  static void throwIfCancelledAt(int address) {
    if (isCancelledAt(address)) throw const PdfExportCancelledException();
  }
}

class PdfExportCancellationLease {
  PdfExportCancellationLease._(this._token, this._address);

  PdfExportCancellationToken? _token;
  final int _address;

  int get address {
    if (_token == null) throw StateError('The PDF export lease was released.');
    return _address;
  }

  void dispose() {
    final token = _token;
    _token = null;
    token?._release();
  }
}

class PdfExportCancelledException implements Exception {
  const PdfExportCancelledException();

  @override
  String toString() => 'PDF export cancelled.';
}
