import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';

class _RecordingController extends Fake implements InAppWebViewController {
  final calls = <String>[];

  @override
  Future<dynamic> callDevToolsProtocolMethod({
    required String methodName,
    Map<String, dynamic>? parameters,
  }) async {
    calls.add('$methodName $parameters');
    if (calls.length == 1) throw Exception('CDP לא זמין');
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    calls.add('load ${urlRequest.url}');
  }
}

void main() {
  test(
    'שרת פיתוח נטען רק אחרי עקיפת המטמון וה-service worker (issue #2060)',
    () async {
      final controller = _RecordingController();

      await loadPluginDevServer(controller, WebUri('http://localhost:3000'));

      expect(controller.calls.last, 'load http://localhost:3000');
      if (Platform.isWindows) {
        expect(controller.calls, [
          'Network.setCacheDisabled {cacheDisabled: true}',
          'Network.setBypassServiceWorker {bypass: true}',
          'load http://localhost:3000',
        ]);
      }
    },
  );
}
