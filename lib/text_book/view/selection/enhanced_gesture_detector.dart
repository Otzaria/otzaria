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
  final VoidCallback? onCtrlClick;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onDragSelectionStart;
  final HitTestBehavior? behavior;

  const EnhancedGestureDetector({
    super.key,
    required this.child,
    this.onSingleTap,
    this.onDoubleTap,
    this.onShiftClick,
    this.onCtrlClick,
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
  static const int _multiTapTimeout = 300; // זמן מקסימלי בין לחיצות רצופות
  static const double _dragThreshold = 5.0;

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
      if (distance > _dragThreshold) {
        // A drag has started, notify the parent to handle selection
        widget.onDragSelectionStart?.call();
        _tapDownPosition = null;
        // איפוס ספירת הלחיצות כדי לבטל single tap שממתין
        _tapCount = 0;
        _lastTapTime = null;
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_tapDownButtons == kSecondaryMouseButton) {
      _tapDownPosition = null;
      _tapDownButtons = null;
      return;
    }

    // בדיקה שהכפתור ששוחרר הוא הכפתור הראשי
    // לאחר שחרור הכפתור, event.buttons הוא 0, אז אנחנו בודקים שהאירוע הוא מהכפתור הראשי
    if (_tapDownPosition == null) {
      return;
    }

    final distance = (event.localPosition - _tapDownPosition!).distance;
    if (distance > _dragThreshold) {
      _tapDownPosition = null;
      return;
    }

    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    if (isShiftPressed) {
      widget.onShiftClick?.call();
      _tapDownPosition = null;
      return;
    }

    // Ctrl (או Cmd ב-macOS) + לחיצה → הוספת/הסרת קטע מבחירה מרובה.
    final isCtrlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (isCtrlPressed && widget.onCtrlClick != null) {
      widget.onCtrlClick!.call();
      _tapDownPosition = null;
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastTapTime != null && (now - _lastTapTime!) < _multiTapTimeout) {
      _tapCount++;
      if (_tapCount >= 3) {
        // לחיצה משולשת - לא עושים כלום, נותנים ל-SelectionArea לטפל
        // (SelectionArea בוחר את כל הקטע בלחיצה משולשת)
        _tapCount = 0;
        _lastTapTime = null;
        _tapDownPosition = null;
        return;
      }
      if (_tapCount >= 2) {
        widget.onDoubleTap?.call();
        // לא מאפסים את הספירה - ממשיכים לספור ללחיצה שלישית
        _lastTapTime = now;
        _tapDownPosition = null;
        return;
      }
    } else {
      _tapCount = 1;
    }
    _lastTapTime = now;

    Future.delayed(const Duration(milliseconds: _multiTapTimeout), () {
      if (mounted && _tapCount == 1 && _lastTapTime == now) {
        widget.onSingleTap?.call();
        _tapCount = 0;
        _lastTapTime = null;
      }
    });

    _tapDownPosition = null;
    _tapDownButtons = null;
  }
}
