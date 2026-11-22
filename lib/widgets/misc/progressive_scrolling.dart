import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_tokens.dart';

import 'navigation_key_tracker.dart';

/// PageDown/PageUp: מסך אחד, 80% מהחלון כמו `ScrollAction` של Flutter.
void animatePageScroll(ScrollPosition position, {required bool forward}) {
  final delta = position.viewportDimension * 0.8 * (forward ? 1 : -1);
  unawaited(
    AppMotion.scrollPosition(
      position,
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      AppTokens.animPanelOpacity,
      curve: Curves.easeOut,
    ),
  );
}

class ProgressiveScroll extends StatefulWidget {
  final Widget child;
  final ItemScrollController scrollController;

  /// המהירות המרבית בפיקסלים לשנייה.
  final double maxSpeed;

  /// המהירות ההתחלתית בפיקסלים לשנייה, לפני ההאצה המעריכית.
  final double accelerationFactor;
  final double curve;
  final FocusNode? focusNode;
  final bool autofocus;

  /// מודיע פעם אחת בתחילת החזקת חץ או PageDown/PageUp, לפני שהמיקום משתנה.
  final VoidCallback? onNavigationStart;
  // קיצורי התוכן מקבלים קדימות על פני גלילת החיצים.
  final FocusOnKeyEventCallback? onKeyEvent;

  const ProgressiveScroll({
    super.key,
    required this.child,
    required this.scrollController,
    // ברירות המחדל הן כוונון הקוראים (issue #5638): 600 פיקסלים לשנייה
    // בהתחלה, האצה עדינה, ותקרה של כ-3 מסכים לשנייה אחרי כשנייה וחצי.
    this.maxSpeed = 2500.0,
    this.accelerationFactor = 600.0,
    this.curve = 1.0,
    this.focusNode,
    this.autofocus = false,
    this.onNavigationStart,
    this.onKeyEvent,
  }) : assert(maxSpeed >= 0 && maxSpeed < double.infinity),
       assert(accelerationFactor >= 0 && accelerationFactor < double.infinity),
       assert(curve > -double.infinity && curve < double.infinity);

  @override
  State<ProgressiveScroll> createState() => _ProgressiveScrollState();
}

class _ProgressiveScrollState extends State<ProgressiveScroll>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final NavigationKeyTracker _navigationKeys;
  int _scrollDirection = 0;
  double _timePressedInSeconds = 0;
  late final Ticker _ticker;
  Duration? _lastFrameTime;
  FocusNode? _ownFocusNode;
  ({ScrollPosition position, double offset, Future<void> done})? _pendingStep;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  ScrollPosition? get _position {
    final controller = widget.scrollController.scrollController;
    if (controller == null || controller.positions.length != 1) return null;
    final position = controller.position;
    return position.hasContentDimensions && position.hasPixels
        ? position
        : null;
  }

  bool get _isEditingText =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;

  @override
  void initState() {
    super.initState();
    _navigationKeys = NavigationKeyTracker(
      hasNavigationFocus: () => _focusNode.hasFocus && !_isEditingText,
    );
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
    _requestFocus();
  }

  void _requestFocus() {
    if (!widget.autofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(ProgressiveScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode ||
        oldWidget.scrollController != widget.scrollController ||
        widget.maxSpeed == 0 ||
        widget.accelerationFactor == 0) {
      _stopScrolling();
      _navigationKeys.clear();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (widget.focusNode != null) {
        _ownFocusNode?.dispose();
        _ownFocusNode = null;
      }
      _requestFocus();
    } else if (!oldWidget.autofocus && widget.autofocus) {
      _requestFocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _stopScrolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopScrolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopScrolling();
    _ticker.dispose();
    _navigationKeys.clear();
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _startScrolling(int direction) {
    if (widget.maxSpeed == 0 ||
        widget.accelerationFactor == 0 ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    if (_scrollDirection == 0) {
      widget.onNavigationStart?.call();
      widget.scrollController.listController?.cancelPositioning();
      final position = _position;
      if (position != null) {
        position.jumpTo(
          position.pixels.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    }
    if (_scrollDirection != direction) {
      // הלחיצה מזיזה צעד מיד, והגלילה הרציפה מתחילה רק כשהצעד מסתיים —
      // כך הקשה קצרה היא צעד אחד בדיוק.
      _timePressedInSeconds =
          -AppTokens.animFast.inMicroseconds / Duration.microsecondsPerSecond;
      // הזמן נספר מהפריים הראשון, כמו אנימציית הצעד.
      _lastFrameTime = null;
      _step(direction);
    }
    _scrollDirection = direction;
    final position = _position;
    if (position == null ||
        (direction > 0 && position.pixels >= position.maxScrollExtent) ||
        (direction < 0 && position.pixels <= position.minScrollExtent)) {
      _ticker.stop();
      return;
    }
    if (!_ticker.isActive) {
      _lastFrameTime = null;
      _ticker.start();
    }
  }

  void _onTick(Duration _) {
    if (_isEditingText) {
      _stopScrolling();
      return;
    }
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final previous = _lastFrameTime;
    _lastFrameTime = now;
    final position = _position;
    if (position == null) {
      _ticker.stop();
      return;
    }
    if (previous == null || _scrollDirection == 0) return;
    final seconds = ((now - previous).inMicroseconds / 1000000).clamp(0.0, 0.1);
    if (seconds == 0) return;
    final start = math.max(_timePressedInSeconds, 0.0);
    _timePressedInSeconds += seconds;
    final active = math.min(seconds, _timePressedInSeconds);
    if (active <= 0) return;
    final distance = _distanceForInterval(start, active);
    if (distance > 0) {
      final target = (position.pixels + distance * _scrollDirection).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) position.jumpTo(target);
      if (target == position.minScrollExtent ||
          target == position.maxScrollExtent) {
        _ticker.stop();
      }
    }
  }

  void _step(int direction) {
    final position = _position;
    final pending = _pendingStep;
    if (pending != null && !identical(pending.position, position)) {
      _pendingStep = null;
    }
    if (position == null) return;
    // הקשה נוספת באותה רשימה ממשיכה מיעד הצעד שבדרך.
    final pendingOffset = _pendingStep?.offset;
    final target = ((pendingOffset ?? position.pixels) + 100 * direction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) {
      if (pendingOffset != null) {
        // גם צעד ללא תזוזה צריך לבטל את האנימציה בכיוון הקודם.
        _pendingStep = null;
        position.jumpTo(target);
      }
      return;
    }
    final animation = AppMotion.scrollPosition(
      position,
      target,
      AppTokens.animFast,
      curve: Curves.linear,
    );
    _pendingStep = (position: position, offset: target, done: animation);
    unawaited(
      animation.whenComplete(() {
        if (identical(_pendingStep?.done, animation)) _pendingStep = null;
      }),
    );
  }

  double _distanceForInterval(double pressed, double seconds) {
    // אינטגרציה של המהירות שומרת מרחק זהה גם בקצבי פריימים שונים.
    final initial = widget.accelerationFactor;
    final maximum = widget.maxSpeed;
    if (initial == 0 || maximum == 0) return 0;
    final curve = widget.curve;
    if (curve == 0) return math.min(initial, maximum) * seconds;
    final start = initial * math.exp(curve * pressed);
    final end = initial * math.exp(curve * (pressed + seconds));
    if (start >= maximum && end >= maximum) return maximum * seconds;
    if (start <= maximum && end <= maximum) return (end - start) / curve;
    final cappedAt = math.log(maximum / initial) / curve;
    if (curve > 0) {
      return (maximum - start) / curve +
          maximum * (pressed + seconds - cappedAt);
    }
    return maximum * (cappedAt - pressed) + (end - maximum) / curve;
  }

  void _stopScrolling() {
    _pendingStep = null;
    _stopHold();
  }

  void _stopHold() {
    _ticker.stop();
    _scrollDirection = 0;
    _timePressedInSeconds = 0;
    _lastFrameTime = null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    _navigationKeys.release(event);
    final result =
        widget.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    if (result != KeyEventResult.ignored) {
      if (event is KeyUpEvent) _stopScrolling();
      return result;
    }

    final modified =
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (modified) _stopScrolling();

    final isPageDown = event.logicalKey == LogicalKeyboardKey.pageDown;
    if (isPageDown || event.logicalKey == LogicalKeyboardKey.pageUp) {
      return _handlePageKey(event, forward: isPageDown, modified: modified);
    }

    final isArrowDown = event.logicalKey == LogicalKeyboardKey.arrowDown;
    final isArrowUp = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!isArrowDown && !isArrowUp) return KeyEventResult.ignored;
    // קיצורי העריכה יושבים בשורש האפליקציה, ולכן החץ מגיע לכאן לפני שדה טקסט מקונן.
    if (_isEditingText) {
      _stopScrolling();
      return KeyEventResult.ignored;
    }

    // Shift+חץ שמור לבחירת טקסט, ושאר הצירופים לקיצורים — לא מתערבים בהם.
    if (modified) {
      return KeyEventResult.ignored;
    }

    final direction = isArrowDown ? 1 : -1;
    if (event is KeyUpEvent) {
      if (_scrollDirection == direction) {
        final other = isArrowDown
            ? LogicalKeyboardKey.arrowUp
            : LogicalKeyboardKey.arrowDown;
        if (HardwareKeyboard.instance.logicalKeysPressed.contains(other)) {
          _startScrolling(-direction);
        } else {
          _stopHold();
        }
      }
    } else {
      _startScrolling(direction);
    }
    // בולעים את החץ כדי שלא יגלול גם Scrollable שמעל — כש"מפרשים מתחת"
    // מקונן בתוך גלילת גוף הטקסט הראשי, אחרת שניהם היו גוללים יחד.
    return KeyEventResult.handled;
  }

  /// ה-`ScrollAction` של Flutter מחפש Scrollable מעל הפוקוס, והפוקוס כאן
  /// יושב מעל הרשימה — לכן PageDown/PageUp מטופלים כאן.
  KeyEventResult _handlePageKey(
    KeyEvent event, {
    required bool forward,
    required bool modified,
  }) {
    // צירופים (Alt+PageDown לכותרת הבאה) הם קיצורים, ובשדה טקסט המקש לסמן.
    if (modified || _isEditingText) return KeyEventResult.ignored;
    if (event is! KeyUpEvent) {
      final position = _position;
      if (position == null) return KeyEventResult.ignored;
      _stopScrolling();
      if (!_navigationKeys.isRepeat(event)) widget.onNavigationStart?.call();
      widget.scrollController.listController?.cancelPositioning();
      animatePageScroll(position, forward: forward);
    }
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
