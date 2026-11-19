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

  testWidgets('מעל PDF הבולען ממתין לגלילה של התוכן (#1982)', (tester) async {
    // אין כאן מזהה גלילה של PDF, ולכן ההחלקה זוכה לפני הסף הכפול.
    expect(await swipeStarted(tester, contentIsWebView: false), isTrue);
  });
}
