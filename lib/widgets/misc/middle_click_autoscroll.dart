import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/widgets/misc/scrollable_hit_test_registry.dart';

/// מזהה המצביע של אירועי הגלגלת הסינתטיים ש[MiddleClickAutoScroll] משגר.
///
/// [SmoothWheelScroll] מדלג עליהם: הם כבר מגיעים חלקים בכל פריים, והחלקה
/// נוספת רק מוסיפה פיגור וזחילה אחרי שהמשתמש שחרר את הכפתור.
const int kAutoScrollSyntheticDevice = -0xA5C;

/// גלילה אוטומטית בלחיצה על גלגל העכבר.
///
/// לחיצה על הגלגל מעגנת סמן במקום הלחיצה, ומכאן המרחק של הסמן מהעוגן קובע
/// את כיוון הגלילה ואת מהירותה. שחרור במקום נועל את המצב (הגלילה נמשכת עד
/// לחיצה נוספת או Esc), וגרירה ושחרור מסיימים אותה.
///
/// עוטף את כל האפליקציה פעם אחת ב-[MaterialApp.builder], ולכן פועל בכל
/// אזור גליל: רשימות, מסכי קריאה, ספרייה, הגדרות, דיאלוגים וצופה ה-PDF.
/// המימוש משגר אירועי גלגלת לנתיב שנתפס בלחיצה, כך שכל מי שמגיב לגלגלת
/// מגיב גם כאן — כולל מעבר לרשימה החיצונית כשהפנימית הגיעה לקצה.
///
/// כדי לשמור לחיצת גלגל לשימוש אחר באזור מסוים (למשל סגירת לשונית), יש
/// לעטוף אותו ב-[AutoScrollBarrier].
class MiddleClickAutoScroll extends StatefulWidget {
  const MiddleClickAutoScroll({super.key, required this.child});

  final Widget child;

  @override
  State<MiddleClickAutoScroll> createState() => _MiddleClickAutoScrollState();
}

class _MiddleClickAutoScrollState extends State<MiddleClickAutoScroll>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements GestureArenaMember {
  /// רדיוס האזור סביב העוגן שבו אין גלילה, כדי שרעד יד לא יזיז.
  static const double _deadZone = 16.0;

  /// מרחק שמעליו שחרור הכפתור מסיים את הגלילה במקום לנעול אותה.
  static const double _dragThreshold = 12.0;

  /// המהירות (פיקסלים לשנייה) היא חזקה של המרחק מהעוגן: עדינה בקרבת
  /// העוגן ומאיצה ככל שמתרחקים, כמו הגלילה האוטומטית במערכת ההפעלה.
  static const double _speedExponent = 1.3;
  static const double _speedFactor = 1.6;
  static const double _maxSpeed = 6000.0;

  static const double _anchorRadius = 17.0;

  late final Ticker _ticker;
  Duration? _lastTick;

  /// נקודת הלחיצה, בקואורדינטות גלובליות. null = הגלילה אינה פעילה.
  Offset? _anchor;
  Offset _pointer = Offset.zero;

  /// פינת השכבה בקואורדינטות גלובליות, לציור העוגן במקום הנכון.
  Offset _origin = Offset.zero;

  /// נתיב הפגיעה שנתפס בלחיצה. הגלילה נשארת נעולה עליו גם כשהתוכן מתחלף.
  HitTestResult? _hitTest;

  /// המאזין לגלגלת הרדוד ביותר בנתיב. משמש רק כמדד חיות: מאזין עמוק יותר
  /// עשוי להיות פריט ממוחזר שיוסר תוך כדי גלילה, בעוד שהרדוד חי כל עוד
  /// המסך על המסך.
  RenderObject? _liveness;
  int? _pointerId;
  int _viewId = 0;

  /// ציר הגלילה של האזור שנתפס, לציור החיצים ולנטרול הציר השני.
  Axis? _axis;

  final _scrollables = ScrollableHitTestRegistry();

  bool get _isActive => _anchor != null;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Ticker.dispose זורק על טיקר שעדיין רץ, וגלילה נעולה משאירה אותו רץ.
    _ticker.stop();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  // --------------------------------------------------------------- מחזור חיים

  void _onPointerDown(PointerDownEvent event) {
    // כל לחיצה במצב פעיל מסיימת, כמו במערכת ההפעלה.
    if (_isActive) {
      _stop();
      return;
    }
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons != kMiddleMouseButton) return;

    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, event.position, event.viewId);
    final target = _resolveTarget(result);
    if (target == null) return;

    // הגרירה שולטת בגלילה האוטומטית, ואסור שתזיז גם את התוכן שמתחתיה.
    final entry = GestureBinding.instance.gestureArena.add(event.pointer, this);

    final box = context.findRenderObject();
    _origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : Offset.zero;
    _hitTest = result;
    _liveness = target.liveness;
    _pointerId = event.pointer;
    _viewId = event.viewId;
    _pointer = event.position;
    _lastTick = null;
    HardwareKeyboard.instance.addHandler(_onKey);
    _ticker.start();
    setState(() {
      _anchor = event.position;
      _axis = target.axis;
    });
    entry.resolve(GestureDisposition.accepted);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isActive || event.pointer != _pointerId) return;
    _pointer = event.position;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointerId) _stop();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isActive || event.pointer != _pointerId) return;
    _pointerId = null;
    // שחרור אחרי גרירה מסיים; שחרור במקום נועל את הגלילה על הסמן.
    if ((_pointer - _anchor!).distance > _dragThreshold) _stop();
  }

  void _stop() {
    if (!_isActive) return;
    _ticker.stop();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hitTest = null;
    _liveness = null;
    _pointerId = null;
    setState(() {
      _anchor = null;
      _axis = null;
    });
  }

  bool _onKey(KeyEvent event) {
    if (!_isActive) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    // ESC מחלון אחר לא עוצר את הגלילה כאן ולא נבלע.
    if (!AppWindowKeys.isActiveWindow(context)) return false;
    _stop();
    return true;
  }

  // ------------------------------------------------------------ זיהוי היעד

  /// מוצא בנתיב את מה שיש לגלול: את הציר שלו ואת המאזין שישמש מדד חיות.
  /// null = אין מה לגלול כאן, או שיש בנתיב [AutoScrollBarrier].
  ///
  /// כל [Scrollable] וגם צופה ה-PDF מאזינים לאותות הגלגלת דרך [Listener],
  /// ולכן סימן אחד מכסה את שניהם. [Scrollable] שאין לו לאן לזוז מדולג לטובת
  /// זה שמעליו — בדיוק כפי שגלגלת אמיתית עוברת אליו.
  ({RenderObject liveness, Axis? axis})? _resolveTarget(HitTestResult result) {
    RenderObject? liveness;
    Axis? axis;
    var found = false;

    for (final entry in result.path) {
      final object = entry.target;
      if (object is _RenderAutoScrollBarrier) return null;
      // לחיצת גלגל על קישור בטקסט פותחת אותו בכרטיסייה חדשה, לא גוללת.
      if (inlineLinkUrlOf(object) != null) return null;
      if (object is! RenderPointerListener || object.onPointerSignal == null) {
        continue;
      }
      liveness = object;
      if (found) continue;

      final scrollable = _scrollables[object];
      if (scrollable == null) {
        // מאזין שאינו Scrollable (צופה PDF, WebView) — הציר אינו ידוע.
        found = true;
        continue;
      }
      if (!_canScroll(scrollable)) continue;
      axis = scrollable.position.axis;
      found = true;
    }

    return found ? (liveness: liveness!, axis: axis) : null;
  }

  bool _canScroll(ScrollableState scrollable) {
    if (!scrollable.mounted) return false;
    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) return false;
    if (!position.physics.shouldAcceptUserOffset(position)) return false;
    return position.maxScrollExtent > position.minScrollExtent;
  }

  // ---------------------------------------------------------------- הגלילה

  double _speed(double distance) {
    final magnitude = distance.abs() - _deadZone;
    if (magnitude <= 0) return 0.0;
    final speed = math.min(
      math.pow(magnitude, _speedExponent).toDouble() * _speedFactor,
      _maxSpeed,
    );
    return distance.isNegative ? -speed : speed;
  }

  void _onTick(Duration elapsed) {
    final anchor = _anchor;
    final hitTest = _hitTest;
    if (anchor == null || hitTest == null) return;

    // כשהאזור שנתפס יורד מהמסך אין למי לשגר, והמצב הפעיל רק לוכד את העכבר.
    if (!(_liveness?.attached ?? false)) {
      _stop();
      return;
    }

    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) return;
    final seconds = (elapsed - previous).inMicroseconds / 1000000.0;
    // פריים חריג (חלון ממוזער, נעילת מסך) היה מקפיץ מרחק עצום בבת אחת.
    if (seconds <= 0 || seconds > 0.1) return;

    final distance = _pointer - anchor;
    final horizontal = _speed(distance.dx) * seconds;
    final vertical = _speed(distance.dy) * seconds;
    // Shift מהפך את הציר ש-Scrollable קורא מהאירוע, ולכן כשהציר ידוע אותה
    // מהירות נשלחת בשני הצירים — אחרת הגלילה קופאת כל עוד Shift לחוץ.
    final delta = switch (_axis) {
      Axis.vertical => Offset(vertical, vertical),
      Axis.horizontal => Offset(horizontal, horizontal),
      null => Offset(horizontal, vertical),
    };
    if (delta == Offset.zero) return;

    GestureBinding.instance.dispatchEvent(
      PointerScrollEvent(
        viewId: _viewId,
        timeStamp: elapsed,
        device: kAutoScrollSyntheticDevice,
        position: anchor,
        scrollDelta: delta,
      ),
      hitTest,
    );
  }

  // ----------------------------------------------------------------- תצוגה

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) =>
          _scrollables.capture(notification.context),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) =>
            _scrollables.capture(notification.context),
        child: _buildInteraction(context),
      ),
    );
  }

  Widget _buildInteraction(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (event) {
        if (event.pointer == _pointerId) _stop();
      },
      // passthrough מעביר לילד את האילוצים המקוריים, כך שהעטיפה אינה משנה
      // את הפריסה של האפליקציה שמתחתיה.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_anchor != null)
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.allScroll,
                opaque: true,
                onHover: (event) => _pointer = event.position,
                onExit: (_) => _stop(),
                child: CustomPaint(
                  painter: _AutoScrollAnchorPainter(
                    center: _anchor! - _origin,
                    axis: _axis,
                    colors: Theme.of(context).colorScheme,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// מסמן אזור שבו לחיצת גלגל שמורה לפעולה אחרת, ולכן [MiddleClickAutoScroll]
/// לא יופעל בו (למשל לשונית שנסגרת בלחיצת גלגל).
class AutoScrollBarrier extends SingleChildRenderObjectWidget {
  const AutoScrollBarrier({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAutoScrollBarrier();
}

class _RenderAutoScrollBarrier extends RenderProxyBoxWithHitTestBehavior {
  _RenderAutoScrollBarrier() : super(behavior: HitTestBehavior.translucent);
}

/// מצייר את עוגן הגלילה: עיגול ובתוכו חיצים משולשים לכיווני הגלילה.
class _AutoScrollAnchorPainter extends CustomPainter {
  const _AutoScrollAnchorPainter({
    required this.center,
    required this.axis,
    required this.colors,
  });

  final Offset center;
  final Axis? axis;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Path()
      ..addOval(
        Rect.fromCircle(
          center: center,
          radius: _MiddleClickAutoScrollState._anchorRadius,
        ),
      );
    canvas.drawShadow(circle, colors.shadow, 3.0, false);
    canvas.drawPath(circle, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawPath(
      circle,
      Paint()
        ..color = colors.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final ink = Paint()..color = colors.onSurfaceVariant;
    canvas.drawCircle(center, 2.0, ink);

    if (axis != Axis.horizontal) {
      _arrow(canvas, ink, const Offset(0, -1));
      _arrow(canvas, ink, const Offset(0, 1));
    }
    if (axis != Axis.vertical) {
      _arrow(canvas, ink, const Offset(-1, 0));
      _arrow(canvas, ink, const Offset(1, 0));
    }
  }

  /// מצייר משולש שקודקודו פונה ל-[direction] (וקטור יחידה על אחד הצירים).
  void _arrow(Canvas canvas, Paint paint, Offset direction) {
    const base = 7.0;
    const inner = 6.0;
    const height = 5.0;
    final normal = Offset(direction.dy, direction.dx);
    final tip = center + direction * (inner + height);
    final edge = center + direction * inner;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(edge.dx + normal.dx * base / 2, edge.dy + normal.dy * base / 2)
        ..lineTo(edge.dx - normal.dx * base / 2, edge.dy - normal.dy * base / 2)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_AutoScrollAnchorPainter oldDelegate) =>
      center != oldDelegate.center ||
      axis != oldDelegate.axis ||
      colors != oldDelegate.colors;
}
