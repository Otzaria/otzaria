// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:otzaria/core/windowing/nativeapi_primary_window_binding.dart';
import 'package:window_manager/legacy.dart';

import '../../test_helpers/recording_native_window.dart';

class _Listener with WindowListener {
  final events = <String>[];

  @override
  void onWindowEvent(String eventName) => events.add(eventName);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    windowManager.debugCurrentWindowOverride = () => null;
  });
  tearDown(() {
    windowManager.bindWindow(null);
    windowManager.debugCurrentWindowOverride = null;
  });

  test('missing or zero runner handles never reach native code', () async {
    var constructions = 0;
    for (final handle in <int?>[null, 0]) {
      expect(
        await bindNativeapiPrimaryWindow(
          nativeHandleProvider: () async => handle,
          windowFactory: (_) {
            constructions++;
            return RecordingNativeWindow();
          },
        ),
        isNull,
      );
    }
    expect(constructions, 0);
  });

  test('binds an existing hidden host before its first show', () async {
    const hwnd = 0x123456789;
    final native = RecordingNativeWindow(visible: false);
    var wrappedAddress = 0;

    final actual = await bindNativeapiPrimaryWindow(
      nativeHandleProvider: () async => hwnd,
      windowFactory: (address) {
        wrappedAddress = address;
        return native;
      },
    );

    expect(actual, hwnd);
    expect(wrappedAddress, hwnd);
    final listener = _Listener();
    windowManager.addListener(listener);
    addTearDown(() async {
      await windowManager.setPreventClose(false);
      windowManager.removeListener(listener);
    });
    await windowManager.setPreventClose(true);
    await native.emit(const nativeapi.WindowFocusedEvent(windowId: 0));
    expect(listener.events, contains('focus'));
    expect(await windowManager.isVisible(), isFalse);
    await windowManager.show();
    expect(native.calls, contains('show'));
    expect(await windowManager.isVisible(), isTrue);
  });

  test('failed native wrapper makes no claim of a bound handle', () async {
    expect(
      await bindNativeapiPrimaryWindow(
        nativeHandleProvider: () async => 42,
        windowFactory: (_) => null,
      ),
      isNull,
    );
  });
}
