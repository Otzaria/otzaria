import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria_zvfs/otzaria_zvfs.dart';

import 'library_zdb_types.dart';

/// תקציב מטמון העמודים המפוענחים לכל קובץ zdb. null — ברירת המחדל של
/// החבילה ([ZVfs.cacheBytesPerFile]); הערך הסופי ייקבע אחרי מדידה.
const int? libraryZdbCacheBytesPerFile = null;

bool _registered = false;
({Object error, StackTrace stackTrace})? _registrationFailure;

/// כשל הרישום ב-isolate הזה, או null.
({Object error, StackTrace stackTrace})? get libraryVfsRegistrationFailure =>
    _registrationFailure;

/// רושם את zvfs כ-VFS ברירת המחדל של התהליך. אידמפוטנטי וזול אחרי הקריאה
/// הראשונה ב-isolate. לא זורק: בלי zvfs מסד seforim.db רגיל עדיין נפתח.
bool ensureLibraryVfs() {
  if (_registered) return true;
  if (_registrationFailure != null) return false;
  try {
    ZVfs.register(
      makeDefault: true,
      cacheBytesPerFile: libraryZdbCacheBytesPerFile,
    );
    _registered = true;
  } catch (error, stackTrace) {
    _registrationFailure = (error: error, stackTrace: stackTrace);
    debugPrint('[library_vfs] zvfs registration failed: $error');
  }
  return _registered;
}

/// האם [path] מתחיל ב-magic של zdb. נתיב פתוח דרך zvfs נענה מהמצב הפתוח.
bool isLibraryZdb(String path) => isZdb(path);

/// האם חיבור כלשהו בתהליך (בכל isolate) מחזיק את [path] פתוח דרך zvfs.
bool isLibraryDbOpenInProcess(String path) => ZVfs.isOpen(path);

/// בתים לוגיים של מסד zdb (בסיס + overlay). סינכרוני ומשחזר את ה-overlay —
/// לא על ה-UI isolate. זורק [ZdbException] כשהקובץ פתוח בתהליך.
Uint8List readLibraryZdbBytes(String path, int offset, int length) =>
    readZdbBytes(path, offset, length);

/// הגודל ש-SQLite רואה במסד zdb. סינכרוני, כמו [readLibraryZdbBytes].
int libraryZdbLogicalSize(String path) => readZdbInfo(path).logicalSize;

/// הגודל ש-SQLite רואה ב-[path]: לוגי ל-zdb, גודל הקובץ לכל מסד אחר.
/// top-level כדי לעבור ל-isolate של ה-applier. סינכרוני.
int libraryDbLogicalSizeOf(String path) {
  if (isZdb(path)) {
    try {
      return libraryZdbLogicalSize(path);
    } on ZdbException catch (error) {
      // משמש למדי התקדמות בלבד; כשל כאן אסור שיפיל את ה-apply.
      debugPrint('[library_vfs] zdb logical size unavailable: $error');
    }
  }
  return File(path).lengthSync();
}

/// הכותרת המאומתת של [path]. סינכרוני ומשחזר overlay — לא על ה-UI isolate.
LibraryZdbHeader readLibraryZdbHeader(String path) => _mapped(() {
  final info = readZdbInfo(path);
  return LibraryZdbHeader(
    formatMajor: info.formatMajor,
    formatMinor: info.formatMinor,
    pageSize: info.pageSize,
    logicalSize: info.logicalSize,
    physicalSize: info.physicalSize,
    dictName: info.dictName,
    dictId: info.dictId,
    level: info.level,
    fileUuidHex: _hexBytes(info.fileUuid),
    contentXxh64Hex: _hex64(info.contentXxh64),
  );
});

/// מפענח כל frame של [path] ובודק את hash התוכן, מחוץ ל-isolate הקורא.
/// [isCancelled] נדגם תוך כדי הפענוח ועוצר אותו (failure=cancelled).
Future<void> verifyLibraryZdbFrames(
  String path, {
  void Function(int bytesDone, int totalBytes)? onProgress,
  bool Function()? isCancelled,
}) => _withProgressPort(
  onProgress,
  isCancelled,
  (report, token) =>
      verifyZdb(path, onProgress: report, cancellationToken: token),
);

/// מתקין את [candidatePath] כבסיס של [path] (ראו `installZdb`).
Future<void> installLibraryZdb(
  String path,
  String candidatePath, {
  bool verify = true,
}) => _mappedAsync(() => installZdb(path, candidatePath, verify: verify));

/// דוחס בסיס + overlay של [path] לבסיס חדש (ראו `compactZdb`).
/// [isCancelled] נדגם תוך כדי ועוצר את הדחיסה לפני ההחלפה (failure=cancelled).
Future<void> compactLibraryZdb(
  String path, {
  void Function(int bytesDone, int totalBytes)? onProgress,
  bool Function()? isCancelled,
}) => _withProgressPort(
  onProgress,
  isCancelled,
  (report, token) =>
      compactZdb(path, onProgress: report, cancellationToken: token),
);

/// כל כמה זמן נדגם [isCancelled] בזמן פעולה ארוכה של zvfs.
const Duration _cancelPollInterval = Duration(milliseconds: 200);

/// ב-zvfs ה-closure של Isolate.run לוכד גם את onProgress, ולכן הוא חייב להיות
/// sendable: מעבירים דרכו רק SendPort, וה-callback של הקורא נשאר כאן.
Future<void> _withProgressPort(
  void Function(int bytesDone, int totalBytes)? onProgress,
  bool Function()? isCancelled,
  Future<Object?> Function(
    void Function(int, int)? report,
    ZdbCancellationToken? token,
  )
  run,
) async {
  final token = isCancelled == null ? null : ZdbCancellationToken();
  if (token != null && isCancelled!()) token.cancel();
  final poll = token == null
      ? null
      : Timer.periodic(_cancelPollInterval, (_) {
          if (isCancelled!()) token.cancel();
        });
  final port = onProgress == null ? null : ReceivePort();
  final drained = Completer<void>();
  (int, int)? last;
  final subscription = port?.listen((message) {
    if (message is (int, int)) {
      last = message;
      onProgress!(message.$1, message.$2);
    } else if (message == _drainMarker) {
      drained.complete();
    }
  });
  var succeeded = false;
  try {
    await _mappedAsync(() => run(_portReporter(port?.sendPort), token));
    succeeded = true;
  } finally {
    poll?.cancel();
    if (port != null) {
      // הדיווח האחרון (100%) עוד בדרך; ה-port שומר על סדר, ולכן הסמן מגיע אחריו.
      port.sendPort.send(_drainMarker);
      await drained.future;
      await subscription!.cancel();
      port.close();
      // verifyZdb מדווח רק מה-timer, ולכן פעולה שהצליחה לא תמיד הגיעה ל-100%.
      final reported = last;
      if (succeeded && reported != null && reported.$1 < reported.$2) {
        onProgress!(reported.$2, reported.$2);
      }
    }
  }
}

const String _drainMarker = 'zvfs-progress-drained';

void Function(int, int)? _portReporter(SendPort? port) =>
    port == null ? null : (done, total) => port.send((done, total));

T _mapped<T>(T Function() body) {
  try {
    return body();
  } on ZdbException catch (error) {
    throw _toLibraryException(error);
  }
}

Future<void> _mappedAsync(Future<Object?> Function() body) async {
  try {
    await body();
  } on ZdbException catch (error) {
    throw _toLibraryException(error);
  }
}

LibraryZdbException _toLibraryException(ZdbException error) =>
    LibraryZdbException(switch (error.code) {
      ZdbException.busy => LibraryZdbFailure.busy,
      ZdbException.corrupt => LibraryZdbFailure.corrupt,
      ZdbException.unsupported => LibraryZdbFailure.unsupported,
      ZdbException.notZdb => LibraryZdbFailure.notZdb,
      ZdbException.io => LibraryZdbFailure.io,
      ZdbException.cancelled => LibraryZdbFailure.cancelled,
      _ => LibraryZdbFailure.other,
    }, error.message);

String _hexBytes(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

// ה-int של Dart מסומן; מפרקים לשני חצאים כדי לקבל את הערך הלא-מסומן.
String _hex64(int value) =>
    ((value >> 32) & 0xffffffff).toRadixString(16).padLeft(8, '0') +
    (value & 0xffffffff).toRadixString(16).padLeft(8, '0');
