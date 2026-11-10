// Intentional use of window_manager 0.6's legacy facade during the
// staged nativeapi migration; remove after moving these callers to Window.
// ignore_for_file: deprecated_member_use

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:otzaria/core/windowing/main_window_binding.dart';
import 'package:window_manager/legacy.dart';

import '../../test_helpers/recording_native_window.dart';

class _Listener with WindowListener {
  final events = <String>[];

  @override
  void onWindowEvent(String eventName) => events.add(eventName);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => windowManager.debugBindWindow(null));

  test('binds the runner HWND before listeners and prevent-close', () async {
    final native = RecordingNativeWindow();
    final created = <int>[];
    final hwnd = await bindMainWindowHandle(
      mainWindowHandle: () async => 0x7FFF12345678,
      createWindow: (hwnd) {
        created.add(hwnd);
        return native;
      },
    );
    expect(hwnd, 0x7FFF12345678);
    expect(created, [0x7FFF12345678]);

    // What main() does next: the listener and prevent-close reach the bound
    // window, not whichever window is active.
    final listener = _Listener();
    windowManager.addListener(listener);
    addTearDown(() => windowManager.removeListener(listener));
    await windowManager.setPreventClose(true);
    addTearDown(() => windowManager.setPreventClose(false));

    await native.emit(const nativeapi.WindowFocusedEvent(windowId: 0));
    expect(listener.events, contains('focus'));
  });

  test('no handle from the runner leaves the default lookup', () async {
    var bound = false;
    expect(
      await bindMainWindowHandle(
        mainWindowHandle: () async => null,
        createWindow: (_) => fail('no window without a handle'),
        bindWindow: (_) => bound = true,
      ),
      isNull,
    );
    expect(
      await bindMainWindowHandle(
        mainWindowHandle: () async => 0,
        createWindow: (_) => fail('no window without a handle'),
        bindWindow: (_) => bound = true,
      ),
      isNull,
    );
    expect(bound, isFalse);
  });

  test('a channel failure does not break startup', () async {
    var bound = false;
    expect(
      await bindMainWindowHandle(
        mainWindowHandle: () async =>
            throw PlatformException(code: 'unavailable'),
        bindWindow: (_) => bound = true,
      ),
      isNull,
    );
    expect(bound, isFalse);
  });

  test('the HWND is still returned when nativeapi cannot wrap it', () async {
    var bound = false;
    expect(
      await bindMainWindowHandle(
        mainWindowHandle: () async => 42,
        createWindow: (_) => null,
        bindWindow: (_) => bound = true,
      ),
      42,
    );
    expect(bound, isFalse);
  });
}
