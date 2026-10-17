import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;

/// תוצאת הסריקה, שורת תיאור לכל תהליך. [unreadable] — תהליכים ששורת הפקודה
/// שלהם חסומה (elevated או משתמש אחר), ולכן אי אפשר לשלול שהם המחזיקים.
typedef WebView2FolderScan = ({
  List<String> holders,
  List<String> unreadable,
  int otherBrowsers,
});

/// אבחון ל-HRESULT 0x8007139F/0x8000FFFF: מי מחזיק בתיקיית `webview2` שלנו.
/// נרשם ל-errors.txt פעם אחת לתהליך, ברקע, ולעולם לא זורק.
class WebView2FolderHolders {
  WebView2FolderHolders._();

  static const String logTitle = 'WebView2 data folder holders';
  static const Duration _processTimeout = Duration(seconds: 10);
  static const List<String> _folderConflictHresults = [
    '0x8007139f',
    '0x8000ffff',
  ];

  // Emits every msedgewebview2 process with its parent; [parse] keeps the roots.
  static const String _script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
function Stamp($d) { if ($d) { $d.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") } }
$w = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'")
$ids = @($w | ForEach-Object { $_.ParentProcessId } | Sort-Object -Unique)
$parents = @()
if ($ids.Count -gt 0) {
  $filter = ($ids | ForEach-Object { "ProcessId=$_" }) -join ' OR '
  $parents = @(Get-CimInstance Win32_Process -Filter $filter)
}
[pscustomobject]@{
  processes = @($w | ForEach-Object { [pscustomobject]@{
    pid = $_.ProcessId; ppid = $_.ParentProcessId; exe = $_.ExecutablePath
    cmd = $_.CommandLine; created = Stamp $_.CreationDate } })
  parents = @($parents | ForEach-Object { [pscustomobject]@{
    pid = $_.ProcessId; name = $_.Name; exe = $_.ExecutablePath
    created = Stamp $_.CreationDate } })
} | ConvertTo-Json -Compress -Depth 4
''';

  static bool _triggered = false;

  /// Process.start חוסם את ה-thread הראשי ב-Windows; ממתינים לחשיפת החלון.
  static Future<void> Function() startupGate = () => Future<void>.value();

  /// מריץ PowerShell עם הארגומנטים ומחזיר stdout, או null בכשל/פסק זמן.
  @visibleForTesting
  static Future<String?> Function(List<String> args)? debugRunnerOverride;

  @visibleForTesting
  static bool? debugIsWindowsOverride;

  @visibleForTesting
  static void debugReset() {
    _triggered = false;
    debugRunnerOverride = null;
    debugIsWindowsOverride = null;
  }

  static bool isFolderConflict(Object error) {
    final text = error.toString().toLowerCase();
    return _folderConflictHresults.any(text.contains);
  }

  /// מפעיל את הסריקה ברקע אם [error] הוא התנגשות על התיקייה (פעם אחת לתהליך).
  /// מחזיר את ה-Future לצורכי בדיקה בלבד; הקוראים אינם ממתינים לו.
  static Future<void>? recordIfFolderConflict(Object error) {
    try {
      if (_triggered) return null;
      if (!(debugIsWindowsOverride ?? Platform.isWindows)) return null;
      if (!isFolderConflict(error)) return null;
      _triggered = true;
      final future = _record(error);
      unawaited(future);
      return future;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _record(Object trigger) async {
    try {
      await startupGate();
      final folder = p.join(await AppPaths.getDataRootPath(), 'webview2');
      final args = [
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        base64.encode(
          Uint16List.fromList(_script.codeUnits).buffer.asUint8List(),
        ),
      ];
      String? output;
      try {
        output = await (debugRunnerOverride ?? _runPowerShell)(args);
      } catch (_) {}

      final scan = output == null ? null : parse(output, folder);
      final String holders;
      if (scan == null) {
        holders = 'process query failed or timed out';
      } else if (scan.holders.isNotEmpty) {
        holders = scan.holders.join('\n');
      } else if (scan.unreadable.isEmpty) {
        holders = 'none: no msedgewebview2 browser process uses the folder';
      } else {
        holders =
            'none readable: may be an unreadable process '
            '(elevated or another user)';
      }
      ErrorLogFile.append(
        title: logTitle,
        error: 'HRESULT folder conflict: ${_firstLine(trigger)}',
        details: {
          'UserDataFolder': folder,
          'OwnPid': '$pid',
          'Holders': holders,
          'UnreadableWebView2Processes': scan?.unreadable.length.toString(),
          'Unreadable': scan?.unreadable.join('\n'),
          'OtherWebView2Browsers': scan?.otherBrowsers.toString(),
        },
      );
    } catch (_) {}
  }

  static String _firstLine(Object error) {
    final text = error.toString().trim();
    final newline = text.indexOf('\n');
    return newline < 0 ? text : text.substring(0, newline);
  }

  // Absolute path: an unqualified name is searched first in the exe folder/CWD.
  static String get _powerShellExecutable => p.join(
    Platform.environment['SystemRoot'] ?? r'C:\Windows',
    'System32',
    'WindowsPowerShell',
    'v1.0',
    'powershell.exe',
  );

  static Future<String?> _runPowerShell(List<String> args) async {
    final process = await Process.start(_powerShellExecutable, args);
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    unawaited(process.stderr.drain<void>());
    try {
      final results = await Future.wait<Object>([
        process.exitCode,
        stdout,
      ]).timeout(_processTimeout);
      return results[1] as String;
    } on TimeoutException {
      process.kill();
      return null;
    }
  }

  /// מפענח את פלט ה-JSON של הסקריפט; null כשהפלט אינו בצורה הצפויה.
  @visibleForTesting
  static WebView2FolderScan? parse(String output, String folder) {
    try {
      final decoded = jsonDecode(output.trim());
      if (decoded is! Map) return null;
      final parents = <Object?, Map>{
        for (final parent in _asList(decoded['parents']))
          if (parent is Map) parent['pid']: parent,
      };
      final wanted = {
        _normalize(folder),
        _normalize(p.windows.join(folder, 'EBWebView')),
      };
      final holders = <String>[];
      final unreadable = <String>[];
      var others = 0;
      for (final process in _asList(decoded['processes'])) {
        if (process is! Map) continue;
        final parent = _liveParent(parents[process['ppid']], process);
        final ids = 'pid=${process['pid']} parentPid=${process['ppid']}';
        final cmd = process['cmd'];
        if (cmd is! String) {
          unreadable.add('$ids parent=${parent?['name'] ?? 'exited'}');
          continue;
        }
        if (cmd.contains('--type=')) continue;
        final dataDir = _argValue(cmd, '--user-data-dir=');
        if (dataDir == null) continue;
        // WebView2 passes Chromium the EBWebView subfolder of userDataFolder.
        if (!wanted.contains(_normalize(dataDir))) {
          others++;
          continue;
        }
        final parentExe = parent?['exe'];
        final parentPath = parent == null
            ? 'exited'
            : parentExe is String && parentExe.isNotEmpty
            ? parentExe
            : '${parent['name']} (path unavailable)';
        final version = _versionPattern
            .firstMatch('${process['exe'] ?? cmd}')
            ?.group(1);
        holders.add(
          '$ids parent=$parentPath created=${process['created'] ?? '?'} '
          'version=${version ?? '?'} '
          'hostExe=${_argValue(cmd, '--webview-exe-name=') ?? '?'}',
        );
      }
      return (holders: holders, unreadable: unreadable, otherBrowsers: others);
    } catch (_) {
      return null;
    }
  }

  static List<Object?> _asList(Object? value) => switch (value) {
    final List list => list.cast<Object?>(),
    null => const [],
    _ => [value],
  };

  // PID reuse: a parent created after the child is a different process.
  static Map? _liveParent(Map? parent, Map child) {
    if (parent == null) return null;
    final parentTime = DateTime.tryParse('${parent['created']}');
    final childTime = DateTime.tryParse('${child['created']}');
    if (parentTime != null &&
        childTime != null &&
        parentTime.isAfter(childTime)) {
      return null;
    }
    return parent;
  }

  static String? _argValue(String cmd, String name) {
    final start = cmd.indexOf(name);
    if (start < 0) return null;
    final rest = cmd.substring(start + name.length);
    if (rest.startsWith('"')) {
      final end = rest.indexOf('"', 1);
      return end < 0 ? rest.substring(1) : rest.substring(1, end);
    }
    final end = rest.indexOf(' ');
    return end < 0 ? rest : rest.substring(0, end);
  }

  static String _normalize(String path) {
    var normalized = path.trim();
    if (normalized.startsWith(r'\\?\UNC\')) {
      normalized = '\\\\${normalized.substring(8)}';
    } else if (normalized.startsWith(r'\\?\')) {
      normalized = normalized.substring(4);
    }
    normalized = p.windows.normalize(normalized).toLowerCase();
    while (normalized.length > 3 && normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static final RegExp _versionPattern = RegExp(
    r'\\(\d+\.\d+\.\d+\.\d+)\\msedgewebview2\.exe',
    caseSensitive: false,
  );
}
