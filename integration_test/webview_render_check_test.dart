// אימות רינדור ומחזור חיים של WebView2 במסלול הסביבה של התוספים.
// הרצה: flutter test integration_test/webview_render_check_test.dart -d windows
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart'
    show WindowsWebViewCreationFailures;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

const String _probeHtml = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>render-check</title></head>
<body><div id="marker">webview-alive</div>
<script>window.probeValue = 41 + 1;</script>
</body>
</html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WebView2 renders after environment dispose and reinitialize',
    (
      tester,
    ) async {
      final dataDir = await Directory.systemTemp.createTemp('wv2_render_check');
      AppPaths.debugOverrideDataRootPath(dataDir.path);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await WebViewEnvironmentHolder.disposeForAppRestart();
        AppPaths.debugOverrideDataRootPath(null);
        try {
          await dataDir.delete(recursive: true);
        } catch (_) {}
      });

      final version = await WebViewEnvironment.getAvailableVersion();
      expect(version, isNotNull, reason: 'WebView2 Runtime חסר במחשב');
      debugPrint('[WebView2 smoke] Runtime: $version');

      await Future.wait([
        WebViewEnvironmentHolder.initialize(),
        WebViewEnvironmentHolder.initialize(),
      ]);
      final firstEnvironment = WebViewEnvironmentHolder.environment;
      expect(firstEnvironment, isNotNull);

      await _renderProbe(tester, firstEnvironment!, phase: 'first environment');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await WebViewEnvironmentHolder.disposeForAppRestart();
      expect(WebViewEnvironmentHolder.environment, isNull);

      await WebViewEnvironmentHolder.initialize();
      final secondEnvironment = WebViewEnvironmentHolder.environment;
      expect(secondEnvironment, isNotNull);
      expect(secondEnvironment, isNot(same(firstEnvironment)));
      await _renderProbe(tester, secondEnvironment!, phase: 'reinitialized');
    },
    skip: !Platform.isWindows,
  );
}

Future<void> _renderProbe(
  WidgetTester tester,
  WebViewEnvironment environment, {
  required String phase,
}) async {
  final controllerCompleter = Completer<InAppWebViewController>();
  final loadedCompleter = Completer<void>();
  final webViewKey = UniqueKey();
  final events = <String>[];
  final creationFailures = WindowsWebViewCreationFailures.stream.listen((
    failure,
  ) {
    if (failure.creationKey == webViewKey) {
      events.add('creation failed: ${failure.error}');
    }
  });

  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InAppWebView(
            key: webViewKey,
            webViewEnvironment: environment,
            initialData: InAppWebViewInitialData(data: _probeHtml),
            onWebViewCreated: controllerCompleter.complete,
            onLoadStart: (controller, url) => events.add('load started: $url'),
            onLoadStop: (controller, url) {
              events.add('load stopped: $url');
              if (!loadedCompleter.isCompleted) loadedCompleter.complete();
            },
            onReceivedError: (controller, request, error) => events.add(
              'navigation failed: ${request.url}, '
              'mainFrame=${request.isForMainFrame}, '
              '${error.type}: ${error.description}',
            ),
            onReceivedHttpError: (controller, request, response) => events.add(
              'HTTP failed: ${request.url}, status=${response.statusCode}',
            ),
            onProcessFailed: (controller, detail) => events.add(
              'process failed: ${detail.kind}, reason=${detail.reason}, '
              'exitCode=${detail.exitCode}',
            ),
          ),
        ),
      ),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!loadedCompleter.isCompleted && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      loadedCompleter.isCompleted,
      isTrue,
      reason:
          'הדף לא סיים להיטען תוך 30 שניות — מסך ריק? '
          'phase=$phase, controllerCreated=${controllerCompleter.isCompleted}, '
          'events=$events',
    );

    final controller = await controllerCompleter.future;
    final probe = await controller.evaluateJavascript(
      source: 'window.probeValue',
    );
    expect(probe, 42, reason: 'JS לא רץ בתוך הדף');
    final marker = await controller.evaluateJavascript(
      source: "document.getElementById('marker').textContent",
    );
    expect(marker, 'webview-alive', reason: 'ה-DOM לא רונדר');
  } finally {
    await creationFailures.cancel();
  }
}
