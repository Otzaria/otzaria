import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// GestureDetector משופר שמזהה כוונת בחירה vs. פעולה רגילה
///
/// תיעדוף Gestures:
/// - Drag → מצב בחירה (SelectionArea מטפל)
/// - Double-click → בחירת פסקה (SelectionArea מטפל)
/// - Shift+Click → בחירת טווח (SelectionArea מטפל)
/// - Single click (ללא Shift, ללא drag) → פעולה רגילה
class EnhancedGestureDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onShiftClick;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onDragSelectionStart;
  final HitTestBehavior? behavior;

  const EnhancedGestureDetector({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onShiftClick,
    this.onSecondaryTapDown,
    this.onDragSelectionStart,
    this.behavior,
  });

  @override
  State<EnhancedGestureDetector> createState() =>
      _EnhancedGestureDetectorState();
}

class _EnhancedGestureDetectorState extends State<EnhancedGestureDetector> {
  Offset? _tapDownPosition;
  int? _tapDownButtons;
  int? _lastTapTime;
  int _tapCount = 0;
  bool _pointerMoved = false;
  static const int _doubleTapTimeout = 300;
  static const double _dragThreshold = 2.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: widget.behavior ?? HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerMove: _handlePointerMove,
      child: widget.child,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _tapDownPosition = event.localPosition;
    _tapDownButtons = event.buttons;
    _pointerMoved = false;

    if (event.buttons == kSecondaryMouseButton) {
      widget.onSecondaryTapDown?.call(
        TapDownDetails(
          globalPosition: event.position,
          localPosition: event.localPosition,
        ),
      );
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_tapDownPosition != null && _tapDownButtons == kPrimaryMouseButton) {
      final distance = (event.localPosition - _tapDownPosition!).distance;
      if (distance > 0.0) {
        _pointerMoved = true;
      }
      if (distance > _dragThreshold) {
        widget.onDragSelectionStart?.call();
        _tapDownPosition = null;
        _tapDownButtons = null;
        _pointerMoved = false;
        _tapCount = 0;
        _lastTapTime = null;
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_tapDownButtons == kSecondaryMouseButton) {
      _tapDownPosition = null;
      _tapDownButtons = null;
      _pointerMoved = false;
      return;
    }

    if (_tapDownPosition == null) {
      _pointerMoved = false;
      return;
    }

    // Any movement usually indicates selection intent, not a plain tap.
    if (_pointerMoved) {
      _tapDownPosition = null;
      _tapDownButtons = null;
      _pointerMoved = false;
      return;
    }

    final distance = (event.localPosition - _tapDownPosition!).distance;
    if (distance > _dragThreshold) {
      _tapDownPosition = null;
      _tapDownButtons = null;
      _pointerMoved = false;
      return;
    }

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (isShiftPressed) {
      widget.onShiftClick?.call();
      _tapDownPosition = null;
      _tapDownButtons = null;
      _pointerMoved = false;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastTapTime != null && (now - _lastTapTime!) < _doubleTapTimeout) {
      _tapCount++;
      if (_tapCount >= 2) {
        widget.onDoubleTap?.call();
        _tapCount = 0;
        _lastTapTime = null;
        _tapDownPosition = null;
        _tapDownButtons = null;
        _pointerMoved = false;
        return;
      }
    } else {
      _tapCount = 1;
    }
    _lastTapTime = now;

    Future.delayed(const Duration(milliseconds: _doubleTapTimeout), () {
      if (mounted && _tapCount == 1 && _lastTapTime == now) {
        widget.onSingleTap?.call();
        _tapCount = 0;
        _lastTapTime = null;
      }
    });

    _tapDownPosition = null;
    _tapDownButtons = null;
    _pointerMoved = false;
  }
}
