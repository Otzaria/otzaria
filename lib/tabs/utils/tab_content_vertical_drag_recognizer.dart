import 'package:flutter/gestures.dart';

/// מונע מעבר טאב בגלילה אנכית, בלי לתפוס את גלילת ה-PDF במגע.
class TabContentVerticalDragRecognizer extends VerticalDragGestureRecognizer {
  TabContentVerticalDragRecognizer()
    : super(
        supportedDevices: const {
          PointerDeviceKind.trackpad,
          PointerDeviceKind.touch,
        },
      );

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      (pointerDeviceKind == PointerDeviceKind.touch
          // במגע הגלילה של pdfrx צריכה לזכות לפני הבולען האנכי.
          ? kPanSlop * 2
          : computeHitSlop(pointerDeviceKind, gestureSettings));
}
