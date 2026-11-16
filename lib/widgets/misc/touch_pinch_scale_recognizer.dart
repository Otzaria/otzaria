import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// צביטת מגע שמנצחת גלילה כבר בשינוי קטן במרחק בין שתי אצבעות,
/// כל עוד השינוי גובר על התזוזה המשותפת שלהן (גלילה או החלקת כרטיסיות).
class TouchPinchScaleRecognizer extends ScaleGestureRecognizer {
  TouchPinchScaleRecognizer({super.debugOwner});

  static const double _trackpadScaleSlop = 0.001;

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
    // DirectManipulation שולח רעש scale גם בגלילה; מסננים אותו לפני קבלת צביטה.
    if (event is PointerPanZoomUpdateEvent &&
        (event.scale - 1).abs() > _trackpadScaleSlop) {
      resolve(GestureDisposition.accepted);
    }
    if (!_touches.containsKey(event.pointer)) return;
    if (event is PointerMoveEvent) {
      _touches[event.pointer] = event.position;
      _movedSinceCheck.add(event.pointer);
      if (_movedSinceCheck.length >= _touches.length) {
        _checkPinch();
      } else {
        // אירועים של אותה אצבע יכולים להגיע יחד; ממתינים לפריים לפני הנחת אצבע נייחת.
        final start = _startCentroid;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (identical(start, _startCentroid) && _movedSinceCheck.isNotEmpty) {
            _checkPinch();
          }
        });
        SchedulerBinding.instance.ensureVisualUpdate();
      }
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
  void rejectGesture(int pointer) {
    _touches.remove(pointer);
    _resetStart();
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    _touches.clear();
    _resetStart();
    super.dispose();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _touches.clear();
    _resetStart();
    super.didStopTrackingLastPointer(pointer);
  }
}
