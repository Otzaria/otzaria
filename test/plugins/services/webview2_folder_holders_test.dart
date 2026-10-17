import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/services/webview2_folder_holders.dart';
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
    WebView2FolderHolders.parse(output, _folder)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(WebView2FolderHolders.parse('not json', _folder), isNull);
      expect(WebView2FolderHolders.parse('[1,2]', _folder), isNull);
      expect(WebView2FolderHolders.parse('', _folder), isNull);
    });
  });

  test('only folder-conflict HRESULTs match, case-insensitively', () {
    expect(WebView2FolderHolders.isFolderConflict(_conflict), isTrue);
    expect(
      WebView2FolderHolders.isFolderConflict('HRESULT 0x8000ffff'),
      isTrue,
    );
    expect(
      WebView2FolderHolders.isFolderConflict('HRESULT 0x80070005'),
      isFalse,
    );
    expect(WebView2FolderHolders.isFolderConflict(StateError('x')), isFalse);
  });

  group('record', () {
    late Directory tempDir;
    late String folder;

    setUp(() {
      WebView2FolderHolders.debugReset();
      WebView2FolderHolders.debugIsWindowsOverride = true;
      tempDir = Directory.systemTemp.createTempSync('wv_holders');
      folder = p.join(tempDir.path, 'webview2');
      AppPaths.debugOverrideDataRootPath(tempDir.path);
      debugForcePluginWebViewFailureFileLog = true;
    });

    tearDown(() {
      WebView2FolderHolders.debugReset();
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
      WebView2FolderHolders.debugRunnerOverride = (_) async => output;
      await WebView2FolderHolders.recordIfFolderConflict(_conflict);
      return errorsTxt();
    }

    test('non-Windows does not run', () {
      WebView2FolderHolders.debugIsWindowsOverride = false;
      expect(WebView2FolderHolders.recordIfFolderConflict(_conflict), isNull);
    });

    test('waits for the startup gate before spawning', () async {
      final gate = Completer<void>();
      var runs = 0;
      WebView2FolderHolders.startupGate = () => gate.future;
      addTearDown(
        () => WebView2FolderHolders.startupGate = () => Future<void>.value(),
      );
      WebView2FolderHolders.debugRunnerOverride = (_) async {
        runs++;
        return null;
      };

      final future = WebView2FolderHolders.recordIfFolderConflict(_conflict)!;
      await Future<void>.delayed(Duration.zero);
      expect(runs, 0);
      gate.complete();
      await future;
      expect(runs, 1);
    });

    test('runs at most once per process and lists the holder', () async {
      var runs = 0;
      WebView2FolderHolders.debugRunnerOverride = (args) async {
        runs++;
        expect(args, containsAllInOrder(['-NoProfile', '-NonInteractive']));
        return _output(
          processes: [
            {'pid': 9, 'ppid': 8, 'cmd': _cmd('$folder\\EBWebView')},
          ],
        );
      };

      expect(
        WebView2FolderHolders.recordIfFolderConflict('HRESULT 0x1'),
        isNull,
      );
      await WebView2FolderHolders.recordIfFolderConflict(_conflict);
      expect(WebView2FolderHolders.recordIfFolderConflict(_conflict), isNull);

      expect(runs, 1);
      final content = errorsTxt();
      expect(
        RegExp(WebView2FolderHolders.logTitle).allMatches(content),
        hasLength(1),
      );
      expect(content, contains('UserDataFolder: $folder'));
      expect(content, contains('OwnPid: $pid'));
      expect(content, contains('Holders: pid=9 parentPid=8 parent=exited'));
      expect(content, contains('0x8007139F'));
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
        WebView2FolderHolders.debugRunnerOverride = entry.value;
        await WebView2FolderHolders.recordIfFolderConflict(_conflict);
        expect(
          errorsTxt(),
          contains('Holders: process query failed or timed out'),
        );
      });
    }

    test('logged folder conflict adds a holders entry after it', () async {
      final ran = Completer<void>();
      WebView2FolderHolders.debugRunnerOverride = (_) async {
        ran.complete();
        return _output(processes: const []);
      };
      logPluginWebViewFailure('Plugin WebView creation failed', _conflict);
      await ran.future;
      // After the runner the record is synchronous; a timer runs after it.
      await Future<void>.delayed(Duration.zero);

      final content = errorsTxt();
      final failureAt = content.indexOf('=== Plugin WebView creation failed');
      final holdersAt = content.indexOf(
        '=== ${WebView2FolderHolders.logTitle}',
      );
      expect(failureAt, greaterThanOrEqualTo(0));
      expect(holdersAt, greaterThan(failureAt));
    });

    test('other logged failures add no holders entry', () {
      logPluginWebViewFailure('Plugin WebView creation failed', 'HRESULT 0x5');
      expect(errorsTxt(), isNot(contains(WebView2FolderHolders.logTitle)));
      expect(
        WebView2FolderHolders.recordIfFolderConflict(_conflict),
        isNotNull,
      );
    });
  });
}
