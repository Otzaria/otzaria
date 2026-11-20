import 'package:flutter/gestures.dart';

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
