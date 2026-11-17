import 'package:flutter/gestures.dart';

/// החלקה בין כרטיסיות בלוח מגע, שזוכרת גם את התזוזה האנכית של המחווה.
class TrackpadTabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  TrackpadTabSwipeRecognizer({super.debugOwner})
    : super(supportedDevices: const {PointerDeviceKind.trackpad});

  /// התזוזה המצטברת של המחווה האחרונה בשני הצירים.
  Offset get pan => _pan;
  Offset _pan = Offset.zero;

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _pan = Offset.zero;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    // localPan כולל גם את הזזת הרכיב; דלתאות שומרות רק את התנועה.
    if (event is PointerPanZoomUpdateEvent) _pan += event.localPanDelta;
    super.handleEvent(event);
  }

  @override
  String get debugDescription => 'trackpad tab swipe';
}
