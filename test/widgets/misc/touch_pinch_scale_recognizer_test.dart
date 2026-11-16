import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';
import 'package:otzaria/widgets/misc/touch_pinch_scale_recognizer.dart';

void main() {
  late int tabSwipeUpdates;
  late int pinchUpdates;
  late int scrollUpdates;

  /// החלקת כרטיסיות מעל צביטה, וגרירה אנכית בפנים כמו רשימת הטקסט.
  Widget buildHarness() {
    tabSwipeUpdates = 0;
    pinchUpdates = 0;
    scrollUpdates = 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RawGestureDetector(
        gestures: {
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(
                () => HorizontalDragGestureRecognizer(
                  supportedDevices: const {PointerDeviceKind.trackpad},
                ),
                (recognizer) => recognizer.onUpdate = (_) => tabSwipeUpdates++,
              ),
          TouchTabSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<TouchTabSwipeRecognizer>(
                () => TouchTabSwipeRecognizer(
                  singleFingerPansContent: () => false,
                ),
                (recognizer) => recognizer.onUpdate = (_) => tabSwipeUpdates++,
              ),
        },
        child: RawGestureDetector(
          gestures: {
            TouchPinchScaleRecognizer:
                GestureRecognizerFactoryWithHandlers<TouchPinchScaleRecognizer>(
                  TouchPinchScaleRecognizer.new,
                  (recognizer) => recognizer.onUpdate = (_) => pinchUpdates++,
                ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (_) => scrollUpdates++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Future<void> moveTwoFingers(
    WidgetTester tester, {
    required Offset firstStart,
    required Offset secondStart,
    required Offset firstStep,
    required Offset secondStep,
    int steps = 10,
  }) async {
    final first = await tester.startGesture(firstStart, pointer: 1);
    final second = await tester.startGesture(secondStart, pointer: 2);
    for (var step = 0; step < steps; step++) {
      // אצבע נייחת לא שולחת אירועי תזוזה.
      if (firstStep != Offset.zero) await first.moveBy(firstStep);
      await second.moveBy(secondStep);
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pump();
  }

  void beginPendingPinch(_RecordingRecognizer recognizer) {
    for (final (pointer, position) in [
      (1, const Offset(300, 200)),
      (2, const Offset(300, 300)),
    ]) {
      final down = PointerDownEvent(pointer: pointer, position: position);
      recognizer.addPointer(down);
      recognizer.handleEvent(down);
    }
    recognizer.handleEvent(
      const PointerMoveEvent(
        pointer: 2,
        position: Offset(300, 312),
        delta: Offset(0, 12),
      ),
    );
  }

  for (final ending in [
    'up',
    'cancel',
    'reject',
    'reject one',
    'dispose',
    'reuse',
  ]) {
    testWidgets('pending pinch is invalidated by $ending', (tester) async {
      final recognizer = _RecordingRecognizer()..onUpdate = (_) {};
      addTearDown(() {
        if (ending != 'dispose') recognizer.dispose();
        for (final pointer in [1, 2]) {
          GestureBinding.instance.gestureArena.close(pointer);
          GestureBinding.instance.gestureArena.sweep(pointer);
        }
      });
      beginPendingPinch(recognizer);
      if (ending == 'dispose') {
        recognizer.dispose();
      } else {
        for (final pointer in ending == 'reject one' ? [1] : [1, 2]) {
          switch (ending) {
            case 'reject':
            case 'reject one':
              recognizer.rejectGesture(pointer);
            case 'cancel':
              recognizer.handleEvent(PointerCancelEvent(pointer: pointer));
            default:
              recognizer.handleEvent(PointerUpEvent(pointer: pointer));
          }
        }
        if (ending == 'reuse') beginPendingPinch(recognizer);
      }
      await tester.pump();
      expect(recognizer.acceptedResolutions, ending == 'reuse' ? 1 : 0);
    });
  }

  for (final scale in [
    1.0,
    1.0000009536743164,
    0.9999990463256836,
    1.0005,
    0.9995,
  ]) {
    for (final horizontal in [false, true]) {
      testWidgets(
        'trackpad pan stays a pan with scale noise=$scale, horizontal=$horizontal',
        (tester) async {
          await tester.pumpWidget(buildHarness());
          final pad = TestPointer(1, PointerDeviceKind.trackpad);
          const position = Offset(300, 250);
          await tester.sendEventToBinding(pad.panZoomStart(position));
          for (var step = 1; step <= 5; step++) {
            await tester.sendEventToBinding(
              pad.panZoomUpdate(
                position,
                pan: horizontal
                    ? Offset(step * 20.0, 0)
                    : Offset(0, step * 20.0),
                scale: scale,
              ),
            );
            await tester.pump();
          }
          await tester.sendEventToBinding(pad.panZoomEnd());
          await tester.pump();
          expect(tabSwipeUpdates, horizontal ? greaterThan(0) : 0);
          expect(scrollUpdates, horizontal ? 0 : greaterThan(0));
          expect(pinchUpdates, 0);
        },
      );
    }
  }

  testWidgets('a small one-sided pinch zooms instead of scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());
    await moveTwoFingers(
      tester,
      firstStart: const Offset(300, 200),
      secondStart: const Offset(300, 300),
      firstStep: Offset.zero,
      secondStep: const Offset(0, 5),
      steps: 5,
    );

    expect(pinchUpdates, greaterThan(0));
    expect(scrollUpdates, 0);
  });

  testWidgets('an uneven two-finger horizontal swipe switches tabs', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness());
    await moveTwoFingers(
      tester,
      firstStart: const Offset(200, 250),
      secondStart: const Offset(400, 250),
      firstStep: const Offset(5, 0),
      secondStep: const Offset(3, 0),
    );

    expect(pinchUpdates, 0);
    expect(tabSwipeUpdates, greaterThan(0));
  });

  testWidgets('a lagging two-finger vertical drag scrolls', (tester) async {
    await tester.pumpWidget(buildHarness());
    await moveTwoFingers(
      tester,
      firstStart: const Offset(300, 100),
      secondStart: const Offset(300, 220),
      firstStep: const Offset(0, 6),
      secondStep: const Offset(0, 2),
    );

    expect(pinchUpdates, 0);
    expect(scrollUpdates, greaterThan(0));
  });

  testWidgets('a symmetric pinch zooms', (tester) async {
    await tester.pumpWidget(buildHarness());
    await moveTwoFingers(
      tester,
      firstStart: const Offset(300, 200),
      secondStart: const Offset(300, 300),
      firstStep: const Offset(0, -4),
      secondStep: const Offset(0, 4),
      steps: 5,
    );

    expect(pinchUpdates, greaterThan(0));
    expect(scrollUpdates, 0);
  });

  for (final speed in [10.0, 12.0]) {
    testWidgets('a fast parallel swipe switches tabs, ${speed}px/event', (
      tester,
    ) async {
      await tester.pumpWidget(buildHarness());
      await moveTwoFingers(
        tester,
        firstStart: const Offset(200, 250),
        secondStart: const Offset(400, 250),
        firstStep: Offset(speed, 0),
        secondStep: Offset(speed, 0),
      );

      expect(pinchUpdates, 0);
      expect(tabSwipeUpdates, greaterThan(0));
    });

    testWidgets('a fast stacked vertical drag scrolls, ${speed}px/event', (
      tester,
    ) async {
      await tester.pumpWidget(buildHarness());
      await moveTwoFingers(
        tester,
        firstStart: const Offset(300, 100),
        secondStart: const Offset(300, 220),
        firstStep: Offset(0, speed),
        secondStep: Offset(0, speed),
      );

      expect(pinchUpdates, 0);
      expect(scrollUpdates, greaterThan(0));
    });
  }
}

class _RecordingRecognizer extends TouchPinchScaleRecognizer {
  int acceptedResolutions = 0;

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted) acceptedResolutions++;
    super.resolve(disposition);
  }
}
