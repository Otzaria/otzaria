import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/misc/scrollable_hit_test_registry.dart';
import 'package:otzaria/widgets/misc/touch_pinch_scale_recognizer.dart';

/// צביטה בקורא וגלילת לוח מגע ששומרת על התנועה מתחילת המחווה.
class ReaderGestureDetector extends StatefulWidget {
  const ReaderGestureDetector({
    super.key,
    required this.beginPinch,
    required this.endPinch,
    required this.child,
  });

  final ValueChanged<double>? Function() beginPinch;
  final VoidCallback endPinch;
  final Widget child;

  @override
  State<ReaderGestureDetector> createState() => _ReaderGestureDetectorState();
}

class _ReaderGestureDetectorState extends State<ReaderGestureDetector> {
  final _scrollables = ScrollableHitTestRegistry();
  late final _recognizer = _ReaderTrackpadRecognizer(
    beginPinch: () => widget.beginPinch(),
    endPinch: () => widget.endPinch(),
  );
  ValueChanged<double>? _updateTouchPinch;

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, event.position, event.viewId);
    for (final entry in result.path) {
      final scrollable = _scrollables[entry.target];
      if (scrollable == null || !scrollable.mounted) continue;
      final position = scrollable.position;
      if (position.axis != Axis.vertical ||
          !position.hasPixels ||
          !position.hasContentDimensions ||
          !position.physics.shouldAcceptUserOffset(position)) {
        continue;
      }
      final behavior =
          scrollable.widget.scrollBehavior ??
          ScrollConfiguration.of(scrollable.context);
      if (!behavior.dragDevices.contains(event.kind)) continue;
      _recognizer.addFromScrollable(
        event.transformed(entry.transform),
        (scrollable: scrollable, behavior: behavior),
      );
      return;
    }
    _recognizer.addFromScrollable(event, null);
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollMetricsNotification>(
    onNotification: (notification) =>
        _scrollables.capture(notification.context),
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) =>
          _scrollables.capture(notification.context),
      child: _TrackpadStartListener(
        onPointerPanZoomStart: _onPanZoomStart,
        child: RawGestureDetector(
          gestures: {
            TouchPinchScaleRecognizer:
                GestureRecognizerFactoryWithHandlers<TouchPinchScaleRecognizer>(
                  () => TouchPinchScaleRecognizer(
                    debugOwner: this,
                    acceptsTrackpad: false,
                  ),
                  (recognizer) => recognizer
                    ..dragStartBehavior = DragStartBehavior.down
                    ..onStart = (_) {
                      _updateTouchPinch = widget.beginPinch();
                    }
                    ..onUpdate = (details) {
                      _updateTouchPinch?.call(details.scale);
                    }
                    ..onEnd = (_) {
                      _updateTouchPinch = null;
                      widget.endPinch();
                    },
                ),
          },
          child: widget.child,
        ),
      ),
    ),
  );
}

class _TrackpadStartListener extends Listener {
  const _TrackpadStartListener({
    required super.onPointerPanZoomStart,
    required Widget super.child,
  });

  @override
  RenderPointerListener createRenderObject(BuildContext context) =>
      _RenderTrackpadStartListener(
        onPointerPanZoomStart: onPointerPanZoomStart,
      );
}

class _RenderTrackpadStartListener extends RenderPointerListener {
  _RenderTrackpadStartListener({super.onPointerPanZoomStart});

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    // גם בעדכון ראשון גדול, המזהה של הקורא קודם למזהה הגרירה של הרשימה.
    result.add(BoxHitTestEntry(this, position));
    return hitTestChildren(result, position: position);
  }
}

class _ReaderTrackpadRecognizer extends VerticalDragGestureRecognizer {
  _ReaderTrackpadRecognizer({
    required this.beginPinch,
    required this.endPinch,
  }) : super(supportedDevices: const {PointerDeviceKind.trackpad}) {
    dragStartBehavior = DragStartBehavior.down;
    onlyAcceptDragOnThreshold = true;
    onStart = _startDrag;
    onUpdate = (details) => _drag?.update(details);
    onEnd = (details) => _drag?.end(details);
  }

  final ValueChanged<double>? Function() beginPinch;
  final VoidCallback endPinch;
  int? _pointer;
  ScrollableState? _scrollable;
  Offset _pan = Offset.zero;
  bool _won = false;
  bool _pinching = false;
  ValueChanged<double>? _updatePinch;
  Drag? _drag;

  void addFromScrollable(
    PointerPanZoomStartEvent event,
    ({ScrollableState scrollable, ScrollBehavior behavior})? target,
  ) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _scrollable = target?.scrollable;
    if (target != null) {
      final (scrollable: scrollable, behavior: behavior) = target;
      final physics = scrollable.position.physics;
      minFlingDistance = physics.minFlingDistance;
      minFlingVelocity = physics.minFlingVelocity;
      maxFlingVelocity = physics.maxFlingVelocity;
      velocityTrackerBuilder = behavior.velocityTrackerBuilder(
        scrollable.context,
      );
    }
    addPointerPanZoom(event);
  }

  void _startDrag(DragStartDetails details) {
    final scrollable = _scrollable;
    if (scrollable == null || !scrollable.mounted) return;
    _drag = scrollable.position.drag(details, () => _drag = null);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      (_scrollable?.mounted ?? false) &&
      _pan.dy.abs() > _pan.dx.abs() &&
      globalDistanceMoved.abs() > kPrecisePointerPanSlop;

  @override
  void acceptGesture(int pointer) {
    _won = true;
    super.acceptGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      _pan = event.pan;
      if (_pinching ||
          (event.scale - 1).abs() >
              TouchPinchScaleRecognizer.trackpadScaleSlop) {
        if (!_won) resolvePointer(event.pointer, GestureDisposition.accepted);
        if (!_won) return;
        if (!_pinching) {
          _pinching = true;
          _drag?.cancel();
          _updatePinch = invokeCallback<ValueChanged<double>?>(
            'beginPinch',
            beginPinch,
          );
        }
        invokeCallback<void>(
          'updatePinch',
          () => _updatePinch?.call(event.scale),
        );
        return;
      }
    } else if (event is PointerCancelEvent) {
      _drag?.cancel();
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    if (_pinching) invokeCallback('endPinch', endPinch);
    _pointer = null;
    _scrollable = null;
    _pan = Offset.zero;
    _won = false;
    _pinching = false;
    _updatePinch = null;
  }

  @override
  void dispose() {
    final drag = _drag;
    if (drag != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(_drag, drag)) drag.cancel();
      });
    }
    super.dispose();
  }
}
