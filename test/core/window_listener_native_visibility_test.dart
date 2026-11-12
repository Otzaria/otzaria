// Intentional use of window_manager 0.6's legacy facade during the
// staged nativeapi migration; remove after moving these callers to Window.
// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:window_manager/legacy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = PluginRuntimeDispatcher.instance;
  const main = (pluginId: 'native-window', instanceId: 'main');
  const other = (pluginId: 'native-window', instanceId: 'other');
  late AppWindowListener listener;

  // window_manager 0.6's legacy API is backed by nativeapi, without the old
  // MethodChannel. Exercise the app's generic listener contract directly.
  Future<void> nativeEvent(String event) async {
    for (final current in windowManager.listeners) {
      if (!windowManager.listeners.contains(current)) continue;
      current.onWindowEvent(event);
      // The nativeapi bridge dispatches dedicated callbacks as well as the
      // generic event. Tests must reproduce both halves of that contract.
      switch (event) {
        case kWindowEventMinimize:
          current.onWindowMinimize();
        case kWindowEventRestore:
          current.onWindowRestore();
        case kWindowEventMaximize:
          current.onWindowMaximize();
      }
    }
  }

  setUp(() {
    dispatcher.resetVisibilityForTesting();
    dispatcher.setVisiblePluginInstances({main});
    dispatcher.setVisiblePluginInstances({other}, viewId: 7);
    listener = AppWindowListener();
    windowManager.addListener(listener);
  });

  tearDown(() {
    windowManager.removeListener(listener);
    dispatcher.resetVisibilityForTesting();
  });

  test('legacy visibility callbacks update plugin runtime', () async {
    expect(dispatcher.isInstanceShown(main), isTrue);
    await nativeEvent('hide');
    expect(dispatcher.isInstanceShown(main), isFalse);
    expect(dispatcher.isInstanceVisible(main), isTrue);
    expect(dispatcher.isInstanceShown(other), isTrue);
    await nativeEvent('show');
    expect(dispatcher.isInstanceShown(main), isTrue);
    expect(dispatcher.isInstanceShown(other), isTrue);
  });

  test('native show restores a hidden window without a focus event', () async {
    dispatcher.setWindowShown(false);
    await nativeEvent('show');
    expect(dispatcher.isInstanceShown(main), isTrue);
  });

  test('repeated visibility events preserve the selected tab', () async {
    await nativeEvent('hide');
    await nativeEvent('hide');
    const replacement = (pluginId: 'native-window', instanceId: 'replacement');
    dispatcher.setVisiblePluginInstances({replacement});
    expect(dispatcher.isInstanceShown(replacement), isFalse);
    await nativeEvent('show');
    await nativeEvent('show');
    expect(dispatcher.isInstanceShown(replacement), isTrue);
    expect(dispatcher.isInstanceShown(main), isFalse);
  });

  test('show does not clear the separate minimized state', () async {
    await nativeEvent('minimize');
    await nativeEvent('hide');
    await nativeEvent('show');
    expect(dispatcher.isInstanceShown(main), isFalse);
    await nativeEvent('restore');
    expect(dispatcher.isInstanceShown(main), isTrue);
  });

  test('show keeps a hidden reader screen hidden', () async {
    dispatcher.setReaderScreenVisible(false);
    await nativeEvent('hide');
    await nativeEvent('show');
    expect(dispatcher.isInstanceShown(main), isFalse);
    expect(dispatcher.isInstanceShown(other), isTrue);
  });

  test(
    'blur and unrelated native events do not hide a visible window',
    () async {
      await nativeEvent('blur');
      await nativeEvent('unrelated-visibility-test-event');
      expect(dispatcher.isInstanceShown(main), isTrue);
    },
  );

  test(
    'removed listener no longer receives native visibility events',
    () async {
      windowManager.removeListener(listener);
      await nativeEvent('hide');
      expect(dispatcher.isInstanceShown(main), isTrue);
    },
  );
}
