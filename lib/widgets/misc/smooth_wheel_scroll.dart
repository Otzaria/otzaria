import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// מחליק את גלילת גלגלת העכבר ברשימה שמתחתיו.
///
/// Flutter מיישם נקישת גלגלת כטלפורט: `forcePixels(pixels + delta)` ואז
/// מהירות אפס — כל התזוזה (100 פיקסלים בהגדרות Windows ברירת המחדל) קורית
/// בפריים אחד ואין האטה בסוף. כאן חוטפים את האירוע ומזינים את אותו מנוע
/// עצמו ([ScrollPosition.pointerScroll]) בצעדים קטנים לעבר יעד מצטבר, כך
/// שהמרחק זהה בדיוק אך פרוס על פריימים.
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

  double _target = 0.0;
  int _direction = 1;
  double? _previousPixels;

  /// ה-minScrollExtent שהיה בתחילת ההחלקה. רשימות ממוקמות מעגנות את מערכת
  /// הצירים לפריט היעד, ולכן שינוי שלו אומר שהעוגן הוחלף (קפיצת ניווט)
  /// והיעד השמור מצביע למקום אחר לגמרי.
  double _anchorMinExtent = 0.0;

  @override
  void initState() {
    super.initState();
    // חובה ליצור כאן ולא ב-late lazy: אם הגלגלת לא נתפסה אף פעם, dispose היה
    // יוצר את ה-Ticker על אלמנט שכבר הוסר מהעץ ומפיל assert.
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
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
    if (depth == 0 && notificationContext != null) {
      _scrollable = Scrollable.maybeOf(notificationContext) ?? _scrollable;
    }
    return false;
  }

  bool _shouldClaim(PointerScrollEvent event) {
    // משטח מגע מגיע כאירועי pan ומקבל אינרציה מהפיזיקה; רק לגלגלת אין.
    if (event.kind != PointerDeviceKind.mouse) return false;

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

  void _onWheel(PointerScrollEvent event) {
    final position = _position;
    if (position == null) return;

    // היעד מצטבר. מדידה מהמקום הנוכחי בכל נקישה הייתה מוותרת על המרחק
    // שההחלקה הקודמת עוד לא הספיקה לספק — נמדד: אובדן של 75% מהגלילה.
    if (!_ticker.isActive) {
      _target = position.pixels;
      _anchorMinExtent = position.minScrollExtent;
    }
    _target = (_target + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _direction = event.scrollDelta.dy > 0 ? 1 : -1;
    _previousPixels = null;

    // הצעד הראשון מבוצע מיד ולא בפריים הבא: השהיית קלט מורגשת יותר מהקפיצה.
    _advance(position, 16.0);
    if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  /// מקדם צעד אחד לעבר היעד. מחזיר false כשהמרחק נגמר.
  bool _advance(ScrollPosition position, double frameMs) {
    final remaining = _target - position.pixels;
    if (remaining.abs() <= _epsilon) return false;

    var step = remaining * (1 - math.exp(-frameMs / _timeConstantMs));
    // ליד היעד המנה שואפת לאפס ומייצרת זחילה — מסיימים בצעד אחד.
    if (step.abs() < _epsilon) step = remaining;

    // אותו מנוע שבו Flutter מטפל בנקישת גלגלת: מזיז מיד, נחסם בקצוות ומודיע
    // כמו גלילת משתמש. ההבדל היחיד הוא שכאן מזינים אותו בצעדים קטנים.
    position.pointerScroll(step);
    return true;
  }

  void _onTick(Duration elapsed) {
    final position = _position;
    if (position == null ||
        (position.minScrollExtent - _anchorMinExtent).abs() > _epsilon) {
      _stop();
      return;
    }

    final previousPixels = _previousPixels;
    _previousPixels = position.pixels;
    // תזוזה נגד כיוון הגלילה = גורם אחר לקח את ההגה (גרירת אגודל, ניווט).
    if (previousPixels != null &&
        (position.pixels - previousPixels) * _direction < -_epsilon) {
      _stop();
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
      _stop();
    }
  }

  void _stop() {
    _ticker.stop();
    _previousPixels = null;
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

  /// נרשמים בנתיב ה-hit-test **לפני** הצאצאים. ב-[PointerSignalResolver]
  /// הרושם הראשון זוכה, והסדר הוא סדר הנתיב — אחרת ה-[Scrollable] שבפנים,
  /// שעמוק יותר, היה נרשם ראשון וקופץ במקומנו.
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
