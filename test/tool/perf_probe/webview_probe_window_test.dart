import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/webview_probe_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const splashChannel = MethodChannel('otzaria/splash');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> events;
  late bool visible;
  late bool minimized;
  late double opacity;
  late Rect bounds;
  late Future<Object?> Function(MethodCall) handleWindow;

  Future<Object?> defaultWindowHandler(MethodCall call) async {
    switch (call.method) {
      case 'ensureInitialized':
      case 'focus':
        return null;
      case 'setBounds':
        final args = call.arguments as Map;
        bounds = Rect.fromLTWH(
          bounds.left,
          bounds.top,
          (args['width'] as num).toDouble(),
          (args['height'] as num).toDouble(),
        );
        return null;
      case 'show':
        visible = true;
        return null;
      case 'isVisible':
        return visible;
      case 'isMinimized':
        return minimized;
      case 'restore':
        minimized = false;
        return null;
      case 'getOpacity':
        return opacity;
      case 'getBounds':
        return {
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.width,
          'height': bounds.height,
        };
      default:
        throw StateError('Unexpected window call: ${call.method}');
    }
  }

  Future<void> pumpFrame() async => events.add('frame');

  setUp(() {
    events = [];
    visible = false;
    minimized = false;
    opacity = 1;
    bounds = const Rect.fromLTWH(10, 10, 240, 240);
    handleWindow = defaultWindowHandler;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      events.add(call.method);
      return handleWindow(call);
    });
    messenger.setMockMethodCallHandler(splashChannel, (call) async {
      expect(call.method, 'close');
      events.add('splash.close');
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(splashChannel, null);
  });

  for (final platform in ['windows', 'linux']) {
    test(
      '$platform reveals and sizes the hidden host before sampling',
      () async {
        final state = await prepareWebViewProbeWindow(
          platform: platform,
          pumpFrame: pumpFrame,
        );
        expect(state['ready'], isTrue);
        expect(state['visible'], isTrue);
        expect(state['minimized'], isFalse);
        expect(state['requestedLogicalSize'], {
          'width': 1000.0,
          'height': 700.0,
        });
        expect((state['logicalBounds'] as Map)['width'], 1000);
        expect(
          events.indexOf('ensureInitialized'),
          lessThan(events.indexOf('show')),
        );
        expect(events.indexOf('show'), lessThan(events.indexOf('frame')));
        expect(
          events.indexOf('frame'),
          lessThan(events.indexOf('splash.close')),
        );
        expect(
          events.indexOf('splash.close'),
          lessThan(events.indexOf('isVisible')),
        );
        expect(events.where((event) => event == 'splash.close'), hasLength(1));
        expect(
          events.where((event) => event == 'frame').length,
          greaterThanOrEqualTo(2),
        );
      },
    );
  }

  test('an app-owned splash close still requires native readiness', () async {
    var observations = 0;
    handleWindow = (call) async {
      if (call.method == 'show') return null;
      if (call.method == 'isVisible') return ++observations >= 2;
      return defaultWindowHandler(call);
    };
    final state = await prepareWebViewProbeWindow(
      platform: 'windows',
      pumpFrame: pumpFrame,
      closeNativeSplash: false,
    );
    expect(state['ready'], isTrue);
    expect(state['visible'], isTrue);
    expect(state['minimized'], isFalse);
    expect((state['logicalBounds'] as Map)['width'], 1000);
    expect((state['logicalBounds'] as Map)['height'], 700);
    expect(observations, 2);
    expect(events, isNot(contains('splash.close')));
    expect(events.where((event) => event == 'show'), hasLength(1));
    expect(events.where((event) => event == 'focus'), hasLength(1));
    expect(events.indexOf('focus'), lessThan(events.indexOf('frame')));
    expect(events.where((event) => event == 'frame'), hasLength(3));
  });

  test('waits for delayed native visibility after the show reply', () async {
    var observations = 0;
    handleWindow = (call) async {
      if (call.method == 'show') return null;
      if (call.method == 'isVisible') return ++observations >= 2;
      return defaultWindowHandler(call);
    };
    final state = await prepareWebViewProbeWindow(
      platform: 'windows',
      pumpFrame: pumpFrame,
    );
    expect(observations, 2);
    expect(state['visible'], isTrue);
    expect(state['ready'], isTrue);
    expect(events.where((event) => event == 'show'), hasLength(1));
  });

  test(
    'macOS visibility alone cannot pass while the splash leaves alpha zero',
    () async {
      var opacityReads = 0;
      handleWindow = (call) async {
        if (call.method == 'getOpacity') {
          return [0.0, 0.5, 1.0][opacityReads++];
        }
        return defaultWindowHandler(call);
      };
      final state = await prepareWebViewProbeWindow(
        platform: 'macos',
        pumpFrame: pumpFrame,
      );
      expect(opacityReads, 3);
      expect(state['opacity'], 1);
      expect(state['ready'], isTrue);
      expect(
        events.indexOf('splash.close'),
        lessThan(events.indexOf('getOpacity')),
      );
    },
  );

  test(
    'subsequent boundaries report hidden, minimized or empty hosts as not ready',
    () async {
      await prepareWebViewProbeWindow(
        platform: 'windows',
        pumpFrame: pumpFrame,
      );
      visible = false;
      expect((await readWebViewProbeWindow('windows'))['ready'], isFalse);
      visible = true;
      minimized = true;
      expect((await readWebViewProbeWindow('windows'))['ready'], isFalse);
      minimized = false;
      bounds = Rect.zero;
      expect((await readWebViewProbeWindow('windows'))['ready'], isFalse);
      expect(events.where((event) => event == 'show'), hasLength(1));
    },
  );

  test(
    'a nonresponding native call fails and never continues reveal later',
    () async {
      final showReply = Completer<Object?>();
      handleWindow = (call) async =>
          call.method == 'show' ? showReply.future : defaultWindowHandler(call);
      await expectLater(
        prepareWebViewProbeWindow(
          platform: 'windows',
          pumpFrame: pumpFrame,
          timeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(events, contains('show'));
      final failedEvents = List<String>.of(events);
      showReply.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(events, failedEvents);
      expect(events, isNot(contains('splash.close')));
    },
  );

  test(
    'a transparent macOS window times out instead of reporting ready',
    () async {
      opacity = 0;
      await expectLater(
        prepareWebViewProbeWindow(
          platform: 'macos',
          pumpFrame: pumpFrame,
          timeout: const Duration(milliseconds: 500),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(events, contains('splash.close'));
      expect(events, contains('getOpacity'));
    },
  );

  test(
    'native errors are propagated instead of becoming successful observations',
    () async {
      handleWindow = (call) async {
        if (call.method == 'show') throw PlatformException(code: 'show-failed');
        return defaultWindowHandler(call);
      };
      await expectLater(
        prepareWebViewProbeWindow(platform: 'windows', pumpFrame: pumpFrame),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'show-failed'),
        ),
      );
      expect(events, isNot(contains('splash.close')));
    },
  );

  for (final platform in ['android', 'ios', 'web']) {
    test(
      '$platform skips desktop channels and makes no visibility claim',
      () async {
        final state = await prepareWebViewProbeWindow(
          platform: platform,
          pumpFrame: pumpFrame,
        );
        expect(state['availability'], 'unsupported');
        expect(state.containsKey('ready'), isFalse);
        expect(state.containsKey('visible'), isFalse);
        expect(events, isEmpty);
      },
    );
  }
}
