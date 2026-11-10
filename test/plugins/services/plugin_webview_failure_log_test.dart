import 'dart:io';

import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart'
    show WindowsWebViewHwndFallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/services/webview2_creation_diagnostics.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wv_failure_log');
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    debugForcePluginWebViewFailureFileLog = true;
  });

  tearDown(() {
    debugForcePluginWebViewFailureFileLog = false;
    AppPaths.debugOverrideDataRootPath(null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File errorsFile() =>
      File(p.join(tempDir.path, 'logs', ErrorLogFile.fileName));

  test('כשל נרשם ל-errors.txt עם הכותרת והפרטים', () async {
    logPluginWebViewFailure(
      'WebView2 environment init failed',
      StateError('boom'),
      details: const {'UserDataFolder': r'C:\data\webview2'},
    );

    await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
    final content = errorsFile().readAsStringSync();
    expect(content, contains('WebView2 environment init failed'));
    expect(content, contains('Bad state: boom'));
    expect(content, contains(r'UserDataFolder: C:\data\webview2'));
  });

  test('פרטים ריקים מושמטים מהרשומה', () async {
    logPluginWebViewFailure(
      'Plugin WebView2 process failed',
      'RENDER_PROCESS_EXITED',
      details: const {'Plugin': 'my-plugin', 'ExitCode': null},
    );

    await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
    final content = errorsFile().readAsStringSync();
    expect(content, contains('Plugin: my-plugin'));
    expect(content, isNot(contains('ExitCode')));
  });

  group('נסיגה למצב HWND', () {
    late int diagnosticsRuns;

    setUp(() {
      debugResetPluginWebViewHwndFallbackLog();
      WebView2CreationDiagnostics.debugReset();
      WebView2CreationDiagnostics.debugIsWindowsOverride = true;
      diagnosticsRuns = 0;
      WebView2CreationDiagnostics.debugRunnerOverride = (_) async {
        diagnosticsRuns++;
        return null;
      };
    });

    tearDown(() {
      WebView2CreationDiagnostics.debugReset();
      WebView2CreationDiagnostics.debugIsWindowsOverride = null;
      WebView2CreationDiagnostics.debugRunnerOverride = null;
    });

    test('נרשמת פעם אחת לתהליך, עם השלב וה-HRESULT', () async {
      const fallback = WindowsWebViewHwndFallback(
        stage: 'CreateCoreWebView2CompositionController callback',
        hresult: 0x8007139F,
        requestedUrl: 'otzaria-plugin://my.plugin/index.html',
      );
      logPluginWebViewHwndFallback(fallback);
      logPluginWebViewHwndFallback(fallback);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));

      final content = errorsFile().readAsStringSync();
      expect('Plugin WebView HWND fallback'.allMatches(content), hasLength(1));
      expect(
        content,
        contains('Stage: CreateCoreWebView2CompositionController callback'),
      );
      expect(content, contains('HRESULT: 0x8007139F'));
      expect(
        content,
        contains('RequestedUrl: otzaria-plugin://my.plugin/index.html'),
      );
      expect(diagnosticsRuns, 1, reason: 'נסיגה אמיתית מריצה את האבחון');
    });

    test('מצב כפוי לבדיקה נרשם בלי להריץ אבחון', () async {
      logPluginWebViewHwndFallback(
        const WindowsWebViewHwndFallback(stage: 'forced'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));

      expect(errorsFile().readAsStringSync(), contains('Stage: forced'));
      expect(diagnosticsRuns, 0);
    });
  });
}
