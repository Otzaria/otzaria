// The 0.6 backend is synchronous nativeapi, not a MethodChannel.
// Keep the production reveal path under test with an in-memory native window.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/legacy.dart';

import '../../../integration_test/support/webview_probe_window.dart';
import '../../test_helpers/recording_native_window.dart';

class _ProbeWindow extends RecordingNativeWindow {
  _ProbeWindow()
      : super(visible: false,
              initialBounds: const nativeapi.Rectangle(x: 10, y: 10, width: 240, height: 240));

  // Replaced by the real native Rectangle below during initialization.
  int appearAfterReads = 1;
  int visibilityReads = 0;
  bool wasShown = false;
  bool rejectShow = false;
  List<double>? opacitySequence;
  int opacityReads = 0;

  @override
  void show() {
    if (rejectShow) throw PlatformException(code: 'show-failed');
    super.show();
    wasShown = true;
  }

  @override
  bool get isVisible {
    if (!wasShown || !visible) return false;
    visibilityReads++;
    return visibilityReads >= appearAfterReads;
  }

  @override
  double get opacity {
    final readings = opacitySequence;
    if (readings == null) return windowOpacity;
    final i = opacityReads++;
    return readings[i < readings.length ? i : readings.length - 1];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const splashChannel = MethodChannel('otzaria/splash');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _ProbeWindow window;
  late List<String> events;

  Future<void> pumpFrame() async => events.add('frame');

  setUp(() {
    window = _ProbeWindow();
    windowManager.debugBindWindow(window);
    events = window.calls;
    messenger.setMockMethodCallHandler(splashChannel, (call) async {
      expect(call.method, 'close');
      events.add('splash.close');
      return null;
    });
  });

  tearDown(() {
    windowManager.debugBindWindow(null);
    messenger.setMockMethodCallHandler(splashChannel, null);
  });

  for (final platform in ['windows', 'linux']) {
    test('$platform reveals and sizes the host before sampling', () async {
      final state = await prepareWebViewProbeWindow(
        platform: platform,
        pumpFrame: pumpFrame,
      );
      expect(state['ready'], isTrue);
      expect(state['visible'], isTrue);
      expect(state['minimized'], isFalse);
      expect(state['requestedLogicalSize'], {'width': 1000.0, 'height': 700.0});
      expect((state['logicalBounds'] as Map)['width'], 1000);
      expect(events.indexOf('setSize'), lessThan(events.indexOf('show')));
      expect(events.indexOf('show'), lessThan(events.indexOf('frame')));
      expect(events.indexOf('frame'), lessThan(events.indexOf('splash.close')));
      expect(events.indexOf('splash.close'), lessThan(events.indexOf('getBounds')));
      expect(events.where((event) => event == 'splash.close'), hasLength(1));
      expect(events.where((event) => event == 'frame').length,
          greaterThanOrEqualTo(2));
    });
  }

  test('app-owned splash close requires native visibility', () async {
    window.appearAfterReads = 2;
    final state = await prepareWebViewProbeWindow(
      platform: 'windows',
      pumpFrame: pumpFrame,
      closeNativeSplash: false,
    );
    expect(state['ready'], isTrue);
    expect(window.visibilityReads, 2);
    expect(events, isNot(contains('splash.close')));
    expect(events.where((event) => event == 'show'), hasLength(1));
    expect(events.where((event) => event == 'focus'), hasLength(1));
    expect(events.indexOf('focus'), lessThan(events.indexOf('frame')));
    expect(events.where((event) => event == 'frame'), hasLength(3));
  });

  test('waits for delayed visibility after the native show call', () async {
    window.appearAfterReads = 2;
    final state = await prepareWebViewProbeWindow(
      platform: 'windows',
      pumpFrame: pumpFrame,
    );
    expect(window.visibilityReads, 2);
    expect(state['ready'], isTrue);
    expect(events.where((event) => event == 'show'), hasLength(1));
  });

  test('macOS waits until splash opacity reaches one', () async {
    window.opacitySequence = [0, 0.5, 1];
    final state = await prepareWebViewProbeWindow(
      platform: 'macos',
      pumpFrame: pumpFrame,
    );
    expect(window.opacityReads, 3);
    expect(state['opacity'], 1);
    expect(state['ready'], isTrue);
    expect(events.indexOf('splash.close'), lessThan(events.indexOf('getBounds')));
  });

  test('hidden, minimized or empty host is not ready', () async {
    await prepareWebViewProbeWindow(platform: 'windows', pumpFrame: pumpFrame);
    window.visible = false;
    expect((await readWebViewProbeWindow('windows'))['ready'], isFalse);
    window.visible = true;
    window.minimized = true;
    expect((await readWebViewProbeWindow('windows'))['ready'], isFalse);
    window.minimized = false;
    window.nativeBounds = const nativeapi.Rectangle(x: 0, y: 0, width: 0, height: 0);
    expect((await readWebViewProbeWindow('windows'))['ready'], isFalse);
    expect(events.where((event) => event == 'show'), hasLength(1));
  });

  test('native visibility timeout does not close the splash', () async {
    window.appearAfterReads = 999999;
    await expectLater(
      prepareWebViewProbeWindow(
        platform: 'windows',
        pumpFrame: pumpFrame,
        timeout: const Duration(milliseconds: 500),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(events, contains('show'));
    expect(events, contains('splash.close'));
    expect(window.visibilityReads, greaterThanOrEqualTo(1));
  });

  test('a transparent macOS window fails readiness with a timeout', () async {
    window.windowOpacity = 0;
    await expectLater(
      prepareWebViewProbeWindow(
        platform: 'macos',
        pumpFrame: pumpFrame,
        timeout: const Duration(milliseconds: 500),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(events, contains('splash.close'));
    expect(window.opacityReads, 0);
  });

  test('native errors propagate rather than masquerading as readiness', () async {
    window.rejectShow = true;
    await expectLater(
      prepareWebViewProbeWindow(platform: 'windows', pumpFrame: pumpFrame),
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'show-failed')),
    );
    expect(events, isNot(contains('splash.close')));
  });

  for (final platform in ['android', 'ios', 'web']) {
    test('$platform skips desktop windows and makes no visibility claim',
        () async {
      final state = await prepareWebViewProbeWindow(
        platform: platform,
        pumpFrame: pumpFrame,
      );
      expect(state['availability'], 'unsupported');
      expect(state.containsKey('ready'), isFalse);
      expect(state.containsKey('visible'), isFalse);
      expect(events, isEmpty);
    });
  }
}
