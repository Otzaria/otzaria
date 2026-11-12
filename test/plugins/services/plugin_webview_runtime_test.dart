import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_runtime.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';

class _Controller extends Fake implements InAppWebViewController {}

class _Runtime extends Fake implements PluginRuntime {}

void main() {
  final d = PluginRuntimeDispatcher.instance;
  const pid = 'webview.runtime.identity';

  tearDown(() => d.unregisterController(pid));

  test('the same controller always maps to the same runtime', () {
    final controller = _Controller();
    expect(
      identical(
        WebViewPluginRuntime.of(controller),
        WebViewPluginRuntime.of(controller),
      ),
      isTrue,
    );
    expect(
      identical(
        WebViewPluginRuntime.of(controller),
        WebViewPluginRuntime.of(_Controller()),
      ),
      isFalse,
    );
  });

  test('a registered controller is owned and reachable as a WebView', () {
    final controller = _Controller();
    d.registerController(pid, controller);
    expect(d.ownsController(pid, controller), isTrue);
    expect(d.ownsController(pid, _Controller()), isFalse);
    expect(d.controllerOf(pid), same(controller));
    expect(d.runtimeOf(pid), same(WebViewPluginRuntime.of(controller)));
  });

  test('a non-WebView runtime has no controller', () {
    d.registerRuntime(pid, _Runtime());
    expect(d.runtimeOf(pid), isNotNull);
    expect(d.controllerOf(pid), isNull);
  });
}
