import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// מחליק את גלילת גלגלת העכבר ברשימה שמתחתיו.
///
/// מחבר נקישות ליעד מצטבר ומניע אליו [ScrollActivity] אחת, כך שהמרחק
/// נשמר אך נפרס על פריימים בלי מחזור התחלה וסיום חדש בכל צעד.
class SmoothWheelScroll extends StatefulWidget {
  const SmoothWheelScroll({super.key, required this.child});

  final Widget child;

  @override
  State<SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

class _SmoothWheelScrollState extends State<SmoothWheelScroll>
    with SingleTickerProviderStateMixin {
  /// קבוע הזמן של ההתקרבות ליעד: ~55ms מביאים ל-90% מהדרך בכ-8 פריימים.
  /// ארוך מזה מרגיש צף ומאחר אחרי היד, קצר מזה חוזר לתחושת הקפיצה.
  static const double _timeConstantMs = 55.0;

  /// מתחת לזה אין מה להחליק — נוחתים על היעד ועוצרים.
  static const double _epsilon = 0.5;

  late final Ticker _ticker;
  Duration? _lastTick;

  ScrollableState? _scrollable;
  _SmoothWheelActivity? _activity;
  final Set<ScrollableState> _nestedScrollables = {};

  double _target = 0.0;

  /// שינוי minScrollExtent ברשימה ממוקמת מעיד שהעוגן הוחלף,
  /// ולכן היעד השמור כבר שייך למערכת צירים קודמת.
  double _anchorMinExtent = 0.0;

  @override
  void initState() {
    super.initState();
    // יצירה מראש מונעת ניסיון ליצור Ticker מתוך dispose של State שהוסר.
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _finish();
    _ticker.dispose();
    super.dispose();
  }

  ScrollPosition? get _position {
    final scrollable = _scrollable;
    if (scrollable == null || !scrollable.mounted) return null;
    final position = scrollable.position;
    return position.hasPixels && position.hasContentDimensions
        ? position
        : null;
  }

  /// לוכד את ה-[Scrollable] של הרשימה מתוך ההודעות שהיא שולחת. depth אחר
  /// מאפס הוא גלילה מקוננת בתוך פריט, שאמורה להישאר של עצמה.
  bool _capture(BuildContext? notificationContext, int depth) {
    if (depth != 0) {
      final nested = notificationContext == null
          ? null
          : Scrollable.maybeOf(notificationContext);
      if (nested != null) _nestedScrollables.add(nested);
      return false;
    }
    if (notificationContext != null) {
      final next = Scrollable.maybeOf(notificationContext);
      if (next != null && !identical(next, _scrollable)) {
        _finish();
        _scrollable = next;
      }
    }
    return false;
  }

  bool _shouldClaim(PointerScrollEvent event) {
    // משטח מגע מגיע כאירועי pan ומקבל אינרציה מהפיזיקה; רק לגלגלת אין.
    if (event.kind != PointerDeviceKind.mouse) return false;
    if (_isOverNestedScrollable(event.position)) {
      _finish();
      return false;
    }

    final delta = event.scrollDelta.dy;
    if (delta == 0) return false;

    // Shift מהפך ציר, ושאר הצירופים שמורים לקיצורים — אלה לא גלילה רגילה.
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }

    final position = _position;
    if (position == null) return false;

    // בקצה אין מה להחליק, ובלי תפיסה המסלול המקורי גם מעביר לאב אם יש.
    return delta > 0
        ? position.pixels < position.maxScrollExtent - _epsilon
        : position.pixels > position.minScrollExtent + _epsilon;
  }

  bool _isOverNestedScrollable(Offset globalPosition) {
    _nestedScrollables.removeWhere((scrollable) => !scrollable.mounted);
    for (final scrollable in _nestedScrollables) {
      final renderObject = scrollable.context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final bounds = MatrixUtils.transformRect(
        renderObject.getTransformTo(null),
        Offset.zero & renderObject.size,
      );
      if (bounds.contains(globalPosition)) return true;
    }
    return false;
  }

  void _onWheel(PointerScrollEvent event) {
    final position = _position;
    if (position == null) return;

    final wasActive = _activity != null;
    if (!wasActive) {
      _target = position.pixels;
      _anchorMinExtent = position.minScrollExtent;
      if (!_beginActivity(position)) {
        position.pointerScroll(event.scrollDelta.dy);
        event.respond(allowPlatformDefault: false);
        return;
      }
    }
    _target = (_target + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    event.respond(allowPlatformDefault: false);

    // אירועים נוספים רק מעדכנים יעד; התנועה עצמה מתבצעת פעם אחת בכל פריים.
    if (wasActive) return;

    if (!_advance(position, 16.0)) {
      _finish();
      return;
    }
    _lastTick = null;
    _ticker.start();
  }

  bool _beginActivity(ScrollPosition position) {
    if (position is! ScrollActivityDelegate) return false;
    final delegate = position as ScrollActivityDelegate;

    late final _SmoothWheelActivity activity;
    activity = _SmoothWheelActivity(
      delegate,
      onDisposed: () => _onActivityDisposed(activity),
    );
    _activity = activity;
    position.beginActivity(activity);
    return identical(_activity, activity);
  }

  /// מקדם צעד אחד לעבר היעד. מחזיר false כשהמרחק נגמר.
  bool _advance(ScrollPosition position, double frameMs) {
    final activity = _activity;
    if (activity == null) return false;

    _target = _target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final remaining = _target - position.pixels;
    if (remaining.abs() <= _epsilon) {
      activity.moveTo(_target, velocity: 0.0);
      return false;
    }

    var step = remaining * (1 - math.exp(-frameMs / _timeConstantMs));
    // ליד היעד המנה שואפת לאפס ומייצרת זחילה — מסיימים בצעד אחד.
    if (step.abs() < _epsilon) step = remaining;

    final before = position.pixels;
    final overscroll = activity.moveTo(
      before + step,
      velocity: step * 1000 / frameMs,
    );
    final moved = (position.pixels - before).abs() > _epsilon;
    if (!moved && overscroll.abs() > _epsilon) return false;
    final remainingAfterStep = _target - position.pixels;
    if (remainingAfterStep.abs() <= _epsilon) {
      activity.moveTo(_target, velocity: 0.0);
      return false;
    }
    return true;
  }

  void _onTick(Duration elapsed) {
    final position = _position;
    if (position == null ||
        _activity == null ||
        (position.minScrollExtent - _anchorMinExtent).abs() > _epsilon) {
      _finish();
      return;
    }

    final previousTick = _lastTick;
    _lastTick = elapsed;
    final measuredMs = previousTick == null
        ? 16.0
        : (elapsed - previousTick).inMicroseconds / 1000.0;
    // פריים ראשון או קפיצת זמן (חלון ממוזער/נעילה) — צעד של פריים תקני.
    final frameMs = measuredMs <= 0 || measuredMs > 100 ? 16.0 : measuredMs;

    if (!_advance(position, frameMs)) {
      _finish();
    }
  }

  void _onActivityDisposed(_SmoothWheelActivity activity) {
    if (!identical(_activity, activity)) return;
    _activity = null;
    _ticker.stop();
  }

  void _finish() {
    _ticker.stop();
    final activity = _activity;
    if (activity == null) return;
    _activity = null;
    activity.finish();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) =>
          _capture(notification.context, notification.depth),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) =>
            _capture(notification.context, notification.depth),
        child: _WheelSignalInterceptor(
          shouldClaim: _shouldClaim,
          onWheel: _onWheel,
          child: widget.child,
        ),
      ),
    );
  }
}

class _SmoothWheelActivity extends ScrollActivity {
  _SmoothWheelActivity(super.delegate, {required this.onDisposed});

  final VoidCallback onDisposed;
  ScrollDirection _direction = ScrollDirection.idle;
  double _velocity = 0.0;

  double moveTo(double pixels, {required double velocity}) {
    _velocity = velocity;
    return delegate.setPixels(pixels);
  }

  void finish() => delegate.goBallistic(0.0);

  @override
  void dispatchScrollUpdateNotification(
    ScrollMetrics metrics,
    BuildContext context,
    double scrollDelta,
  ) {
    super.dispatchScrollUpdateNotification(metrics, context, scrollDelta);
    final direction = scrollDelta > 0
        ? ScrollDirection.reverse
        : ScrollDirection.forward;
    if (direction == _direction) return;
    _direction = direction;
    UserScrollNotification(
      metrics: metrics,
      context: context,
      direction: direction,
    ).dispatch(context);
  }

  @override
  void dispatchScrollEndNotification(
    ScrollMetrics metrics,
    BuildContext context,
  ) {
    super.dispatchScrollEndNotification(metrics, context);
    if (_direction == ScrollDirection.idle) return;
    _direction = ScrollDirection.idle;
    UserScrollNotification(
      metrics: metrics,
      context: context,
      direction: ScrollDirection.idle,
    ).dispatch(context);
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    super.dispose();
    onDisposed();
  }
}

/// תופס אירועי גלגלת לפני ה-[Scrollable] שמתחתיו, דרך רישום ב-
/// [PointerSignalResolver].
class _WheelSignalInterceptor extends SingleChildRenderObjectWidget {
  const _WheelSignalInterceptor({
    required this.shouldClaim,
    required this.onWheel,
    super.child,
  });

  final bool Function(PointerScrollEvent event) shouldClaim;
  final void Function(PointerScrollEvent event) onWheel;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWheelSignalInterceptor(shouldClaim: shouldClaim, onWheel: onWheel);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWheelSignalInterceptor renderObject,
  ) {
    renderObject
      ..shouldClaim = shouldClaim
      ..onWheel = onWheel;
  }
}

class _RenderWheelSignalInterceptor extends RenderProxyBox {
  _RenderWheelSignalInterceptor({
    required this.shouldClaim,
    required this.onWheel,
  });

  bool Function(PointerScrollEvent event) shouldClaim;
  void Function(PointerScrollEvent event) onWheel;

  /// רישום לפני הצאצאים מאפשר להחליף את קפיצת ה-[Scrollable] בהחלקה.
  /// כשיש Scrollable מקונן, העטיפה אינה נרשמת כלל.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return hitTestChildren(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    // ההכרעה חייבת לקרות לפני הרישום: רישום שלא מלווה בטיפול היה בולע את
    // הגלילה המקורית ומשאיר את הגלגלת מתה.
    if (event is PointerScrollEvent && shouldClaim(event)) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (claimed) => onWheel(claimed as PointerScrollEvent),
      );
    }
  }
}
