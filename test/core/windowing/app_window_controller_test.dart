// The 0.6 nativeapi implementation does not install a window_manager
// MethodChannel. Test the actual compatibility adapter with a borrowed native
// window fake instead of silently exercising a channel nobody listens to.
// ignore_for_file: deprecated_member_use

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:window_manager/legacy.dart';

import '../../test_helpers/recording_native_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingNativeWindow native;
  const controller = WindowManagerAppWindowController();
  final runnerCalls = <String>[];

  setUp(() {
    runnerCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RunnerWindowChannel.channel, (call) async {
      runnerCalls.add(call.method);
      return null;
    });
    native = RecordingNativeWindow(maximized: true);
    windowManager.debugBindWindow(native);
  });

  tearDown(() {
    windowManager.debugBindWindow(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RunnerWindowChannel.channel, null);
  });

  test('the controller has the primary window ID by default', () {
    expect(controller.id, AppWindowId.primary);
    expect(
      const WindowManagerAppWindowController(id: AppWindowId('window-2')).id,
      const AppWindowId('window-2'),
    );
  });

  test('simple actions target the borrowed native window', () async {
    await controller.show();
    await controller.focus();
    await controller.minimize();
    await controller.maximize();
    await controller.unmaximize();
    await controller.startDragging();

    expect(native.calls, [
      'show',
      'focus',
      'minimize',
      'maximize',
      'unmaximize',
      'startDragging',
    ]);
  });

  // Non-Windows window_manager.center() calculates monitor work-area
  // alignment through nativeapi DisplayManager. That needs a real display
  // and belongs in a desktop integration test, not a headless unit fake.
  test(
    'Windows centering delegates to the runner instead of nativeapi',
    () async {
      await controller.center();
      expect(runnerCalls, ['centerMainWindow']);
      expect(native.calls, isNot(contains('center')));
    },
    skip: !Platform.isWindows,
  );

  test('show restores a minimized window first', () async {
    native.minimized = true;
    await controller.show();
    expect(native.calls, ['restore', 'show']);
    expect(native.minimized, isFalse);
  });

  test('nativeapi controls dragging, including while fullscreen', () async {
    native.fullScreen = true;
    await controller.startDragging();
    expect(native.calls, ['startDragging']);
  });

  test('state queries observe the current native state', () async {
    native
      ..visible = true
      ..maximized = true
      ..minimized = true
      ..fullScreen = true;

    expect(await controller.isVisible(), isTrue);
    expect(await controller.isMaximized(), isTrue);
    expect(await controller.isMinimized(), isTrue);
    expect(await controller.isFullScreen(), isTrue);
    native.visible = false;
    expect(await controller.isVisible(), isFalse);
  });

  test('title bar honors explicit system button visibility', () async {
    await controller.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    expect(native.calls, [
      'setTitleBarStyle',
      'setWindowControlButtonsVisible',
    ]);
    expect(native.barStyle, TitleBarStyle.hidden);
    expect(native.controlButtonsVisible, isFalse);
  });

  test('geometry is converted into nativeapi units and back', () async {
    await controller.setBounds(const Rect.fromLTWH(10, 20, 500, 300));
    expect(await controller.getBounds(), const Rect.fromLTWH(10, 20, 500, 300));
    await controller.setSize(const Size(300, 400));
    expect(await controller.getBounds(), const Rect.fromLTWH(10, 20, 300, 400));
    await controller.setMinimumSize(const Size(100, 200));
    expect(native.minimum?.width, 100);
    expect(native.minimum?.height, 200);
    await controller.setFullScreen(true);
    expect(native.fullScreen, isTrue);
    expect(
      native.calls,
      containsAllInOrder([
        'setBounds',
        'getBounds',
        'setSize',
        'getBounds',
        'setMinimumSize',
        'setFullScreen',
      ]),
    );
  });
}
