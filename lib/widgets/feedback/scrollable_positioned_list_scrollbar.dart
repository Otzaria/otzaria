import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/feedback/scrollbar_target_label.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// ההתקנים שגוררים פס גלילה. בלי לוח מגע: גלילה בשתי אצבעות מעל הפס אינה
/// גרירה, וכגרירה כל פיקסל שלה היה נמדד ביחס לכל המסמך.
const Set<PointerDeviceKind> kScrollbarDragDevices = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};

class ScrollablePositionedListScrollbar extends StatefulWidget {
  static const Key trackKey = Key('positioned-list-scrollbar-track');
  static const Key thumbKey = Key('positioned-list-scrollbar-thumb');

  /// הרצועה שהמסילה תופסת בקצה ההתחלה של אזור הקריאה.
  static const double trackWidth =
      _ScrollablePositionedListScrollbarState._trackWidth;

  final ItemScrollController scrollController;
  final int itemCount;
  final Widget child;

  /// הכתובת של הפריט שיגיע לראש התצוגה בלחיצה בנקודה זו במסילה.
  final String Function(int index)? labelForIndex;

  /// נקרא פעם אחת בתחילת ניווט דרך המסילה, לפני שינוי מיקום התוכן.
  final VoidCallback? onNavigationStart;

  const ScrollablePositionedListScrollbar({
    super.key,
    required this.scrollController,
    required this.itemCount,
    required this.child,
    this.labelForIndex,
    this.onNavigationStart,
  });

  @override
  State<ScrollablePositionedListScrollbar> createState() =>
      _ScrollablePositionedListScrollbarState();
}

class _ScrollablePositionedListScrollbarState
    extends State<ScrollablePositionedListScrollbar> {
  static const double _edgeGap = AppTokens.scrollbarMargin;
  static const double _contentGap = AppTokens.scrollbarContentGap;
  static const double _trackWidth = AppTokens.scrollbarGutter;

  ScrollMetrics? _metrics;
  double _thumbPosition = 0;
  double _thumbHeight = 1;
  bool _isDragging = false;
  bool _navigationStarted = false;
  Duration? _lastDragFrame;
  double? _pendingDragDelta;
  int? _dragFrameCallback;

  final ScrollbarTargetLabelController _labelController =
      ScrollbarTargetLabelController();
  int? _labelIndex;
  String? _labelText;

  bool get _canScroll =>
      widget.itemCount > 0 &&
      _metrics != null &&
      _metrics!.maxScrollExtent - _metrics!.minScrollExtent >
          precisionErrorTolerance;

  ScrollPosition? get _position {
    final controller = widget.scrollController.scrollController;
    if (controller == null || controller.positions.length != 1) return null;
    final position = controller.position;
    return position.hasContentDimensions ? position : null;
  }

  @override
  void didUpdateWidget(covariant ScrollablePositionedListScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _cancelPendingDrag();
      _metrics = null;
      _thumbPosition = 0;
      _thumbHeight = 1;
      _isDragging = false;
      _hideLabel();
    } else if (oldWidget.labelForIndex != widget.labelForIndex ||
        oldWidget.itemCount != widget.itemCount) {
      _labelIndex = null;
      if (widget.labelForIndex == null || widget.itemCount == 0) _hideLabel();
    }
  }

  @override
  void dispose() {
    _cancelPendingDrag();
    _labelController.dispose();
    super.dispose();
  }

  ScrollbarLabelSide get _labelSide =>
      Directionality.of(context) == TextDirection.rtl
      ? ScrollbarLabelSide.left
      : ScrollbarLabelSide.right;

  void _showLabel(double pixels, Offset pointer) {
    final labelForIndex = widget.labelForIndex;
    if (labelForIndex == null) return;
    var index = widget.scrollController.indexForScrollOffset(pixels);
    if (index == null) {
      final metrics = _metrics;
      if (metrics == null) return;
      if (pixels <= metrics.minScrollExtent) {
        index = 0;
      } else if (pixels >= metrics.maxScrollExtent) {
        index = widget.itemCount - 1;
      } else {
        return;
      }
    }
    if (index != _labelIndex) {
      _labelIndex = index;
      _labelText = labelForIndex(index);
    }
    _labelController.show(
      context,
      anchor: pointer,
      text: _labelText ?? '',
      side: _labelSide,
    );
  }

  void _hideLabel() {
    _labelIndex = null;
    _labelText = null;
    _labelController.hide();
  }

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth == 0) _updateMetrics(notification.metrics);
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 && notification is ScrollUpdateNotification) {
      _updateMetrics(notification.metrics);
    }
    return false;
  }

  void _updateScrollPosition() {
    final position = _position;
    if (position != null) _updateMetrics(position);
  }

  void _updateMetrics(ScrollMetrics metrics) {
    if (!mounted || metrics.axis != Axis.vertical) return;
    final range = metrics.maxScrollExtent - metrics.minScrollExtent;
    final viewport = metrics.viewportDimension;
    if (!range.isFinite || !viewport.isFinite || viewport <= 0) return;
    final couldScroll = _canScroll;
    _metrics = metrics.copyWith();
    final height = (viewport / (range + viewport)).clamp(0.05, 1.0);
    var progress = range > 0
        ? ((metrics.pixels - metrics.minScrollExtent) / range).clamp(0.0, 1.0)
        : 0.0;
    if (metrics.axisDirection == AxisDirection.up) progress = 1 - progress;
    final top = progress * (1 - height);
    if (!_canScroll) {
      _hideLabel();
      _cancelPendingDrag();
      _isDragging = false;
    }
    final thumbChanged =
        !_isDragging &&
        ((_thumbHeight - height).abs() > 1e-5 ||
            (_thumbPosition - top).abs() > 1e-5);
    if (couldScroll == _canScroll && !thumbChanged) return;
    setState(() {
      if (!_isDragging) {
        _thumbHeight = height;
        _thumbPosition = top;
      }
    });
  }

  double _targetFromThumbPosition(double position) {
    final metrics = _metrics!;
    final space = 1 - _thumbHeight;
    var fraction = space > 0 ? (position / space).clamp(0.0, 1.0) : 0.0;
    if (metrics.axisDirection == AxisDirection.up) fraction = 1 - fraction;
    return metrics.minScrollExtent +
        fraction * (metrics.maxScrollExtent - metrics.minScrollExtent);
  }

  double _thumbPositionFromTrack(double dy, double height) =>
      (dy / height - _thumbHeight / 2).clamp(0.0, 1 - _thumbHeight);

  bool _isOutsideThumb(double dy, double height) =>
      dy < height * _thumbPosition ||
      dy > height * (_thumbPosition + _thumbHeight);

  void _beginNavigation() {
    if (_navigationStarted) return;
    _navigationStarted = true;
    widget.onNavigationStart?.call();
    widget.scrollController.listController?.cancelPositioning();
  }

  void _jumpToTrackPosition(double dy, double height, [Offset? pointer]) {
    if (height <= 0 || !_canScroll) return;
    _beginNavigation();
    setState(() => _thumbPosition = _thumbPositionFromTrack(dy, height));
    final target = _targetFromThumbPosition(_thumbPosition);
    _jumpToPixels(target);
    if (pointer != null) _showLabel(target, pointer);
  }

  void _jumpToPixels(double target) {
    _lastDragFrame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final position = _position;
    if (position == null) return;
    position.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  double _targetFromDragDelta(double delta) {
    final metrics = _position ?? _metrics!;
    final reverse = metrics.axisDirection == AxisDirection.up;
    if (_thumbPosition <= 0) {
      return reverse ? metrics.maxScrollExtent : metrics.minScrollExtent;
    }
    if (_thumbPosition >= 1 - _thumbHeight) {
      return reverse ? metrics.minScrollExtent : metrics.maxScrollExtent;
    }
    return (metrics.pixels + delta).clamp(
      metrics.minScrollExtent,
      metrics.maxScrollExtent,
    );
  }

  void _requestDragJump(double delta) {
    // תנועה יחסית נשמרת גם אם תיקון עיגון משנה את הפיקסלים עד הציור.
    final target = _targetFromDragDelta(delta);
    if (target == _position?.pixels) {
      _cancelPendingDrag();
      return;
    }
    if (_lastDragFrame !=
        SchedulerBinding.instance.currentSystemFrameTimeStamp) {
      _cancelPendingDrag();
      _jumpToPixels(target);
      return;
    }
    _pendingDragDelta = target - (_position?.pixels ?? _metrics!.pixels);
    _dragFrameCallback ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _dragFrameCallback = null;
      final pending = _pendingDragDelta;
      _pendingDragDelta = null;
      if (mounted && pending != null) {
        _jumpToPixels(_targetFromDragDelta(pending));
      }
    });
  }

  void _cancelPendingDrag() {
    final callback = _dragFrameCallback;
    if (callback != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callback);
    }
    _dragFrameCallback = null;
    _pendingDragDelta = null;
  }

  void _onDragUpdate(double delta, Offset pointer) {
    if (!_canScroll) return;
    final previous = _thumbPosition;
    setState(
      () => _thumbPosition = (_thumbPosition + delta).clamp(
        0.0,
        1 - _thumbHeight,
      ),
    );
    final metrics = _position ?? _metrics!;
    final pixelsDelta =
        (_thumbPosition - previous) /
        (1 - _thumbHeight) *
        (metrics.maxScrollExtent - metrics.minScrollExtent) *
        (metrics.axisDirection == AxisDirection.up ? -1 : 1);
    final pending = (_pendingDragDelta ?? 0) + pixelsDelta;
    final target = _targetFromDragDelta(pending);
    _requestDragJump(pending);
    _showLabel(target, pointer);
  }

  void _onDragEnd({bool canceled = false}) {
    final pending = _pendingDragDelta;
    _cancelPendingDrag();
    if (!canceled && pending != null) {
      _jumpToPixels(_targetFromDragDelta(pending));
    }
    if (_isDragging) setState(() => _isDragging = false);
    _hideLabel();
    _updateScrollPosition();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_canScroll)
        SizedBox(
          width: _trackWidth,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              return MouseRegion(
                onHover: widget.labelForIndex == null
                    ? null
                    : (event) {
                        if (height <= 0) return;
                        _showLabel(
                          _targetFromThumbPosition(
                            _thumbPositionFromTrack(
                              event.localPosition.dy,
                              height,
                            ),
                          ),
                          event.position,
                        );
                      },
                onExit: (_) {
                  if (!_isDragging) _hideLabel();
                },
                child: Listener(
                  onPointerCancel: (_) => _onDragEnd(canceled: true),
                  onPointerDown: (_) {
                    if (!_isDragging) {
                      _navigationStarted = false;
                      _lastDragFrame = null;
                    }
                  },
                  child: GestureDetector(
                    key: ScrollablePositionedListScrollbar.trackKey,
                    behavior: HitTestBehavior.opaque,
                    supportedDevices: kScrollbarDragDevices,
                    dragStartBehavior: DragStartBehavior.down,
                    onVerticalDragStart: (details) {
                      _beginNavigation();
                      setState(() => _isDragging = true);
                      if (_isOutsideThumb(details.localPosition.dy, height)) {
                        _jumpToTrackPosition(
                          details.localPosition.dy,
                          height,
                          details.globalPosition,
                        );
                      }
                    },
                    onVerticalDragUpdate: (details) {
                      if (height > 0) {
                        _onDragUpdate(
                          details.delta.dy / height,
                          details.globalPosition,
                        );
                      }
                    },
                    onVerticalDragEnd: (_) => _onDragEnd(),
                    onVerticalDragCancel: () => _onDragEnd(canceled: true),
                    onTapDown: (details) {
                      if (_isOutsideThumb(details.localPosition.dy, height)) {
                        _jumpToTrackPosition(details.localPosition.dy, height);
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PositionedDirectional(
                          top: height * _thumbPosition,
                          start: _edgeGap,
                          end: _contentGap,
                          height: height * _thumbHeight,
                          child: Container(
                            key: ScrollablePositionedListScrollbar.thumbKey,
                            decoration: BoxDecoration(
                              color: AppSurfaces.scrollbarThumb(
                                Theme.of(context).colorScheme,
                                isDragging: _isDragging,
                              ),
                              borderRadius: AppTokens.borderRadiusAll,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      Expanded(
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: _onScrollMetrics,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: widget.child,
            ),
          ),
        ),
      ),
    ],
  );
}
