import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// פס הגלילה האנכי של אוצריא.
///
/// יושב בקצה הימני הפיזי, בכל כיוון טקסט: ב-RTL ברירת המחדל של Flutter היא
/// קצה ה-end, כלומר שמאל. כשיש מה לגלול, הוא שומר לעצמו רצועה ([gutterOf])
/// בצד שלו, והתוכן מצטמצם לידה, כך שהאגודל לא מכסה טקסט, כרטיסים או
/// פקדים. כשאין מה לגלול אין פס ואין רצועה.
///
/// [EdgeScrollbarBehavior] בונה אותו לכל רשימה באפליקציה. אתר שבונה פס
/// מפורש (אגודל קבוע, בקר משלו) משתמש ב-[AppScrollbar] ולא ב-`Scrollbar`
/// גולמי (UIL-031).
class AppScrollbar extends StatelessWidget {
  const AppScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.side = ScrollbarOrientation.right,
    this.thumbVisibility,
    this.interactive,
    this.contentInset = 0,
  }) : assert(
         side == ScrollbarOrientation.right ||
             side == ScrollbarOrientation.left,
         'AppScrollbar הוא פס אנכי',
       );

  /// אזור הגלילה. הפס האוטומטי של ההתנהגות כבוי בתוכו, כדי שלא יצויר פס כפול.
  final Widget child;

  final ScrollController? controller;

  /// הצד הפיזי. שמאל רק בחריג מתועד: חלונית צד שמשמאל לתוכן, שהידית שלה
  /// בקצה הפנימי (`AdaptiveSidePane`, `ContextOverlayPanel`).
  final ScrollbarOrientation side;

  final bool? thumbVisibility;

  final bool? interactive;

  /// המרווח שכבר יש לתוכן בצד הפס, בתוך אזור הגלילה. הרצועה מצטמצמת בו,
  /// כדי שתוכן עם ריווח משלו לא יקבל ריווח כפול.
  final double contentInset;

  /// רוחב הרצועה של הפס: המרחק מהקצה, עובי האגודל ומרווח עד התוכן, לפי
  /// ערכת הנושא של הפס במקום.
  static double gutterOf(BuildContext context) {
    final theme = ScrollbarTheme.of(context);
    final thickness =
        theme.thickness?.resolve(const <WidgetState>{}) ??
        AppTokens.scrollbarThickness;
    final margin = theme.crossAxisMargin ?? AppTokens.scrollbarMargin;
    return margin + thickness + AppTokens.scrollbarContentGap;
  }

  @override
  Widget build(BuildContext context) {
    return ScrollbarGutter(
      controller: controller,
      side: side,
      thumbVisibility: thumbVisibility,
      interactive: interactive,
      contentInset: contentInset,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
    );
  }
}

/// הפס עצמו ([Scrollbar] בצד [side]) עם הרצועה שנפתחת רק כשיש מה לגלול.
///
/// הרצועה היא ריווח בין הפס לאזור הגלילה: הפס מצויר על כל הרוחב, ולכן
/// האגודל נופל בתוך הרצועה, והוויופורט מצטמצם לידה. העץ זהה בשני המצבים,
/// כדי שפתיחת הרצועה לא תבנה מחדש את הרשימה.
///
/// ההחלטה על הרצועה נעשית בתוך שלב הפריסה ([_RenderScrollbarGutter]): הרשימה
/// נפרסת, ומיד נבדק אם יש בה מה לגלול. כך תוכן שגובהו נגזר מרוחבו (רשת עם
/// מספר עמודות ויחס קבועים) לא נכנס ללולאה שבה הרצועה מכווצת אותו עד שאין מה
/// לגלול, ואז נסגרת והוא גולש שוב. כשהתוכן גולש ברוחב מלא ונכנס רק בזכות
/// הרצועה, הרצועה נשארת.
///
/// משמש את [AppScrollbar] ואת [EdgeScrollbarBehavior]; קוד פיצ'ר משתמש
/// ב-[AppScrollbar].
class ScrollbarGutter extends StatefulWidget {
  const ScrollbarGutter({
    super.key,
    required this.child,
    required this.side,
    this.controller,
    this.thumbVisibility,
    this.interactive,
    this.contentInset = 0,
    this.reserveGutter = true,
  });

  final Widget child;
  final ScrollbarOrientation side;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final bool? interactive;
  final double contentInset;

  /// false: הפס בלבד, בלי רצועה — לאתר ששומר בעצמו רצועה קבועה.
  final bool reserveGutter;

  @override
  State<ScrollbarGutter> createState() => _ScrollbarGutterState();
}

class _ScrollbarGutterState extends State<ScrollbarGutter> {
  /// ההקשר של אזור הגלילה הישיר (depth 0), מההתראה האחרונה שלו. משמש כשאין
  /// בקר עם מיקום יחיד.
  BuildContext? _scrollableContext;

  /// אות לקופסת הרצועה שהרשימה נפרסה מחדש בלעדיה, למשל כשנוספו פריטים.
  final _metricsChanged = _Signal();

  /// קופסת הרצועה, לבדיקה אם נקודה נופלת ברצועה הפתוחה.
  final _boxKey = GlobalKey();

  // גרירת מגע ומשטח מגע שמתחילות ברצועה. הרצועה מחוץ ל-Scrollable, ולכן
  // המחוות שלו לא מגיעות אליה; כאן הן מועברות לאותו מיקום, כמו שה-Scrollable
  // עצמו עושה.
  VerticalDragGestureRecognizer? _recognizer;
  ScrollPosition? _dragPosition;
  ScrollHoldController? _hold;
  Drag? _drag;

  @override
  void dispose() {
    _hold?.cancel();
    _drag?.cancel();
    _recognizer?.dispose();
    _metricsChanged.dispose();
    super.dispose();
  }

  /// המיקום של אזור הגלילה שהרצועה שומרת לו, או null לפני שהוא ידוע.
  ScrollPosition? _position() {
    final controller = widget.controller;
    if (controller != null && controller.positions.length == 1) {
      return controller.position;
    }
    final context = _scrollableContext;
    if (context == null || !context.mounted) return null;
    return context.findAncestorStateOfType<ScrollableState>()?.position;
  }

  bool _inGutter(Offset globalPosition) {
    final box = _boxKey.currentContext?.findRenderObject();
    return box is _RenderScrollbarGutter && box.isInGutter(globalPosition);
  }

  /// המיקום, אם המשתמש יכול לגלול אותו עכשיו.
  ScrollPosition? _scrollablePosition() {
    final position = _position();
    if (position == null || !position.hasContentDimensions) return null;
    if (!position.physics.shouldAcceptUserOffset(position)) return null;
    return position;
  }

  VerticalDragGestureRecognizer? _dragRecognizer() {
    if (_hold == null && _drag == null) _dragPosition = _scrollablePosition();
    final position = _dragPosition;
    if (position == null) return null;
    final behavior = ScrollConfiguration.of(context);
    final physics = position.physics;
    return (_recognizer ??= VerticalDragGestureRecognizer(debugOwner: this))
      ..supportedDevices = behavior.dragDevices
      ..onDown = _handleDragDown
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel
      ..minFlingDistance = physics.minFlingDistance
      ..minFlingVelocity = physics.minFlingVelocity
      ..maxFlingVelocity = physics.maxFlingVelocity
      ..velocityTrackerBuilder = behavior.velocityTrackerBuilder(context)
      ..multitouchDragStrategy = behavior.getMultitouchDragStrategy(context)
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_inGutter(event.position)) return;
    _dragRecognizer()?.addPointer(event);
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (!_inGutter(event.position)) return;
    _dragRecognizer()?.addPointerPanZoom(event);
  }

  void _handleDragDown(DragDownDetails details) {
    _hold = _dragPosition?.hold(_disposeHold);
  }

  void _handleDragStart(DragStartDetails details) {
    _drag = _dragPosition?.drag(details, _disposeDrag);
    if (_hold != null) _disposeHold();
  }

  void _handleDragUpdate(DragUpdateDetails details) => _drag?.update(details);

  void _handleDragEnd(DragEndDetails details) => _drag?.end(details);

  void _handleDragCancel() {
    _hold?.cancel();
    _drag?.cancel();
  }

  void _disposeHold() => _hold = null;

  void _disposeDrag() => _drag = null;

  /// גלגלת ברצועה: כמו ב-Scrollable, נרשמת רק אם היא באמת תגלול, כדי
  /// שרשימה חיצונית תקבל אותה כשהפנימית בקצה.
  void _onPointerSignal(PointerSignalEvent event) {
    if (!_inGutter(event.position)) return;
    final position = _scrollablePosition();
    if (position == null) return;
    if (event is PointerScrollEvent) {
      final behavior = ScrollConfiguration.of(context);
      final flipAxes =
          event.kind == PointerDeviceKind.mouse &&
          HardwareKeyboard.instance.logicalKeysPressed.any(
            behavior.pointerAxisModifiers.contains,
          );
      var delta = flipAxes ? event.scrollDelta.dx : event.scrollDelta.dy;
      if (axisDirectionIsReversed(position.axisDirection)) delta = -delta;
      final target = math.min(
        math.max(position.pixels + delta, position.minScrollExtent),
        position.maxScrollExtent,
      );
      if (delta == 0 || target == position.pixels) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        position.pointerScroll(delta);
        (event as PointerScrollEvent).respond(allowPlatformDefault: false);
      });
    } else if (event is PointerScrollInertiaCancelEvent) {
      position.pointerScroll(0);
    }
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;
    _scrollableContext = notification.context;
    _metricsChanged.notify();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    var gutter = 0.0;
    if (widget.reserveGutter) {
      gutter = AppScrollbar.gutterOf(context) - widget.contentInset;
      if (gutter < 0) gutter = 0;
    }
    // המאזין מעל הפס: מחוות שמתחילות על האגודל נשארות של הפס, כי הוא
    // מקבל אותן לפני המאזין. שקוף, כדי שהרצועה לא תחסום את מה שמאחוריה.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: widget.controller,
          scrollbarOrientation: widget.side,
          thumbVisibility: widget.thumbVisibility,
          interactive: widget.interactive,
          child: _GutterBox(
            key: _boxKey,
            gutter: gutter,
            onRight: widget.side == ScrollbarOrientation.right,
            position: _position,
            metricsChanged: _metricsChanged,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Signal extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// הריווח של הרצועה, שנקבע בפריסה לפי מה שהרשימה מדווחת אחריה.
class _GutterBox extends SingleChildRenderObjectWidget {
  const _GutterBox({
    super.key,
    required this.gutter,
    required this.onRight,
    required this.position,
    required this.metricsChanged,
    required super.child,
  });

  /// רוחב הרצועה כשהיא פתוחה; 0 — אין רצועה כלל.
  final double gutter;
  final bool onRight;
  final ScrollPosition? Function() position;
  final Listenable metricsChanged;

  @override
  _RenderScrollbarGutter createRenderObject(BuildContext context) =>
      _RenderScrollbarGutter(
        gutter: gutter,
        onRight: onRight,
        position: position,
        metricsChanged: metricsChanged,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScrollbarGutter renderObject,
  ) {
    renderObject
      ..gutter = gutter
      ..onRight = onRight
      ..position = position
      ..metricsChanged = metricsChanged
      ..recheckHeldGutter();
  }
}

/// הקופסה שמחליטה על הרצועה בזמן הפריסה.
///
/// היא פורסת את הרשימה במצב הנוכחי ומיד קוראת את גבולות הגלילה. רשימה שיש בה
/// מה לגלול בלי רצועה מקבלת רצועה, ורשימה שנכנסת עם רצועה נפרסת שוב בלעדיה,
/// והרצועה יורדת רק אם גם אז אין מה לגלול. כך ההחלטה לא מזינה את עצמה
/// מפריים לפריים.
class _RenderScrollbarGutter extends RenderShiftedBox {
  _RenderScrollbarGutter({
    required this._gutter,
    required this._onRight,
    required this.position,
    required this._metricsChanged,
  }) : super(null);

  double get gutter => _gutter;
  double _gutter;
  set gutter(double value) {
    if (value == _gutter) return;
    _gutter = value;
    markNeedsLayout();
  }

  bool get onRight => _onRight;
  bool _onRight;
  set onRight(bool value) {
    if (value == _onRight) return;
    _onRight = value;
    markNeedsLayout();
  }

  ScrollPosition? Function() position;

  Listenable get metricsChanged => _metricsChanged;
  Listenable _metricsChanged;
  set metricsChanged(Listenable value) {
    if (identical(value, _metricsChanged)) return;
    if (attached) {
      _metricsChanged.removeListener(_onMetricsChanged);
      value.addListener(_onMetricsChanged);
    }
    _metricsChanged = value;
  }

  /// האם הרצועה פתוחה עכשיו.
  bool _reserved = false;

  /// גבולות הגלילה בסוף הפריסה האחרונה של הקופסה. התראה עם אותם גבולות היא
  /// הד של הפריסה הזו, ולא סיבה להחליט מחדש.
  double? _laidMin;
  double? _laidMax;

  double get _currentGutter => _reserved ? _gutter : 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _metricsChanged.addListener(_onMetricsChanged);
  }

  @override
  void detach() {
    _metricsChanged.removeListener(_onMetricsChanged);
    super.detach();
  }

  /// הרשימה נפרסה מחדש לבדה (הוויופורט הוא גבול פריסה): אם הגבולות השתנו
  /// מאז הפריסה של הקופסה, היא מחליטה שוב בפריים הבא.
  void _onMetricsChanged() {
    final p = position();
    if (p == null || !p.hasContentDimensions) return;
    if (p.minScrollExtent == _laidMin && p.maxScrollExtent == _laidMax) return;
    markNeedsLayout();
  }

  /// אזור הגלילה נבנה מחדש, ואולי התוכן השתנה. רצועה שנשמרת בלי שיש מה
  /// לגלול (תוכן שנכנס רק בזכותה) נבדקת שוב: כשהתוכן מתכווץ גבולות הגלילה
  /// נשארים 0, ולכן אין התראה שתעיר אותה.
  void recheckHeldGutter() {
    final held = _reserved && _laidMax != null && _laidMax! <= _laidMin!;
    if (held) markNeedsLayout();
  }

  /// האם הנקודה (גלובלית) נופלת ברצועה הפתוחה.
  bool isInGutter(Offset globalPosition) {
    final gutter = _currentGutter;
    if (gutter <= 0 || !attached || !hasSize) return false;
    final local = globalToLocal(globalPosition);
    if (local.dy < 0 || local.dy > size.height) return false;
    return _onRight
        ? local.dx >= size.width - gutter && local.dx <= size.width
        : local.dx >= 0 && local.dx < gutter;
  }

  EdgeInsets _insets(double gutter) =>
      // ui-lint: allow UIL-021 — הרצועה בצד הפיזי של הפס, שקבוע בימין או בשמאל בכל כיוון
      EdgeInsets.only(
        left: _onRight ? 0 : gutter,
        right: _onRight ? gutter : 0,
      );

  void _layoutChild(RenderBox child, bool reserved) {
    final gutter = reserved ? _gutter : 0.0;
    child.layout(constraints.deflate(_insets(gutter)), parentUsesSize: true);
    (child.parentData! as BoxParentData).offset = Offset(
      _onRight ? 0 : gutter,
      0,
    );
    size = constraints.constrain(
      Size(child.size.width + gutter, child.size.height),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    if (_gutter <= 0) _reserved = false;
    _layoutChild(child, _reserved);
    if (_gutter <= 0) return;
    final p = position();
    if (p == null || !p.hasContentDimensions) return;
    bool overflows() => p.maxScrollExtent > p.minScrollExtent;
    if (!_reserved) {
      if (overflows()) {
        _reserved = true;
        _layoutChild(child, true);
      }
    } else if (!overflows()) {
      _layoutChild(child, false);
      if (overflows()) {
        // גולש ברוחב מלא ונכנס רק בזכות הרצועה: הרצועה נשארת.
        _layoutChild(child, true);
      } else {
        _reserved = false;
      }
    }
    _laidMin = p.minScrollExtent;
    _laidMax = p.maxScrollExtent;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final gutter = _currentGutter;
    final inner = child.getDryLayout(constraints.deflate(_insets(gutter)));
    return constraints.constrain(Size(inner.width + gutter, inner.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height) ?? 0) + _currentGutter;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + _currentGutter;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(
        math.max(0, width - _currentGutter),
      ) ??
      0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(
        math.max(0, width - _currentGutter),
      ) ??
      0;
}
