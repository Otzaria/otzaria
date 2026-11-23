import 'package:flutter/gestures.dart';

/// החלקה בין כרטיסיות במסך מגע בדסקטופ.
///
/// שתי אצבעות בתנועה מקבילה מעבירות כרטיסיה; צביטה נשארת בתוכן.
/// אצבע אחת מעבירה רק כשהתוכן לא גולל לרוחב בעצמו.
class TouchTabSwipeRecognizer extends HorizontalDragGestureRecognizer {
  TouchTabSwipeRecognizer({
    required this.singleFingerPansContent,
    super.debugOwner,
  }) : super(supportedDevices: const {PointerDeviceKind.touch});

  /// האם אצבע אחת מזיזה כעת את התוכן לרוחב (למשל PDF מוגדל).
  final bool Function() singleFingerPansContent;

  final Map<int, Offset> _downPointers = {};

  /// התזוזה במחווה חד־אצבעתית. בכמה אצבעות המצביע שמניע את הטאב עשוי להתחלף.
  Offset get pan => _hadMultiplePointers ? Offset.zero : _pan;
  Offset _pan = Offset.zero;
  bool _hadMultiplePointers = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_downPointers.isEmpty) {
      _pan = Offset.zero;
      _hadMultiplePointers = false;
    } else {
      _hadMultiplePointers = true;
    }
    _downPointers[event.pointer] = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!_hadMultiplePointers) _pan += event.delta;
      _downPointers[event.pointer] =
          _downPointers[event.pointer]! + event.delta;
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downPointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      ) &&
      (_downPointers.length >= 2
          ? _isParallelDrag(pointerDeviceKind)
          : !singleFingerPansContent());

  bool _isParallelDrag(PointerDeviceKind kind) {
    final slop = computeHitSlop(kind, gestureSettings);
    final first = _downPointers.values.first;
    return _downPointers.values.every(
      (delta) =>
          delta.dx.abs() > slop &&
          delta.dx * first.dx > 0 &&
          (delta - first).distance < slop,
    );
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downPointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  String get debugDescription => 'touch tab swipe';
}
