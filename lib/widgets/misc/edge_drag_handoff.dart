import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// מעביר לרשימה שמעליו גרירה (לוח מגע, מסך מגע) שהתחילה כשהרשימה המקוננת
/// כבר בקצה בכיוון הגרירה.
///
/// ההכרעה נעשית פעם אחת בתחילת המחווה, כמו נעילת הגלילה בדפדפן: מחווה
/// שהזיזה את הרשימה המקוננת נשארת בה גם כשהיא מגיעה לקצה, ומחווה שהועברה
/// נשארת כולה ברשימה החיצונית, כולל שינוי כיוון ותנופה בסוף.
/// [builder] מקבל את ה-physics שהרשימה המקוננת חייבת להשתמש בהם.
class EdgeDragHandoff extends StatefulWidget {
  const EdgeDragHandoff({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollPhysics physics) builder;

  @override
  State<EdgeDragHandoff> createState() => _EdgeDragHandoffState();
}

class _EdgeDragHandoffState extends State<EdgeDragHandoff>
    with AutomaticKeepAliveClientMixin {
  final _HandoffLatch _latch = _HandoffLatch();
  late final ScrollPhysics _physics = _HandoffScrollPhysics(_latch);
  Drag? _outerDrag;

  // הספר יכול לגלול את הכרטיס אל מחוץ לטווח הרשימה; בלי זה הכרטיס נהרס
  // יחד עם מזהה הגרירה שלו, והספר נעצר באמצע המחווה.
  @override
  bool get wantKeepAlive => _outerDrag != null;

  @override
  void dispose() {
    // האב כבר עשוי להיות inactive; אם הוא מתפרק, הביטול שלו מאפס את הגרירה.
    // אחרת מסיימים אותה אחרי פירוק העץ, כשהאב שנותר פעיל שוב בטוח לשימוש.
    if (_outerDrag != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _endGesture(null, disposing: true),
      );
    }
    super.dispose();
  }

  ScrollPosition? _outerPositionFor(ScrollMetrics inner) {
    final outer = Scrollable.maybeOf(context)?.position;
    if (outer == null || !outer.hasPixels) return null;
    return outer.axis == inner.axis ? outer : null;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      case ScrollStartNotification(dragDetails: final DragStartDetails details):
        _endGesture(null);
        _latch.dragging = _outerPositionFor(notification.metrics) != null;
        _latch.kind = details.kind;
      case ScrollUpdateNotification(dragDetails: final DragUpdateDetails _):
        if (!_latch.handedOff) _latch.innerMoved = true;
      case OverscrollNotification(
        dragDetails: final DragUpdateDetails details,
      ):
        if (_latch.handedOff) _forward(notification.metrics, details);
      case ScrollEndNotification(:final dragDetails):
        _endGesture(dragDetails);
      default:
        break;
    }
    return false;
  }

  void _forward(ScrollMetrics inner, DragUpdateDetails details) {
    if (_outerDrag == null && !_latch.outerStarted) {
      _latch.outerStarted = true;
      final outer = _outerPositionFor(inner);
      if (outer == null) return;
      _outerDrag = outer.drag(
        DragStartDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          sourceTimeStamp: details.sourceTimeStamp,
          kind: _latch.kind,
        ),
        // ביטול מבחוץ (ניווט, גרירה אחרת): שאר המחווה לא מזיזה דבר.
        // גם פירוק האב משחרר את הגרירה, בלי לעדכן כרטיס שכבר פורק.
        () {
          if (_outerDrag == null) return;
          _outerDrag = null;
          if (mounted) updateKeepAlive();
        },
      );
      updateKeepAlive();
    }
    _outerDrag?.update(details);
  }

  void _endGesture(DragEndDetails? details, {bool disposing = false}) {
    final drag = _outerDrag;
    _outerDrag = null;
    _latch.reset();
    if (drag == null) return;
    if (details != null && details.primaryVelocity != null) {
      drag.end(details);
    } else {
      drag.cancel();
    }
    if (!disposing) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: (notification) {
        // הרשימה החיצונית היא שזזה; הבלטת קצה ברשימה הפנימית רק מבלבלת.
        if (_latch.handedOff) notification.disallowIndicator();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.builder(context, _physics),
      ),
    );
  }
}

class _HandoffLatch {
  /// גרירה של הרשימה המקוננת בעיצומה, ויש רשימה חיצונית באותו ציר.
  bool dragging = false;
  bool innerMoved = false;
  bool handedOff = false;
  bool outerStarted = false;
  PointerDeviceKind? kind;

  void reset() {
    dragging = false;
    innerMoved = false;
    handedOff = false;
    outerStarted = false;
    kind = null;
  }
}

/// ההכרעה כאן ולא בהודעת ה-overscroll, כדי שגם הצעד הראשון לא יפעיל את
/// אפקט הקצה של הרשימה הפנימית לפני שהועבר.
class _HandoffScrollPhysics extends ClampingScrollPhysics {
  const _HandoffScrollPhysics(this._latch, {super.parent});

  final _HandoffLatch _latch;

  @override
  _HandoffScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _HandoffScrollPhysics(_latch, parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final overscroll = super.applyBoundaryConditions(position, value);
    if (!_latch.dragging) return overscroll;
    // אחרי ההעברה כל התנועה נשארת בחוץ, גם בכיוון שבו הפנימית הייתה זזה.
    if (_latch.handedOff) return value - position.pixels;
    if (!_latch.innerMoved && _atEdgeToward(position, value)) {
      _latch.handedOff = true;
      return value - position.pixels;
    }
    return overscroll;
  }

  /// עם סבולת: שארית תת-פיקסלית מתיקוני גובה משוער אינה "תזוזה" של הרשימה.
  static bool _atEdgeToward(ScrollMetrics position, double value) {
    const tolerance = 0.5;
    if (value < position.pixels) {
      return position.pixels <= position.minScrollExtent + tolerance;
    }
    if (value > position.pixels) {
      return position.pixels >= position.maxScrollExtent - tolerance;
    }
    return false;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (_latch.handedOff) return null;
    return super.createBallisticSimulation(position, velocity);
  }
}
