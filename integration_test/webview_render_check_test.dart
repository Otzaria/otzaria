// אימות רינדור WebView2 אמיתי במסלול של התוספים: סביבה עם userDataFolder
// מותאם (כמו WebViewEnvironmentHolder) + טעינת דף + הרצת JS.
// הרצה: flutter test integration_test/webview_render_check_test.dart -d windows
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

  testWidgets('WebView2 with custom userDataFolder renders and runs JS', (
    tester,
  ) async {
    final dataDir = await Directory.systemTemp.createTemp('wv2_render_check');
    addTearDown(() async {
      // תהליכי WebView2 עשויים עדיין להחזיק קבצים — מחיקה best-effort.
      try {
        await dataDir.delete(recursive: true);
      } catch (_) {}
    });
    WebViewEnvironment? environment;
    if (Platform.isWindows) {
      final version = await WebViewEnvironment.getAvailableVersion();
      expect(version, isNotNull, reason: 'WebView2 Runtime חסר במחשב');
      environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: dataDir.path),
      );
      // LIFO: ה-dispose שנרשם כאן רץ לפני מחיקת התיקייה שנרשמה למעלה.
      addTearDown(() => environment!.dispose());
    }

    final controllerCompleter = Completer<InAppWebViewController>();
    final loadedCompleter = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InAppWebView(
            webViewEnvironment: environment,
            initialData: InAppWebViewInitialData(data: _probeHtml),
            onWebViewCreated: controllerCompleter.complete,
            onLoadStop: (controller, url) {
              if (!loadedCompleter.isCompleted) loadedCompleter.complete();
            },
          ),
        ),
      ),
    );

    // pump ידני: onLoadStop מגיע מהצד הנייטיבי, לא מטיימרים של Flutter.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!loadedCompleter.isCompleted && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(
      loadedCompleter.isCompleted,
      isTrue,
      reason: 'הדף לא סיים להיטען תוך 30 שניות — מסך ריק?',
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
  });
}
