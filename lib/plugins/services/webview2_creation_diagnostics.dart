import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

/// תוצאת הסריקה, שורת תיאור לכל תהליך. [unreadable] — תהליכים ששורת הפקודה
/// שלהם חסומה (elevated או משתמש אחר), ולכן אי אפשר לשלול שהם המחזיקים.
typedef WebView2FolderScan = ({
  List<String> holders,
  List<String> unreadable,
  int otherBrowsers,
});

/// אבחון לכשל יצירת WebView2 ב-Windows: מי מחזיק בתיקיית `webview2`, מה יש בה,
/// אילו runtimes, משתנים, מדיניות ואירועים. ריצת PowerShell אחת לתהליך, ברקע.
class WebView2CreationDiagnostics {
  WebView2CreationDiagnostics._();

  static const String logTitle = 'WebView2 creation failure diagnostics';
  static const Duration _processTimeout = Duration(seconds: 20);
  static const int maxFieldLength = 2000;

  // Each section fails alone; a failed process query is reported, not fatal.
  static const String _scriptBody = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
function Stamp($d) { if ($d) { $d.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'") } }
function Clip($s, $n) { $s = "$s" -replace '\s+', ' '; if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }
function Names($dir) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return $null }
  $all = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
  $names = @($all | Select-Object -First 30 | ForEach-Object { $_.Name })
  if ($all.Count -gt 30) { $names += "... +$($all.Count - 30)" }
  ,$names
}
function Section($block) { try { & $block } catch { 'error: ' + (Clip $_ 200) } }
$r = [ordered]@{}
try {
  $w = @(Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'")
  $ids = @($w | ForEach-Object { $_.ParentProcessId } | Sort-Object -Unique)
  $parents = @()
  if ($ids.Count -gt 0) {
    $filter = ($ids | ForEach-Object { "ProcessId=$_" }) -join ' OR '
    $parents = @(Get-CimInstance Win32_Process -Filter $filter)
  }
  $r.processes = @($w | ForEach-Object { [pscustomobject]@{
    pid = $_.ProcessId; ppid = $_.ParentProcessId; exe = $_.ExecutablePath
    cmd = $_.CommandLine; created = Stamp $_.CreationDate } })
  $r.parents = @($parents | ForEach-Object { [pscustomobject]@{
    pid = $_.ProcessId; name = $_.Name; exe = $_.ExecutablePath
    created = Stamp $_.CreationDate } })
} catch { $r.processError = Clip $_ 200 }
$r.ebWebView = Section { Names (Join-Path $folder 'EBWebView') }
$udf = $env:WEBVIEW2_USER_DATA_FOLDER
if ($udf) { $r.envFolderEbWebView = Section { Names (Join-Path $udf 'EBWebView') } }
$r.runtimes = [ordered]@{
  machine = Section { Names (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\EdgeWebView\Application') }
  user = Section { Names (Join-Path $env:LOCALAPPDATA 'Microsoft\EdgeWebView\Application') }
}
$r.env = @(Get-ChildItem Env: | Where-Object { $_.Name -like 'WEBVIEW2_*' } |
  ForEach-Object { $_.Name + '=' + (Clip $_.Value 300) })
$r.policies = @(foreach ($hive in 'HKLM', 'HKCU') {
  Section {
    $key = Get-Item -LiteralPath "${hive}:\SOFTWARE\Policies\Microsoft\Edge\WebView2" -ErrorAction SilentlyContinue
    if ($key) {
      $key.GetValueNames() | ForEach-Object { "$hive value $_" }
      $key.GetSubKeyNames() | ForEach-Object { "$hive key $_" }
    }
  }
})
$r.smartAppControl = Section {
  (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -Name VerifiedAndReputablePolicyState -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
}
$r.events = Section {
  @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-10) } -MaxEvents 300 -ErrorAction SilentlyContinue |
    ForEach-Object {
      $m = $_.Message; if (-not $m) { $m = ($_.Properties | ForEach-Object { $_.Value }) -join ' ' }
      if ("$($_.ProviderName) $m" -match 'msedgewebview2|WebView2|otzaria') {
        Clip ((Stamp $_.TimeCreated) + " $($_.ProviderName) #$($_.Id): $m") 400
      }
    } | Select-Object -First 6)
}
[pscustomobject]$r | ConvertTo-Json -Compress -Depth 4
''';

  static String _script(String folder) =>
      "\$folder = '${folder.replaceAll("'", "''")}'\n$_scriptBody";

  static bool _triggered = false;

  /// הגרסה שהחזיר `WebViewEnvironment.getAvailableVersion`, אם כבר נקרא.
  static String? runtimeVersion;

  /// תוצאת חימום WebView2 בתהליך הזה (תוצאה, משך, מתי הסתיים), אם רץ.
  static String? prewarmOutcome;

  /// סריקת CIM ויומן האירועים כבדה במעבד; לא מתחרים בה בעלייה ובחשיפת החלון.
  static Future<void> Function() startupGate = () => Future<void>.value();

  /// מריץ PowerShell עם הארגומנטים ומחזיר stdout, או null בכשל/פסק זמן.
  @visibleForTesting
  static Future<String?> Function(List<String> args)? debugRunnerOverride;

  @visibleForTesting
  static bool? debugIsWindowsOverride;

  @visibleForTesting
  static void debugReset() {
    _triggered = false;
    runtimeVersion = null;
    prewarmOutcome = null;
    debugRunnerOverride = null;
    debugIsWindowsOverride = null;
  }

  static bool get _isWindows => debugIsWindowsOverride ?? Platform.isWindows;

  /// מפעיל את הסריקה ברקע אחרי כשל יצירה (פעם אחת לתהליך).
  /// מחזיר את ה-Future לצורכי בדיקה בלבד; הקוראים אינם ממתינים לו.
  static Future<void>? recordCreationFailure(Object error) {
    try {
      if (_triggered) return null;
      if (!_isWindows) return null;
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
          Uint16List.fromList(_script(folder).codeUnits).buffer.asUint8List(),
        ),
      ];
      String? output;
      final stopwatch = Stopwatch()..start();
      try {
        output = await (debugRunnerOverride ?? _runPowerShell)(args);
      } catch (_) {}
      stopwatch.stop();

      final decoded = _decode(output);
      final scan = decoded == null || decoded['processError'] != null
          ? null
          : _scan(decoded, folder);
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
      final redactor = AppReportRedactor.fromPlatform();
      ErrorLogFile.append(
        title: logTitle,
        error: redactor.redactText(
          'WebView2 creation failed: ${_firstLine(trigger)}',
        ),
        details: {
          for (final MapEntry(:key, :value) in {
            'UserDataFolder': folder,
            'OwnPid': '$pid',
            'ScanMs': '${stopwatch.elapsedMilliseconds}',
            'RuntimeVersion': runtimeVersion,
            'Prewarm': prewarmOutcome,
            'ProcessQueryError': decoded?['processError']?.toString(),
            'Holders': holders,
            'UnreadableWebView2Processes': scan?.unreadable.length.toString(),
            'Unreadable': scan?.unreadable.join('\n'),
            'OtherWebView2Browsers': scan?.otherBrowsers.toString(),
            ...describeEnvironment(decoded),
          }.entries)
            key: value == null ? null : redactor.redactText(_clip(value)),
        },
      );
    } catch (_) {}
  }

  /// שדות הסביבה מפלט הסקריפט כשורות טקסט; ערך null מושמט מהרשומה.
  @visibleForTesting
  static Map<String, String?> describeEnvironment(Map? decoded) {
    if (decoded == null) return const {};
    final runtimes = decoded['runtimes'];
    return {
      'EBWebView': _joinNames(decoded['ebWebView']) ?? '(missing)',
      'WEBVIEW2_USER_DATA_FOLDER': _envValue(
        decoded['env'],
        'WEBVIEW2_USER_DATA_FOLDER',
      ),
      'EBWebViewAtEnvFolder': _joinNames(decoded['envFolderEbWebView']),
      if (runtimes is Map) ...{
        'RuntimesMachine': _joinNames(runtimes['machine']) ?? '(missing)',
        'RuntimesUser': _joinNames(runtimes['user']) ?? '(missing)',
      },
      'WebView2EnvVars': _lines(decoded['env']) ?? '(none)',
      'WebView2Policies': _lines(decoded['policies']) ?? '(none)',
      'SmartAppControl': switch ('${decoded['smartAppControl'] ?? ''}') {
        '' => '(not set)',
        '0' => '0 (off)',
        '1' => '1 (on)',
        '2' => '2 (evaluation)',
        final other => other,
      },
      'RecentAppEvents': _lines(decoded['events']) ?? '(none)',
    };
  }

  static String? _joinNames(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    final names = _asList(value);
    return names.isEmpty ? '(empty)' : names.join(', ');
  }

  static String? _lines(Object? value) {
    final items = _asList(value);
    return items.isEmpty ? null : items.join('\n');
  }

  static String? _envValue(Object? env, String name) {
    for (final entry in _asList(env)) {
      if (entry is String && entry.startsWith('$name=')) {
        return entry.substring(name.length + 1);
      }
    }
    return null;
  }

  static String _clip(String value) => value.length <= maxFieldLength
      ? value
      : '${value.substring(0, maxFieldLength)}... [clipped]';

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

  static Future<String?> _runPowerShell(List<String> args) =>
      runProcessOffMainIsolate(_powerShellExecutable, args, _processTimeout);

  /// מריץ תהליך ב-isolate עזר ומחזיר stdout, או null ביציאה לא תקינה/פסק זמן.
  /// Process.start קורא ל-CreateProcess סינכרונית ב-thread של ה-isolate הקורא.
  @visibleForTesting
  static Future<String?> runProcessOffMainIsolate(
    String executable,
    List<String> args,
    Duration timeout,
  ) => Isolate.run(() => _runProcess(executable, args, timeout));

  static Future<String?> _runProcess(
    String executable,
    List<String> args,
    Duration timeout,
  ) async {
    final process = await Process.start(executable, args);
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    unawaited(process.stderr.drain<void>());
    try {
      final results = await Future.wait<Object>([
        process.exitCode,
        stdout,
      ]).timeout(timeout);
      return results[0] == 0 ? results[1] as String : null;
    } on TimeoutException {
      process.kill();
      return null;
    }
  }

  static Map? _decode(String? output) {
    if (output == null) return null;
    try {
      final decoded = jsonDecode(output.trim());
      return decoded is Map ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// מפענח את פלט ה-JSON של הסקריפט; null כשהפלט אינו בצורה הצפויה.
  @visibleForTesting
  static WebView2FolderScan? parse(String output, String folder) {
    final decoded = _decode(output);
    return decoded == null ? null : _scan(decoded, folder);
  }

  static WebView2FolderScan? _scan(Map decoded, String folder) {
    try {
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
