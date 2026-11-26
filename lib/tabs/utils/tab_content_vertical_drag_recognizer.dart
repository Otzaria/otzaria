import 'package:flutter/gestures.dart';
import 'package:otzaria/tabs/utils/trackpad_tab_swipe_recognizer.dart';

/// מונע מעבר טאב בגלילה אנכית, בלי לתפוס את גלילת ה-PDF במגע.
class TabContentVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  TabContentVerticalDragRecognizer({this.contentIsWebView = _never})
    : super(
        supportedDevices: const {
          PointerDeviceKind.trackpad,
          PointerDeviceKind.touch,
        },
      );

  /// האם התוכן שמתחת הוא WebView, שאין בו מזהה גלילה של Flutter.
  final bool Function() contentIsWebView;

  static bool _never() => false;

  @override
  void handleEvent(PointerEvent event) {
    // בלוח מגע הבולען רק מחזיק את הזירה פתוחה עד שהכיוון ברור; בגלילה
    // אנכית הוא יוצא יחד עם ההחלקה, והגלילה זוכה בלי לבלוע את הסף (#3975).
    if (event is PointerPanZoomUpdateEvent &&
        !contentIsWebView() &&
        TrackpadTabSwipeRecognizer.isVerticalPan(event.pan)) {
      resolve(GestureDisposition.rejected);
      return;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      (pointerDeviceKind == PointerDeviceKind.touch && !contentIsWebView()
          // במגע הגלילה של pdfrx צריכה לזכות לפני הבולען האנכי. מעל WebView
          // סף כזה מפסיד להחלקה האופקית (kTouchSlop) בכל סטייה קטנה.
          ? kPanSlop * 2
          : computeHitSlop(pointerDeviceKind, gestureSettings));
}
