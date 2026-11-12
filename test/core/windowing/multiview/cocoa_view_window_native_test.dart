import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

/// ה-runner של macOS לפי החוזה של `otzaria/view_window` (ViewWindowChannel.swift).
class _FakeRunner {
  final List<MethodCall> calls = [];
  Map<String, Object?>? frame = {'x': 100.0, 'y': 50.0, 'width': 800.0};
  Map<String, Object?>? visibleFrame = {
    'x': 0.0,
    'y': 25.0,
    'width': 1440.0,
    'height': 875.0,
    'scale': 2.0,
  };
  bool ready = true;
  bool zoomed = false;
  bool cloakResult = false;
  Set<int> knownHandles = {7};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'multiViewReady':
        return ready;
      case 'multiViewStatus':
        return 'ivar _multiViewEnabled not found';
      case 'keyWindow':
        return 7;
      case 'enableReopenHandling':
        return null;
    }
    final handle = (call.arguments as Map)['handle'];
    if (!knownHandles.contains(handle)) {
      throw PlatformException(code: 'unknown_window');
    }
    return switch (call.method) {
      'frame' => frame == null ? null : {...frame!, 'height': 600.0},
      'placement' =>
        frame == null
            ? null
            : {...frame!, 'height': 600.0, 'maximized': zoomed},
      'visibleFrame' => visibleFrame,
      'isVisible' => true,
      'cloak' => cloakResult,
      'reveal' => true,
      _ => null,
    };
  }

  List<String> get methods => [for (final c in calls) c.method];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = CocoaViewWindowNative.defaultChannel;
  const native = CocoaViewWindowNative();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeRunner runner;

  setUp(() {
    runner = _FakeRunner();
    messenger.setMockMethodCallHandler(channel, runner.handle);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final (initial, saved) in [
    (
      const Rect.fromLTWH(100, 100, 800, 600),
      const Rect.fromLTWH(1500, 100, 800, 600),
    ),
    (
      const Rect.fromLTWH(1500, 100, 800, 600),
      const Rect.fromLTWH(100, 100, 800, 600),
    ),
    (
      const Rect.fromLTWH(100, 100, 800, 600),
      const Rect.fromLTWH(-1600, -100, 800, 600),
    ),
  ]) {
    test('שחזור בין מסכי 1x/2x: $saved', () async {
      // Primary: [0,1440) points at 2x. Secondary: [1440,3360) points at 1x.
      // Saved secondary window: x=1500,y=100,w=800,h=600, all at 1x.
      var actual = initial;
      double scale() => actual.center.dx < 1440 ? 2 : 1;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'visibleFrame') {
          return {
            'x': scale() == 2 ? 0.0 : 1440.0,
            'y': 25.0,
            'width': scale() == 2 ? 1440.0 : 1920.0,
            'height': 875.0,
            'scale': scale(),
          };
        }
        if (call.method == 'setFrame') {
          final a = call.arguments as Map;
          actual = Rect.fromLTWH(
            a['x'] as double,
            a['y'] as double,
            a['width'] as double,
            a['height'] as double,
          );
        }
        if (call.method == 'frame') {
          return {
            'x': actual.left,
            'y': actual.top,
            'width': actual.width,
            'height': actual.height,
          };
        }
        return null;
      });
      await native.setWindowRect(7, saved);
      // This is precisely the retry condition used by ViewWindowOpener._place.
      if (await native.windowRect(7) != saved) {
        await native.setWindowRect(7, saved);
      }
      expect(
        actual,
        saved,
        reason: 'המסגרת נשמרת בנקודות, בלי תלות במסך שהחלון נוצר עליו.',
      );
    });
  }

  test('מסגרת: נקודות גלובליות מה-runner, גם ב-Retina', () async {
    expect(
      await native.windowRect(7),
      const Rect.fromLTWH(100, 50, 800, 600),
    );
    expect(runner.methods, ['frame']);
    expect(runner.calls.first.arguments, {'handle': 7});
  });

  test(
    'setWindowRect: נקודות ללא המרה לפי המסך הנוכחי',
    () async {
      await native.setWindowRect(7, const Rect.fromLTWH(100, 50, 800, 600));
      final setFrame = runner.calls.last;
      expect(setFrame.method, 'setFrame');
      expect(setFrame.arguments, {
        'handle': 7,
        'x': 100.0,
        'y': 50.0,
        'width': 800.0,
        'height': 600.0,
      });
    },
  );

  test('אזור עבודה ומיקום: באותו מרחב נקודות, DPI 96 להיסט', () async {
    expect(await native.workArea(7), const Rect.fromLTWH(0, 25, 1440, 875));
    final placement = (await native.placement(7))!;
    expect(placement.normal, const Rect.fromLTWH(100, 50, 800, 600));
    expect(placement.maximized, isFalse);
    expect(placement.dpi, 96);
  });

  test('placement קורא את מצב zoom של החלון מה-runner', () async {
    runner.zoomed = true;
    expect((await native.placement(7))!.maximized, isTrue);
    runner.zoomed = false;
    expect((await native.placement(7))!.maximized, isFalse);
  });

  test('visibleFrame null (אין מסך): אין אזור עבודה, וקנה המידה 1', () async {
    runner.visibleFrame = null;
    expect(await native.workArea(7), isNull);
    expect(await native.windowRect(7), const Rect.fromLTWH(100, 50, 800, 600));
    expect((await native.placement(7))!.dpi, 96);
    await native.setWindowRect(7, const Rect.fromLTWH(10, 20, 300, 400));
    expect(runner.calls.last.arguments, {
      'handle': 7,
      'x': 10.0,
      'y': 20.0,
      'width': 300.0,
      'height': 400.0,
    });
  });

  test(
    'ידית שאינה מוכרת (unknown_window): ערכי ברירת מחדל, בלי חריגה',
    () async {
      expect(await native.windowRect(99), isNull);
      expect(await native.workArea(99), isNull);
      expect(await native.placement(99), isNull);
      expect(await native.isVisible(99), isFalse);
      await native.focus(99);
      await native.setWindowRect(99, const Rect.fromLTWH(0, 0, 10, 10));
    },
  );

  test('פעולות החלון: שמות המתודות של ה-runner', () async {
    await native.show(7);
    await native.focus(7);
    await native.startDragging(7);
    expect(await native.isVisible(7), isTrue);
    expect(await native.foregroundWindow(), 7);
    expect(runner.methods, [
      'orderFront',
      'makeKey',
      'startDragging',
      'isVisible',
      'keyWindow',
    ]);
    expect(runner.calls.last.arguments, isNull);
  });

  test('אין בערוץ: הסתרה, שינוי גודל מקצה, הגדלה אנכית ותיקוני קלט', () async {
    await native.hide(7);
    await native.startResizing(7, ResizeEdge.left);
    await native.maximizeVertically(7);
    await native.installViewHooks(7);
    expect(runner.calls, isEmpty);
  });

  test(
    'makeFrameless: cloak ואז makeFrameless, גם כש-cloak מחזיר false',
    () async {
      // false הוא גם "כבר מוסתר" (ה-hook תפס את החלון), ולא "אינו חלון Dart".
      runner.cloakResult = false;
      await native.makeFrameless(7);
      expect(runner.methods, ['cloak', 'makeFrameless']);
      expect(
        runner.calls.every((c) => (c.arguments as Map)['handle'] == 7),
        isTrue,
      );
    },
  );

  test('reveal: עם הפעלה', () async {
    await native.reveal(7);
    expect(runner.calls.single.method, 'reveal');
    expect(runner.calls.single.arguments, {'handle': 7, 'activate': true});
  });

  group('handshake', () {
    test('מוכן: null, בלי שאלת סטטוס', () async {
      expect(await native.multiViewUnavailableReason(), isNull);
      expect(runner.methods, ['multiViewReady']);
    });

    test('לא מוכן: הסיבה מ-multiViewStatus', () async {
      runner.ready = false;
      expect(
        await native.multiViewUnavailableReason(),
        'ivar _multiViewEnabled not found',
      );
      expect(runner.methods, ['multiViewReady', 'multiViewStatus']);
    });

    test('runner בלי הערוץ: סיבה, בלי חריגה', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await native.multiViewUnavailableReason(),
        'runner without otzaria/view_window',
      );
    });

    test('runner שאינו עונה: timeout', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      expect(
        await native.multiViewUnavailableReason(
          timeout: const Duration(milliseconds: 10),
        ),
        startsWith('no answer'),
      );
    });
  });

  group('Dock', () {
    Future<Object?> reopenRequested() async {
      final reply = await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('reopenRequested')),
        null,
      );
      return reply == null ? null : channel.codec.decodeEnvelope(reply);
    }

    tearDown(() => channel.setMethodCallHandler(null));

    test('ה-handler מותקן לפני enableReopenHandling, ותשובתו חוזרת', () async {
      var reopens = 0;
      var handlerReadyAtEnable = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'enableReopenHandling') {
          handlerReadyAtEnable = await reopenRequested() == true;
          reopens = 0;
        }
        return runner.handle(call);
      });

      await native.handleDockReopen(() async {
        reopens++;
        return true;
      });

      expect(handlerReadyAtEnable, isTrue);
      expect(await reopenRequested(), isTrue);
      expect(reopens, 1);
    });

    test('שחזור שנכשל: false, וה-runner משחזר בעצמו', () async {
      await native.handleDockReopen(() async => throw StateError('db'));
      expect(await reopenRequested(), isFalse);
    });
  });
}
