import 'package:flutter/gestures.dart';

/// צביטת מגע שמנצחת גלילה כבר בשינוי קטן במרחק בין שתי אצבעות,
/// כל עוד השינוי גובר על התזוזה המשותפת שלהן (גלילה או החלקת כרטיסיות).
class TouchPinchScaleRecognizer extends ScaleGestureRecognizer {
  TouchPinchScaleRecognizer({super.debugOwner});

  final Map<int, Offset> _touches = {};
  double? _startSpan;
  Offset? _startCentroid;
  final Set<int> _movedSinceCheck = {};

  double get _span =>
      (_touches.values.first - _touches.values.elementAt(1)).distance;

  Offset get _centroid =>
      (_touches.values.first + _touches.values.elementAt(1)) / 2;

  void _resetStart() {
    final hasPair = _touches.length >= 2;
    _startSpan = hasPair ? _span : null;
    _startCentroid = hasPair ? _centroid : null;
    _movedSinceCheck.clear();
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.position;
    _resetStart();
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (!_touches.containsKey(event.pointer)) return;
    if (event is PointerMoveEvent) {
      // כל אצבע מדווחת בנפרד: בודקים רק כשכולן דיווחו, או כשאחת דיווחה פעמיים
      // (השנייה נייחת) - אחרת תזוזה משותפת נראית לרגע כצביטה.
      if (_movedSinceCheck.contains(event.pointer)) _checkPinch();
      _touches[event.pointer] = event.position;
      _movedSinceCheck.add(event.pointer);
      if (_movedSinceCheck.length >= _touches.length) _checkPinch();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touches.remove(event.pointer);
      _resetStart();
    }
  }

  void _checkPinch() {
    _movedSinceCheck.clear();
    final startSpan = _startSpan;
    if (startSpan == null) return;
    final spanChange = (_span - startSpan).abs();
    // אצבע נייחת ואחת זזה: השינוי כפול מתזוזת המרכז; תזוזה משותפת: פחות.
    if (spanChange > kTouchSlop / 2 &&
        spanChange > 1.5 * (_centroid - _startCentroid!).distance) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _touches.clear();
    _resetStart();
    super.didStopTrackingLastPointer(pointer);
  }
}
