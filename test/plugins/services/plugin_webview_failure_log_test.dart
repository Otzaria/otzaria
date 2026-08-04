import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
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

  test('כשל נרשם ל-errors.txt עם הכותרת והפרטים', () {
    logPluginWebViewFailure(
      'WebView2 environment init failed',
      StateError('boom'),
      details: const {'UserDataFolder': r'C:\data\webview2'},
    );

    final content = errorsFile().readAsStringSync();
    expect(content, contains('WebView2 environment init failed'));
    expect(content, contains('Bad state: boom'));
    expect(content, contains(r'UserDataFolder: C:\data\webview2'));
  });

  test('פרטים ריקים מושמטים מהרשומה', () {
    logPluginWebViewFailure(
      'Plugin WebView2 process failed',
      'RENDER_PROCESS_EXITED',
      details: const {'Plugin': 'my-plugin', 'ExitCode': null},
    );

    final content = errorsFile().readAsStringSync();
    expect(content, contains('Plugin: my-plugin'));
    expect(content, isNot(contains('ExitCode')));
  });
}
