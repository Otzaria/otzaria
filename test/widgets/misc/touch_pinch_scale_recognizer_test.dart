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
    }
    await first.up();
    await second.up();
    await tester.pump();
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
