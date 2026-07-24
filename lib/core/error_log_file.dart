import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

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

    ensureExists(
      environment: environment,
      platform: platform,
      tempPath: tempPath,
    );

    file.writeAsStringSync(
      formattedMessage,
      mode: FileMode.append,
      flush: true,
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
