import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ProgressiveScroll extends StatefulWidget {
  final Widget child;
  final ScrollOffsetController scrollController;
  final double maxSpeed;
  final double accelerationFactor;
  final double curve;
  final FocusNode? focusNode;
  final bool autofocus;
  // ScrollOffsetController לא חושף isAttached, ו-animateScroll זורק אם הרשימה
  // אינה מחוברת (נטענת/לא ב-tree). ItemScrollController (שמתחבר יחד עם
  // ScrollOffsetController לאותו ScrollablePositionedList) כן חושף isAttached.
  final ItemScrollController? itemScrollController;

  const ProgressiveScroll({
    super.key,
    required this.child,
    required this.scrollController,
    this.maxSpeed = 5000.0,
    this.accelerationFactor = 0.1,
    this.curve = 2.0,
    this.focusNode,
    this.autofocus = false,
    this.itemScrollController,
  });

  @override
  State<ProgressiveScroll> createState() => _ProgressiveScrollState();
}

class _ProgressiveScrollState extends State<ProgressiveScroll> {
  double _scrollSpeed = 0;
  bool _isKeyPressed = false;
  int _scrollDirection = 0; // 1 for down, -1 for up, 0 for no scroll
  double _timePressedInSeconds = 0;
  Timer? _scrollTickTimer;
  late final FocusNode _focusNode;
  bool _isLocalFocusNode = false;

  // גלילה אפשרית רק כשה-ScrollablePositionedList מחובר; אחרת animateScroll זורק.
  bool get _canScroll => widget.itemScrollController?.isAttached ?? false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _focusNode = FocusNode();
      _isLocalFocusNode = true;
    } else {
      _focusNode = widget.focusNode!;
    }
    // בקשת פוקוס מפורשת — Focus.autofocus לא יורה כשכבר יש primaryFocus
    // ב-scope (כמו ה-Focus של ה-Scaffold בכרטיסיית המפרשים).
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scrollTickTimer?.cancel();
    if (_isLocalFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  // הטיימר רץ רק בזמן לחיצת חץ. טיימר תמידי + KeyUp שהלך לאיבוד (מעבר
  // פוקוס באמצע לחיצה) גרמו בעבר לגלילה אוטונומית אינסופית שנלחמת במשתמש.
  void _startScrolling() {
    if (_scrollTickTimer?.isActive ?? false) return;
    _scrollTickTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_isKeyPressed) {
        _stopScrolling();
        return;
      }
      _timePressedInSeconds += 0.016; // 16 milliseconds in seconds
      double curvedT = exp(widget.curve * _timePressedInSeconds);
      _scrollSpeed = (curvedT * widget.accelerationFactor * _scrollDirection)
          .clamp(-widget.maxSpeed, widget.maxSpeed);

      if (_scrollSpeed != 0 && _canScroll) {
        widget.scrollController.animateScroll(
          offset: _scrollSpeed,
          duration: const Duration(milliseconds: 16),
        );
      }
    });
  }

  void _stopScrolling() {
    _scrollTickTimer?.cancel();
    _scrollTickTimer = null;
    _isKeyPressed = false;
    _scrollDirection = 0;
    _scrollSpeed = 0;
    _timePressedInSeconds = 0;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isArrowDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isArrowUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isArrowDown && !isArrowUp) return KeyEventResult.ignored;
    // קיצורי העריכה יושבים בשורש האפליקציה, ולכן החץ מגיע לכאן לפני שדה טקסט מקונן.
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null) {
      return KeyEventResult.ignored;
    }

    // Shift+חץ שמור לבחירת טקסט, ושאר הצירופים לקיצורים — לא מתערבים בהם.
    if (HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    if (event is KeyUpEvent) {
      if (_canScroll && _scrollDirection != 0) {
        widget.scrollController.animateScroll(
          offset: 100.0 * _scrollDirection,
          duration: const Duration(milliseconds: 150),
        );
      }
      _stopScrolling();
    } else {
      _isKeyPressed = true;
      _scrollDirection = isArrowDown ? 1 : -1;
      _startScrolling();
    }
    // בולעים את החץ כדי שלא יגלול גם Scrollable שמעל — כש"מפרשים מתחת"
    // מקונן בתוך גלילת גוף הטקסט הראשי, אחרת שניהם היו גוללים יחד.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      // איבוד פוקוס באמצע לחיצה בולע את ה-KeyUp — חובה לעצור כאן,
      // אחרת הגלילה ממשיכה לבד ללא דרך לעצור אותה.
      onFocusChange: (hasFocus) {
        if (!hasFocus) _stopScrolling();
      },
      child: widget.child,
    );
  }
}
