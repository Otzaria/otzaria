import 'package:flutter/gestures.dart';
import 'package:otzaria/widgets/misc/touch_pinch_scale_recognizer.dart';

/// החלקה בין כרטיסיות בלוח מגע, שזוכרת גם את התזוזה האנכית של המחווה.
class TrackpadTabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  TrackpadTabSwipeRecognizer({super.debugOwner})
    : super(supportedDevices: const {PointerDeviceKind.trackpad});

  /// התזוזה המצטברת של המחווה האחרונה בשני הצירים.
  Offset get pan => _pan;
  Offset _pan = Offset.zero;
  bool _accepted = false;

  /// מבטל מעבר טאב כשקנה המידה משתנה אחרי הזכייה בזירת המחוות.
  void Function()? onPinchAfterAcceptance;

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _pan = Offset.zero;
    _accepted = false;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      // צביטה שייכת לתוכן גם כשמרכזה זז לרוחב (#3972).
      if ((event.scale - 1).abs() >
          TouchPinchScaleRecognizer.trackpadScaleSlop) {
        if (_accepted) {
          onPinchAfterAcceptance?.call();
        } else {
          resolve(GestureDisposition.rejected);
        }
        return;
      }
      // localPan כולל גם את הזזת הרכיב; דלתאות שומרות רק את התנועה.
      _pan += event.localPanDelta;
    }
    super.handleEvent(event);
  }

  @override
  void acceptGesture(int pointer) {
    _accepted = true;
    super.acceptGesture(pointer);
  }

  @override
  String get debugDescription => 'trackpad tab swipe';
}
