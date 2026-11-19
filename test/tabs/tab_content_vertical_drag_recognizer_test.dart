import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/utils/tab_content_vertical_drag_recognizer.dart';
import 'package:otzaria/tabs/utils/touch_tab_swipe_recognizer.dart';

void main() {
  Future<bool> swipeStarted(
    WidgetTester tester, {
    required bool contentIsWebView,
  }) async {
    var started = false;
    await tester.pumpWidget(
      RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TabContentVerticalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                TabContentVerticalDragRecognizer
              >(
                () => TabContentVerticalDragRecognizer(
                  contentIsWebView: () => contentIsWebView,
                ),
                (recognizer) => recognizer.onStart = (_) {},
              ),
          TouchTabSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<TouchTabSwipeRecognizer>(
                () => TouchTabSwipeRecognizer(
                  singleFingerPansContent: () => false,
                ),
                (recognizer) => recognizer.onStart = (_) => started = true,
              ),
        },
        child: const SizedBox.expand(),
      ),
    );
    final gesture = await tester.startGesture(
      const Offset(300, 400),
      kind: PointerDeviceKind.touch,
    );
    // גלילה אנכית במגע עם סטייה אופקית של 1:3.
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(4, -12));
    }
    await gesture.up();
    return started;
  }

  testWidgets('גלילה אנכית במגע מעל WebView אינה מתחילה החלקת טאב (#3048)', (
    tester,
  ) async {
    expect(await swipeStarted(tester, contentIsWebView: true), isFalse);
  });

  testWidgets('בלי WebView נשמר הסף הכפול שממתין לגלילת PDF (#1982)', (
    tester,
  ) async {
    // אין כאן מזהה גלילה של תוכן, ולכן ההחלקה זוכה לפני הסף הכפול.
    expect(await swipeStarted(tester, contentIsWebView: false), isTrue);
  });

  testWidgets('תזוזה אנכית של אצבע אחת אינה מבטלת החלקה בשתי אצבעות', (
    tester,
  ) async {
    Offset? panAtEnd;
    late TouchTabSwipeRecognizer swipe;
    await tester.pumpWidget(
      RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TabContentVerticalDragRecognizer:
              GestureRecognizerFactoryWithHandlers<
                TabContentVerticalDragRecognizer
              >(
                TabContentVerticalDragRecognizer.new,
                (recognizer) => recognizer.onStart = (_) {},
              ),
          TouchTabSwipeRecognizer:
              GestureRecognizerFactoryWithHandlers<TouchTabSwipeRecognizer>(
                () => swipe = TouchTabSwipeRecognizer(
                  singleFingerPansContent: () => false,
                ),
                (recognizer) => recognizer.onEnd = (_) => panAtEnd = swipe.pan,
              ),
        },
        child: const SizedBox.expand(),
      ),
    );
    final first = await tester.startGesture(const Offset(250, 250));
    final second = await tester.startGesture(const Offset(300, 250));
    await first.moveBy(const Offset(28, 0));
    await second.moveBy(const Offset(28, 0));
    await first.moveBy(const Offset(0, 150));
    await first.up();
    await second.moveBy(const Offset(120, 0));
    await second.up();

    expect(panAtEnd, Offset.zero);
  });
}
