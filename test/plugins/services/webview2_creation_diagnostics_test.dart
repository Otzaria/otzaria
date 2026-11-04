import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

const _folder = r'C:\Users\Moshe\AppData\Roaming\otzaria\webview2';
const _exe =
    r'C:\Program Files (x86)\Microsoft\EdgeWebView\Application\141.0.3537.71\msedgewebview2.exe';
const _conflict =
    'PlatformException(0, Cannot create the InAppWebView instance! '
    'HRESULT 0x8007139F, null, null)';

String _cmd(String dataDir, {String extra = ''}) =>
    '"$_exe" --embedded-browser-webview=1 --webview-exe-name=otzaria.exe '
    '--user-data-dir="$dataDir" $extra--noerrdialogs';

String _output({
  required List<Map<String, Object?>> processes,
  List<Map<String, Object?>> parents = const [],
}) => jsonEncode({'processes': processes, 'parents': parents});

WebView2FolderScan _parse(String output) =>
    WebView2CreationDiagnostics.parse(output, _folder)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final powerShell = Platform.isWindows ? 'powershell.exe' : 'pwsh';
  var hasPowerShell = false;
  try {
    hasPowerShell =
        Process.runSync(powerShell, [
          '-NoProfile',
          '-Command',
          'exit 0',
        ]).exitCode ==
        0;
  } on ProcessException {
    // הרצת הסקריפט דורשת PowerShell מותקן.
  }

  group('parse', () {
    test('keeps only browser roots that use our folder (any case/form)', () {
      final scan = _parse(
        _output(
          processes: [
            {
              'pid': 100,
              'ppid': 50,
              'exe': _exe,
              'cmd': _cmd(
                r'\\?\c:\users\moshe\appdata\roaming\OTZARIA\webview2\EBWebView\',
              ),
              'created': '2026-10-17T08:00:05Z',
            },
            {
              'pid': 101,
              'ppid': 100,
              'cmd': _cmd('$_folder\\EBWebView', extra: '--type=renderer '),
            },
            {'pid': 200, 'ppid': 60, 'cmd': _cmd(r'C:\Other\App\EBWebView')},
          ],
          parents: [
            {
              'pid': 50,
              'name': 'otzaria.exe',
              'exe': r'C:\Program Files\otzaria\otzaria.exe',
              'created': '2026-10-17T08:00:00Z',
            },
          ],
        ),
      );

      expect(scan.otherBrowsers, 1);
      expect(scan.unreadable, isEmpty);
      expect(scan.holders, [
        r'pid=100 parentPid=50 parent=C:\Program Files\otzaria\otzaria.exe '
            'created=2026-10-17T08:00:05Z version=141.0.3537.71 '
            'hostExe=otzaria.exe',
      ]);
    });

    test('folder itself (no EBWebView) also matches', () {
      final scan = _parse(
        _output(
          processes: [
            {'pid': 1, 'ppid': 2, 'cmd': '--user-data-dir=$_folder'},
          ],
        ),
      );
      expect(scan.holders.single, startsWith('pid=1 parentPid=2'));
    });

    test('missing parent and reused parent pid are reported as exited', () {
      final scan = _parse(
        _output(
          processes: [
            {'pid': 100, 'ppid': 50, 'cmd': _cmd(_folder)},
            {
              'pid': 300,
              'ppid': 70,
              'cmd': _cmd(_folder),
              'created': '2026-10-17T08:00:00Z',
            },
          ],
          parents: [
            {
              'pid': 70,
              'name': 'notepad.exe',
              'exe': r'C:\Windows\notepad.exe',
              'created': '2026-10-17T09:00:00Z',
            },
          ],
        ),
      );
      expect(scan.holders, everyElement(contains('parent=exited')));
    });

    test('processes without a readable command line are counted', () {
      final scan = _parse(
        jsonEncode({
          'processes': [
            {'pid': 7, 'ppid': 2, 'cmd': null, 'exe': null},
            {'pid': 8, 'ppid': 7, 'cmd': null, 'exe': null},
          ],
          'parents': {'pid': 2, 'name': 'otzaria.exe', 'exe': null},
        }),
      );
      expect(scan.holders, isEmpty);
      expect(scan.unreadable, [
        'pid=7 parentPid=2 parent=otzaria.exe',
        'pid=8 parentPid=7 parent=exited',
      ]);
    });

    test('single objects instead of arrays are accepted', () {
      final scan = _parse(
        jsonEncode({
          'processes': {'pid': 1, 'ppid': 2, 'cmd': _cmd(_folder)},
          'parents': {'pid': 2, 'name': 'svchost.exe', 'exe': null},
        }),
      );
      expect(scan.holders.single, contains('svchost.exe (path unavailable)'));
    });

    test('garbage output yields null', () {
      expect(WebView2CreationDiagnostics.parse('not json', _folder), isNull);
      expect(WebView2CreationDiagnostics.parse('[1,2]', _folder), isNull);
      expect(WebView2CreationDiagnostics.parse('', _folder), isNull);
    });
  });

  group('describeEnvironment', () {
    test('formats every section of the script output', () {
      final fields = WebView2CreationDiagnostics.describeEnvironment({
        'ebWebView': ['EBWebViewMetrics'],
        'envFolderEbWebView': <String>[],
        'runtimes': {
          'machine': ['141.0.3537.71', 'SetupMetrics'],
          'user': null,
        },
        'env': [
          r'WEBVIEW2_USER_DATA_FOLDER=D:\wv',
          'WEBVIEW2_RELEASE_CHANNEL_PREFERENCE=1',
        ],
        'policies': [
          'HKLM value BrowserExecutableFolder',
          'HKCU key ReleaseChannels',
        ],
        'smartAppControl': 2,
        'events': [
          '2026-10-17T08:00:00Z Application Error #1000: msedgewebview2.exe',
        ],
      });
      expect(fields['EBWebView'], 'EBWebViewMetrics');
      expect(fields['WEBVIEW2_USER_DATA_FOLDER'], r'D:\wv');
      expect(fields['EBWebViewAtEnvFolder'], '(empty)');
      expect(fields['RuntimesMachine'], '141.0.3537.71, SetupMetrics');
      expect(fields['RuntimesUser'], '(missing)');
      expect(fields['WebView2EnvVars'], contains('\nWEBVIEW2_RELEASE_CHANNEL'));
      expect(fields['WebView2Policies'], contains('HKCU key ReleaseChannels'));
      expect(fields['SmartAppControl'], '2 (evaluation)');
      expect(fields['RecentAppEvents'], contains('#1000'));
    });

    test('missing sections stay explicit, section errors are kept', () {
      final fields = WebView2CreationDiagnostics.describeEnvironment({
        'ebWebView': null,
        'runtimes': {'machine': 'error: Access denied', 'user': null},
        'env': <String>[],
      });
      expect(fields['EBWebView'], '(missing)');
      expect(fields['RuntimesMachine'], 'error: Access denied');
      expect(fields['WEBVIEW2_USER_DATA_FOLDER'], isNull);
      expect(fields['EBWebViewAtEnvFolder'], isNull);
      expect(fields['WebView2EnvVars'], '(none)');
      expect(fields['SmartAppControl'], '(not set)');
      expect(WebView2CreationDiagnostics.describeEnvironment(null), isEmpty);
    });
  });

  group('record', () {
    late Directory tempDir;
    late String folder;

    setUp(() {
      WebView2CreationDiagnostics.debugReset();
      WebView2CreationDiagnostics.debugIsWindowsOverride = true;
      WebViewEnvironmentHolder.debugResetBrowserExitCount();
      tempDir = Directory.systemTemp.createTempSync('wv_diagnostics');
      folder = p.join(tempDir.path, 'webview2');
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      debugForcePluginWebViewFailureFileLog = true;
    });

    tearDown(() {
      WebView2CreationDiagnostics.debugReset();
      debugForcePluginWebViewFailureFileLog = false;
      AppPaths.debugOverrideDataRootPath(null);
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    String errorsTxt() {
      final file = File(p.join(tempDir.path, 'logs', ErrorLogFile.fileName));
      return file.existsSync() ? file.readAsStringSync() : '';
    }

    Future<String> recordWith(String? output) async {
      WebView2CreationDiagnostics.debugRunnerOverride = (_) async => output;
      await WebView2CreationDiagnostics.recordCreationFailure(_conflict);
      return errorsTxt();
    }

    String redacted(String text) =>
        AppReportRedactor.fromPlatform().redactText(text);

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('non-Windows does not run', () {
      WebView2CreationDiagnostics.debugIsWindowsOverride = false;
      expect(
        WebView2CreationDiagnostics.recordCreationFailure(_conflict),
        isNull,
      );
    });

    for (final failure in ['empty', 'browser query', 'parent query']) {
      test('PowerShell $failure preserves query outcome', () async {
        int? exitCode;
        WebView2CreationDiagnostics.debugRunnerOverride = (args) async {
          final script = String.fromCharCodes(
            Uint16List.view(base64Decode(args.last).buffer),
          );
          final mockedScript =
              '''
function Get-CimInstance {
  param(\$ClassName, \$Filter)
  if (\$Filter -like 'Name=*') {
    ${failure == 'browser query' ? "Write-Error 'Access denied'" : ''}
    ${failure == 'parent query' ? "[pscustomobject]@{ ProcessId=7; ParentProcessId=4; CommandLine='--user-data-dir=\"$folder\"' }" : ''}
  } else {
    Write-Error 'WMI unavailable'
  }
}
$script
''';
          final result = await Process.run(powerShell, [
            ...args.take(args.length - 1),
            base64Encode(
              Uint16List.fromList(mockedScript.codeUnits).buffer.asUint8List(),
            ),
          ]);
          exitCode = result.exitCode;
          return result.stdout as String;
        };

        await WebView2CreationDiagnostics.recordCreationFailure(_conflict);
        final content = errorsTxt();
        expect(
          content,
          contains(
            failure == 'empty'
                ? 'Holders: none: no msedgewebview2 browser process uses the folder'
                : 'Holders: process query failed or timed out',
          ),
        );
        if (failure != 'empty') {
          expect(content, isNot(contains('parent=exited')));
          expect(content, contains('ProcessQueryError: '));
        }
        // A failed process query no longer hides the other sections.
        expect(exitCode, 0);
        expect(content, contains('EBWebView: (missing)'));
        expect(content, contains('SmartAppControl: '));
        expect(content, contains('RuntimesMachine: '));
      }, skip: !hasPowerShell ? 'PowerShell is not installed' : false);
    }

    test('waits for the startup gate before spawning', () async {
      final gate = Completer<void>();
      var runs = 0;
      WebView2CreationDiagnostics.startupGate = () => gate.future;
      addTearDown(
        () =>
            WebView2CreationDiagnostics.startupGate = () =>
                Future<void>.value(),
      );
      WebView2CreationDiagnostics.debugRunnerOverride = (_) async {
        runs++;
        return null;
      };

      final future = WebView2CreationDiagnostics.recordCreationFailure(
        _conflict,
      )!;
      await Future<void>.delayed(Duration.zero);
      expect(runs, 0);
      gate.complete();
      await future;
      expect(runs, 1);
    });

    test('runs at most once per process and lists the holder', () async {
      var runs = 0;
      WebView2CreationDiagnostics.debugRunnerOverride = (args) async {
        runs++;
        expect(args, containsAllInOrder(['-NoProfile', '-NonInteractive']));
        return _output(
          processes: [
            {'pid': 9, 'ppid': 8, 'cmd': _cmd('$folder\\EBWebView')},
          ],
        );
      };

      await WebView2CreationDiagnostics.recordCreationFailure(
        'HRESULT 0x80070005',
      );
      expect(
        WebView2CreationDiagnostics.recordCreationFailure(_conflict),
        isNull,
      );

      expect(runs, 1);
      final content = errorsTxt();
      expect(
        RegExp(WebView2CreationDiagnostics.logTitle).allMatches(content),
        hasLength(1),
      );
      expect(content, contains('UserDataFolder: ${redacted(folder)}'));
      expect(content, contains('WebView2 creation failed: HRESULT 0x80070005'));
      expect(content, contains('OwnPid: $pid'));
      expect(content, contains('Holders: pid=9 parentPid=8 parent=exited'));
    });

    test('no holder is written explicitly', () async {
      final content = await recordWith(_output(processes: const []));
      expect(
        content,
        contains(
          'Holders: none: no msedgewebview2 browser process uses the folder',
        ),
      );
      expect(content, contains('OtherWebView2Browsers: 0'));
    });

    test('unreadable processes prevent the "none" conclusion', () async {
      final content = await recordWith(
        _output(
          processes: [
            {'pid': 5, 'ppid': 4, 'cmd': null},
          ],
        ),
      );
      expect(content, contains('Holders: none readable'));
      expect(content, contains('UnreadableWebView2Processes: 1'));
      expect(content, contains('pid=5 parentPid=4 parent=exited'));
    });

    for (final entry in <String, Future<String?> Function(List<String>)>{
      'throws': (_) async => throw const ProcessException('powershell', []),
      'times out (null)': (_) async => null,
      'returns garbage': (_) async => '\u0000garbage{',
    }.entries) {
      test('runner that ${entry.key} never throws', () async {
        WebView2CreationDiagnostics.debugRunnerOverride = entry.value;
        await WebView2CreationDiagnostics.recordCreationFailure(_conflict);
        expect(
          errorsTxt(),
          contains('Holders: process query failed or timed out'),
        );
      });
    }

    test('logged folder conflict adds a holders entry after it', () async {
      final ran = Completer<void>();
      WebView2CreationDiagnostics.debugRunnerOverride = (_) async {
        ran.complete();
        return _output(processes: const []);
      };
      logPluginWebViewFailure(
        'Plugin WebView creation failed',
        _conflict,
        creationFailure: true,
      );
      await ran.future;
      // After the runner the record is synchronous; a timer runs after it.
      await Future<void>.delayed(Duration.zero);

      final content = errorsTxt();
      final failureAt = content.indexOf('=== Plugin WebView creation failed');
      final holdersAt = content.indexOf(
        '=== ${WebView2CreationDiagnostics.logTitle}',
      );
      expect(failureAt, greaterThanOrEqualTo(0));
      expect(holdersAt, greaterThan(failureAt));
    });

    test('failures that are not creation failures do no work', () async {
      var runs = 0;
      WebView2CreationDiagnostics.debugRunnerOverride = (_) async {
        runs++;
        return null;
      };
      logPluginWebViewFailure('Plugin WebView2 process failed', _conflict);
      await settle();
      expect(runs, 0);
      expect(
        errorsTxt(),
        isNot(contains(WebView2CreationDiagnostics.logTitle)),
      );
      expect(
        WebView2CreationDiagnostics.recordCreationFailure(_conflict),
        isNotNull,
      );
    });

    test(
      'fields are clipped and the user profile is redacted',
      () async {
        final profile =
            Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
        final content = await recordWith(
          jsonEncode({
            'processes': const [],
            'ebWebView': List.filled(500, 'EBWebViewMetrics'),
            'env': ['WEBVIEW2_USER_DATA_FOLDER=$profile${p.separator}wv'],
          }),
        );
        final line = content
            .split('\n')
            .firstWhere((line) => line.startsWith('EBWebView: '));
        expect(
          line.length,
          lessThan(WebView2CreationDiagnostics.maxFieldLength + 40),
        );
        expect(line, endsWith('... [clipped]'));
        expect(
          content,
          contains(
            'WEBVIEW2_USER_DATA_FOLDER: '
            '${AppReportRedactor.profilePlaceholder}${p.separator}wv',
          ),
        );
        expect(content, isNot(contains('$profile${p.separator}wv')));
      },
      skip:
          (Platform.environment['USERPROFILE'] ??
                  Platform.environment['HOME'] ??
                  '')
              .length <
          4,
    );

    test('runtime version joins the record', () async {
      WebView2CreationDiagnostics.runtimeVersion = '141.0.3537.71';
      final content = await recordWith(_output(processes: const []));
      expect(content, contains('RuntimeVersion: 141.0.3537.71'));
    });

    test('watchdog of a slow load does not trigger the scan', () async {
      var runs = 0;
      WebView2CreationDiagnostics.debugRunnerOverride = (_) async {
        runs++;
        return null;
      };
      logPluginWebViewFailure(
        'Plugin WebView never created (silent blank)',
        'onWebViewCreated did not fire within 20s',
      );
      await settle();
      expect(runs, 0);
    });

    test('only abnormal browser exits are logged, a few per process', () {
      WebViewEnvironmentHolder.debugBrowserProcessExited(
        BrowserProcessExitedDetail(
          kind: BrowserProcessExitKind.NORMAL,
          processId: 1,
        ),
      );
      expect(errorsTxt(), isEmpty);
      for (var i = 0; i < 5; i++) {
        WebViewEnvironmentHolder.debugBrowserProcessExited(
          BrowserProcessExitedDetail(
            kind: BrowserProcessExitKind.FAILED,
            processId: 40 + i,
          ),
        );
      }
      final content = errorsTxt();
      expect(
        RegExp('=== WebView2 browser process exited').allMatches(content),
        hasLength(3),
      );
      expect(content, contains('Exception: FAILED'));
      expect(content, contains('ProcessId: 40'));
    });
  });

  group('runProcessOffMainIsolate', () {
    Future<String?> run(String command, Duration timeout) =>
        WebView2CreationDiagnostics.runProcessOffMainIsolate(powerShell, [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          command,
        ], timeout);
    final skip = !hasPowerShell ? 'PowerShell is not installed' : false;

    test('returns stdout of a successful run', () async {
      expect(
        (await run("Write-Output 'ok'", const Duration(seconds: 20)))?.trim(),
        'ok',
      );
    }, skip: skip);

    test('failed exit and timeout yield null', () async {
      expect(await run('exit 3', const Duration(seconds: 20)), isNull);
      final stopwatch = Stopwatch()..start();
      expect(
        await run('Start-Sleep -Seconds 30', const Duration(seconds: 2)),
        isNull,
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    }, skip: skip);
  });
}
