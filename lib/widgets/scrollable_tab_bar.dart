import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// TabBar גלילה עם חיצים לשמאל/ימין ועיצוב יפה יותר.
class ScrollableTabBarWithArrows extends StatefulWidget {
  final TabController controller;
  final List<Widget> tabs;
  final TabAlignment? tabAlignment;
  // מאפשר לדעת אם יש גלילה אופקית (יש Overflow)
  final ValueChanged<bool>? onOverflowChanged;
  // האם להסתיר את החיצים כשאין גלילה (לצמצום רווחים)
  final bool hideArrowsWhenNotScrollable;

  const ScrollableTabBarWithArrows({
    super.key,
    required this.controller,
    required this.tabs,
    this.tabAlignment,
    this.onOverflowChanged,
    this.hideArrowsWhenNotScrollable = false,
  });

  @override
  State<ScrollableTabBarWithArrows> createState() =>
      _ScrollableTabBarWithArrowsState();
}

class _ScrollableTabBarWithArrowsState
    extends State<ScrollableTabBarWithArrows> {
  // נאתר את ה-ScrollPosition של ה-TabBar (isScrollable:true)
  ScrollPosition? _tabBarPosition;
  BuildContext? _scrollContext;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool? _lastOverflow;

  @override
  void dispose() {
    _detachPositionListener();
    super.dispose();
  }

  void _detachPositionListener() {
    _tabBarPosition?.removeListener(_onPositionChanged);
  }

  void _attachAndSyncPosition() {
    if (!mounted || _scrollContext == null) return;
    _adoptPositionFrom(_scrollContext!);
  }

  void _adoptPositionFrom(BuildContext ctx) {
    final state = Scrollable.maybeOf(ctx);
    if (state == null) return;
    final newPos = state.position;
    // וידוא שמדובר בציר אופקי
    final isHorizontal = newPos.axisDirection == AxisDirection.left ||
        newPos.axisDirection == AxisDirection.right;
    if (!isHorizontal) return;
    if (!identical(newPos, _tabBarPosition)) {
      _detachPositionListener();
      _tabBarPosition = newPos;
      _tabBarPosition!.addListener(_onPositionChanged);
    }
    _onPositionChanged();
  }

  void _onPositionChanged() {
    final pos = _tabBarPosition;
    if (pos == null) return;
    final canLeft = pos.pixels > pos.minScrollExtent + 0.5;
    final canRight = pos.pixels < pos.maxScrollExtent - 0.5;
    if (_canScrollLeft != canLeft || _canScrollRight != canRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
      _emitOverflowIfChanged();
    }
  }

  void _handleScrollMetrics(ScrollMetrics metrics) {
    final canLeft = metrics.pixels > metrics.minScrollExtent + 0.5;
    final canRight = metrics.pixels < metrics.maxScrollExtent - 0.5;
    if (_canScrollLeft != canLeft || _canScrollRight != canRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
      _emitOverflowIfChanged();
    }
  }

  void _emitOverflowIfChanged() {
    final overflow = _canScrollLeft || _canScrollRight;
    if (_lastOverflow != overflow) {
      _lastOverflow = overflow;
      widget.onOverflowChanged?.call(overflow);
    }
  }

  void _scrollBy(double delta) {
    final pos = _tabBarPosition;
    if (pos == null) return;
    final target =
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    pos.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _scrollLeft() => _scrollBy(-150);
  void _scrollRight() => _scrollBy(150);

  /// בונה כפתור חץ לגלילה
  Widget _buildArrowButton({
    required String keyValue,
    required bool canScroll,
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
  }) {
    return SizedBox(
      width: 36,
      height: 32,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: canScroll ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !canScroll,
          child: IconButton(
            key: ValueKey(keyValue),
            onPressed: onPressed,
            icon: Icon(icon),
            iconSize: 20,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            tooltip: tooltip,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasOverflow = _canScrollLeft || _canScrollRight;
    final bool showArrows =
        !widget.hideArrowsWhenNotScrollable || hasOverflow;

    return Row(
      children: [
        // חץ שמאלי – מוסתר לגמרי אם אין גלילה והאפשרות מופעלת
        if (showArrows)
          _buildArrowButton(
            keyValue: 'left-arrow',
            canScroll: _canScrollLeft,
            onPressed: _scrollLeft,
            icon: FluentIcons.chevron_left_24_regular,
            tooltip: 'גלול שמאלה',
          ),
        // TabBar משופר עם עיצוב יפה יותר
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (metricsNotification) {
              final metrics = metricsNotification.metrics;
              if (metrics.axis == Axis.horizontal) {
                _adoptPositionFrom(metricsNotification.context);
                _handleScrollMetrics(metrics);
              }
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.axis == Axis.horizontal) {
                  final ctx = notification.context;
                  if (ctx != null) {
                    _adoptPositionFrom(ctx);
                  }
                  _handleScrollMetrics(notification.metrics);
                }
                return false;
              },
              child: Builder(
                builder: (scrollCtx) {
                  // נשמור context כדי לאמץ את ה-ScrollPosition לאחר הבניה
                  if (!identical(_scrollContext, scrollCtx)) {
                    _scrollContext = scrollCtx;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _attachAndSyncPosition();
                    });
                  }
                  return TabBar(
                    controller: widget.controller,
                    isScrollable: true,
                    tabs: widget.tabs,
                    tabAlignment: widget.tabAlignment,
                    padding: EdgeInsets.zero,
                    labelPadding: EdgeInsets.zero,
                    indicatorPadding: EdgeInsets.zero,
                    dividerColor: Colors.transparent,
                    // הסרת האינדיקטור מתחת לטאב
                    indicator: const BoxDecoration(),
                    // הסרת ה-hover המרובע
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                    splashFactory: NoSplash.splashFactory,
                  );
                },
              ),
            ),
          ),
        ),
        // חץ ימני – מוסתר לגמרי אם אין גלילה והאפשרות מופעלת
        if (showArrows)
          _buildArrowButton(
            keyValue: 'right-arrow',
            canScroll: _canScrollRight,
            onPressed: _scrollRight,
            icon: FluentIcons.chevron_right_24_regular,
            tooltip: 'גלול ימינה',
          ),
      ],
    );
  }
}
