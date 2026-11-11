import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

enum ErrorLogPlatform {
  windows,
  macos,
  linux,
  android,
  ios,
  other,
}

class ErrorLogFile {
  static const String fileName = 'errors.txt';
  static String _appVersion = 'unknown';

  static String get appVersion => _appVersion;

  static void setAppVersion(String version) {
    final normalized = version.trim();
    _appVersion = normalized.isEmpty ? 'unknown' : normalized;
  }

  /// מחזירה מופע קובץ עבור לוג השגיאות המקומי.
  static File resolveFile({
    Map<String, String>? environment,
    ErrorLogPlatform? platform,
    String? tempPath,
  }) {
    return File(
      resolvePath(
        environment: environment,
        platform: platform,
        tempPath: tempPath,
      ),
    );
  }

  /// מחזירה את הנתיב המלא לקובץ השגיאות של האפליקציה.
  ///
  /// ברירת המחדל היא תיקייה כתיבה פר-משתמש, כדי להימנע
  /// מכתיבה לתיקיית ההתקנה שעלולה להיות חסומה להרשאות כתיבה.
  static String resolvePath({
    Map<String, String>? environment,
    ErrorLogPlatform? platform,
    String? tempPath,
  }) {
    final env = environment ?? Platform.environment;
    final currentPlatform = platform ?? _detectPlatform();
    final configuredDataRoot =
        environment == null && platform == null && tempPath == null
        ? AppPaths.cachedDataRootPath
        : null;
    final baseDir =
        configuredDataRoot ??
        _resolveBaseDirectory(
          environment: env,
          platform: currentPlatform,
        ) ??
        tempPath ??
        Directory.systemTemp.path;

    return p.join(baseDir, 'logs', fileName);
  }

  /// מבטיחה שתיקיית הלוג והקובץ עצמו קיימים.
  static void ensureExists({
    Map<String, String>? environment,
    ErrorLogPlatform? platform,
    String? tempPath,
  }) {
    final file = resolveFile(
      environment: environment,
      platform: platform,
      tempPath: tempPath,
    );

    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
  }

  /// מוסיפה טקסט שכבר פורמט ללוג המקומי.
  static void appendText(
    String formattedMessage, {
    Map<String, String>? environment,
    ErrorLogPlatform? platform,
    String? tempPath,
  }) {
    final file = resolveFile(
      environment: environment,
      platform: platform,
      tempPath: tempPath,
    );

    // מצרפים רשומות שעוד בתור באותו קובץ כדי לשמור אותן גם במסלול קריסה.
    final pending = StringBuffer();
    for (final entry in _queued) {
      if (p.equals(entry.file.absolute.path, file.absolute.path)) {
        pending.write(entry.text);
      }
    }
    _writeSync(file.path, (pending..write(formattedMessage)).toString());
    _queued.removeWhere(
      (entry) => p.equals(entry.file.absolute.path, file.absolute.path),
    );
  }

  /// מוסיפה רשומת שגיאה לקובץ הלוג המקומי.
  static void append({
    required String title,
    required Object error,
    StackTrace? stackTrace,
    DateTime? timestamp,
    Map<String, String?> details = const {},
    String? version,
    Map<String, String>? environment,
    ErrorLogPlatform? platform,
    String? tempPath,
  }) {
    appendText(
      formatEntry(
        title: title,
        error: error,
        stackTrace: stackTrace,
        timestamp: timestamp,
        details: details,
        version: version,
      ),
      environment: environment,
      platform: platform,
      tempPath: tempPath,
    );
  }

  static final List<({File file, String text})> _queued = [];
  static Future<void>? _drain;

  /// כמו [append], בלי לחסום את ה-UI כשהדיסק עמוס. רשומה שעוד בתור אובדת
  /// בקריסה, ולכן מסלולי קריסה, יציאה ואינדוקס נשארים ב-[append].
  static void appendInBackground({
    required String title,
    required Object error,
    StackTrace? stackTrace,
    DateTime? timestamp,
    Map<String, String?> details = const {},
    String? version,
    Map<String, String>? environment,
    ErrorLogPlatform? platform,
    String? tempPath,
  }) {
    _queued.add((
      file: resolveFile(
        environment: environment,
        platform: platform,
        tempPath: tempPath,
      ),
      text: formatEntry(
        title: title,
        error: error,
        stackTrace: stackTrace,
        timestamp: timestamp,
        details: details,
        version: version,
      ),
    ));
    _drain ??= Future<void>(_drainQueue);
  }

  /// מסתיים כשכל רשומות הרקע נכתבו, או אחרי [timeout] אם הדיסק תקוע.
  static Future<void> flushPending({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final drain = _drain;
    if (drain == null) return;
    await drain.timeout(timeout, onTimeout: () {});
  }

  static Future<void> _drainQueue() async {
    try {
      while (_queued.isNotEmpty) {
        final entry = _queued.removeAt(0);
        try {
          await _writeInBackground(entry.file.path, entry.text);
        } catch (_) {
          // כמו בקוראים של append: כשל ברישום אינו משנה את הפעולה עצמה.
        }
      }
    } finally {
      _drain = null;
    }
  }

  static Future<void> _writeInBackground(String path, String text) =>
      Isolate.run(() => _writeSync(path, text));

  static void _writeSync(String path, String text) {
    File(path).parent.createSync(recursive: true);
    final bytes = utf8.encode(text);
    // FileMode.append ממקם את הסמן בפתיחה, לפני שכותב אחר עשוי להוסיף רשומה.
    using((arena) {
      final buffer = arena<Uint8>(bytes.length)
        ..asTypedList(bytes.length).setAll(0, bytes);
      if (Platform.isWindows) {
        _appendWindows(path, buffer, bytes.length, arena);
      } else {
        _appendPosix(path, buffer, bytes.length, arena);
      }
    });
  }

  /// בונה את תוכן הרשומה שתישמר בקובץ הלוג.
  static String formatEntry({
    required String title,
    required Object error,
    StackTrace? stackTrace,
    DateTime? timestamp,
    Map<String, String?> details = const {},
    String? version,
  }) {
    final logBuffer = StringBuffer()
      ..writeln(
        '=== $title ${timestamp?.toIso8601String() ?? DateTime.now().toIso8601String()} ===',
      )
      ..writeln('Version: ${_resolveVersion(version)}')
      ..writeln('Exception: $error');

    for (final entry in details.entries) {
      final value = entry.value?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }

      _writeDetail(logBuffer, entry.key, value);
    }

    if (stackTrace != null) {
      logBuffer
        ..writeln()
        ..writeln('Stack:')
        ..writeln(stackTrace);
    }

    logBuffer.writeln();
    return logBuffer.toString();
  }

  static String _resolveVersion(String? version) {
    final normalized = version?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    return _appVersion;
  }

  static void _writeDetail(StringBuffer buffer, String key, String value) {
    if (value.contains('\n')) {
      buffer
        ..writeln('$key:')
        ..writeln(value);
      return;
    }

    buffer.writeln('$key: $value');
  }

  static String? _resolveBaseDirectory({
    required Map<String, String> environment,
    required ErrorLogPlatform platform,
  }) {
    switch (platform) {
      case ErrorLogPlatform.windows:
        return _firstNonEmpty([
          environment['LOCALAPPDATA'],
          environment['APPDATA'],
        ]);
      case ErrorLogPlatform.macos:
        final home = environment['HOME'];
        if (home == null || home.isEmpty) {
          return null;
        }
        return p.join(home, 'Library', 'Application Support');
      case ErrorLogPlatform.linux:
        return _firstNonEmpty([
          environment['XDG_STATE_HOME'],
          _joinIfHasValue(environment['HOME'], '.local', 'state'),
          _joinIfHasValue(environment['HOME'], '.local', 'share'),
        ]);
      case ErrorLogPlatform.android:
      case ErrorLogPlatform.ios:
      case ErrorLogPlatform.other:
        return _joinIfHasValue(environment['HOME'], '.otzaria');
    }
  }

  static ErrorLogPlatform _detectPlatform() {
    if (Platform.isWindows) {
      return ErrorLogPlatform.windows;
    }
    if (Platform.isMacOS) {
      return ErrorLogPlatform.macos;
    }
    if (Platform.isLinux) {
      return ErrorLogPlatform.linux;
    }
    if (Platform.isAndroid) {
      return ErrorLogPlatform.android;
    }
    if (Platform.isIOS) {
      return ErrorLogPlatform.ios;
    }
    return ErrorLogPlatform.other;
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String? _joinIfHasValue(String? base, String part1, [String? part2]) {
    if (base == null || base.isEmpty) {
      return null;
    }
    if (part2 == null) {
      return p.join(base, part1);
    }
    return p.join(base, part1, part2);
  }
}

void _appendWindows(
  String path,
  Pointer<Uint8> buffer,
  int length,
  Arena arena,
) {
  final name = _windowsLogPath(path).toNativeUtf16(allocator: arena);
  final opened = win32.CreateFile(
    win32.PCWSTR(name),
    win32.FILE_APPEND_DATA,
    win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
    null,
    win32.OPEN_ALWAYS,
    win32.FILE_FLAG_WRITE_THROUGH,
    null,
  );
  if (opened.value == win32.INVALID_HANDLE_VALUE) {
    throw FileSystemException('CreateFileW', path, OSError('', opened.error));
  }
  try {
    final written = arena<Uint32>();
    final result = win32.WriteFile(opened.value, buffer, length, written, null);
    if (!result.value) {
      throw FileSystemException('WriteFile', path, OSError('', result.error));
    }
    if (written.value != length) {
      throw FileSystemException('Incomplete log write', path);
    }
  } finally {
    win32.CloseHandle(opened.value);
  }
}

String _windowsLogPath(String path) {
  if (path.startsWith(r'\\?\') || path.startsWith(r'\\.\')) return path;
  final absolute = p.normalize(p.absolute(path));
  if (absolute.length < win32.MAX_PATH) return absolute;
  return absolute.startsWith(r'\\')
      ? r'\\?\UNC\' + absolute.substring(2)
      : r'\\?\' + absolute;
}

void _appendPosix(String path, Pointer<Uint8> buffer, int length, Arena arena) {
  final file = _fopen(
    path.toNativeUtf8(allocator: arena),
    'ab'.toNativeUtf8(allocator: arena),
  );
  if (file == nullptr) throw FileSystemException('fopen', path);
  try {
    final fd = _fileno(file);
    if (_write(fd, buffer, length) != length) {
      throw FileSystemException('Incomplete log write', path);
    }
    if (_fsync(fd) != 0) throw FileSystemException('fsync', path);
  } finally {
    _fclose(file);
  }
}

final _libc = DynamicLibrary.process();
final _fopen = _libc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>)
    >('fopen');
final _fileno = _libc
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'fileno',
    );
final _write = _libc
    .lookupFunction<
      IntPtr Function(Int, Pointer<Uint8>, Size),
      int Function(int, Pointer<Uint8>, int)
    >('write');
final _fsync = _libc.lookupFunction<Int Function(Int), int Function(int)>(
  'fsync',
);
final _fclose = _libc
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'fclose',
    );
