import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// Runner restore/raise must resume main-window plugins without changing
/// visibility of other windows or the separate minimized state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = PluginRuntimeDispatcher.instance;
  const main = (pluginId: 'runner-restore', instanceId: 'main');
  const other = (pluginId: 'runner-restore', instanceId: 'other');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  Object? restoreResult;
  bool failRaise = false;

  setUp(() {
    calls.clear();
    restoreResult = true;
    failRaise = false;
    RunnerWindowChannel.debugSupportedOverride = true;
    messenger.setMockMethodCallHandler(RunnerWindowChannel.channel, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'restoreLastClosedWindow':
          return restoreResult;
        case 'raiseSelf':
          if (failRaise) throw PlatformException(code: 'gone');
          return null;
      }
      return null;
    });
    dispatcher.resetVisibilityForTesting();
    dispatcher.setVisiblePluginInstances({main});
    dispatcher.setVisiblePluginInstances({other}, viewId: 7);
    // As AppWindowListener does before RunnerWindowChannel.closeSelf.
    dispatcher.setWindowShown(false);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(RunnerWindowChannel.channel, null);
    RunnerWindowChannel.debugSupportedOverride = null;
    dispatcher.resetVisibilityForTesting();
  });

  test('restoring the closed main window shows its plugins again', () async {
    expect(dispatcher.isInstanceShown(main), isFalse);
    expect(await const RunnerWindowChannel().restoreLastClosedWindow(), isTrue);
    expect(calls, ['restoreLastClosedWindow']);
    expect(dispatcher.isInstanceShown(main), isTrue);
    expect(dispatcher.isInstanceShown(other), isTrue);
  });

  test(
    'a runner that restored nothing leaves the main window hidden',
    () async {
      restoreResult = false;
      expect(
        await const RunnerWindowChannel().restoreLastClosedWindow(),
        isFalse,
      );
      expect(dispatcher.isInstanceShown(main), isFalse);
    },
  );

  test('raising the main window shows a closed main window again', () async {
    await const RunnerWindowChannel().raiseSelf();
    expect(calls, ['raiseSelf']);
    expect(dispatcher.isInstanceShown(main), isTrue);
  });

  test('a failed raise does not report the window as shown', () async {
    failRaise = true;
    await const RunnerWindowChannel().raiseSelf();
    expect(dispatcher.isInstanceShown(main), isFalse);
  });

  test('without a runner nothing is reported', () async {
    RunnerWindowChannel.debugSupportedOverride = false;
    expect(
      await const RunnerWindowChannel().restoreLastClosedWindow(),
      isFalse,
    );
    await const RunnerWindowChannel().raiseSelf();
    expect(calls, isEmpty);
    expect(dispatcher.isInstanceShown(main), isFalse);
  });

  test('a restored main window stays separately minimized', () async {
    dispatcher.setWindowMinimized(true);
    addTearDown(() => dispatcher.setWindowMinimized(false));
    await const RunnerWindowChannel().restoreLastClosedWindow();
    expect(dispatcher.isInstanceShown(main), isFalse);
    dispatcher.setWindowMinimized(false);
    expect(dispatcher.isInstanceShown(main), isTrue);
  });
}
