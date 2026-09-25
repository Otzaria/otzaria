import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// הפריט הראשון שתחילתו בתוך התצוגה. רק הוא ניתן לביטוי כעוגן, כי
/// `alignment` של `jumpTo` מגיע ל-`Viewport.anchor` שחייב להיות בתחום [0,1].
ItemPosition? reanchorTargetPosition(Iterable<ItemPosition> positions) {
  ItemPosition? best;
  for (final position in positions) {
    if (position.itemLeadingEdge < 0 || position.itemLeadingEdge > 1) continue;
    if (best == null || position.itemLeadingEdge < best.itemLeadingEdge) {
      best = position;
    }
  }
  return best;
}

/// מעגן מחדש `ScrollablePositionedList` על הפריט שבראש התצוגה בכל פעם
/// שהגלילה נחה.
///
/// החבילה שומרת מיקום כ"פריט עוגן + היסט בפיקסלים", והעוגן מתעדכן רק בקפיצה
/// תכנותית. בלי העיגון הזה שינוי רוחב (חלונית שנפתחת, שינוי גודל החלון) שופך
/// את הטקסט מחדש, וההיסט הישן נוחת במקום אחר לגמרי.
class ScrollPositionReanchor extends StatefulWidget {
  const ScrollPositionReanchor({
    super.key,
    required this.scrollController,
    required this.positionsListener,
    required this.child,
    this.enabled = true,
    this.preferredIndex,
  });

  /// מבדיל בין "הגלילה נחה" לבין אנימציית גלילה שעדיין רצה — עיגון מחדש
  /// באמצע אנימציה היה מבטל אותה.
  static const idleDelay = Duration(milliseconds: 350);

  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final bool enabled;

  /// הפסקה הנבחרת: כשרוחב התצוגה משתנה היא חוזרת לגובה שבו הייתה, כדי שפתיחת
  /// חלונית לא תדחוף אותה מהמסך כשהפסקאות שמעליה מתארכות.
  final int? preferredIndex;
  final Widget child;

  @override
  State<ScrollPositionReanchor> createState() => _ScrollPositionReanchorState();
}

class _ScrollPositionReanchorState extends State<ScrollPositionReanchor> {
  Timer? _idleTimer;
  int? _lastIndex;
  double? _lastAlignment;
  double? _lastWidth;
  double? _selectedEdge;

  @override
  void initState() {
    super.initState();
    widget.positionsListener.itemPositions.addListener(_trackSelected);
  }

  @override
  void didUpdateWidget(covariant ScrollPositionReanchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferredIndex != oldWidget.preferredIndex) _trackSelected();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    widget.positionsListener.itemPositions.removeListener(_trackSelected);
    super.dispose();
  }

  void _trackSelected() {
    final index = widget.preferredIndex;
    _selectedEdge = index == null
        ? null
        : widget.positionsListener.itemPositions.value
              .where((p) => p.index == index)
              .map((p) => p.itemLeadingEdge)
              .where((edge) => edge >= 0 && edge <= 1)
              .firstOrNull;
  }

  /// נקרא לפני שהרשימה נפרסת ברוחב החדש, ולכן [_selectedEdge] עדיין מהרוחב
  /// הקודם.
  void _onWidth(double width) {
    final previous = _lastWidth;
    _lastWidth = width;
    final index = widget.preferredIndex;
    final edge = _selectedEdge;
    if (previous == null || previous == width || !widget.enabled) return;
    if (index == null || edge == null) return;
    // עוגן ישן (הגלילה עוד לא נחה): קפיצה אחרי השפיכה מפילה layout cycles.
    if (_idleTimer?.isActive ?? false) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.isAttached) return;
      _lastIndex = index;
      _lastAlignment = edge;
      widget.scrollController.jumpTo(index: index, alignment: edge);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _onWidth(constraints.maxWidth);
        return _buildListener();
      },
    );
  }

  Widget _buildListener() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!widget.enabled) return false;
        final metrics = notification.metrics;
        // `pixels` הוא ההיסט מהעוגן, והוא מתאפס בכל עיגון. כל עוד לא
        // התרחקנו ממנו מסך שלם, שינוי רוחב יזיז את הטקסט פחות ממסך —
        // ועיגון כאן היה בונה מחדש את כל טווח המטמון על כל נקישת גלגלת.
        if (metrics.pixels.abs() < metrics.viewportDimension) return false;
        _idleTimer?.cancel();
        _idleTimer = Timer(ScrollPositionReanchor.idleDelay, _reanchor);
        return false;
      },
      child: widget.child,
    );
  }

  void _reanchor() {
    if (!mounted || !widget.scrollController.isAttached) return;
    final anchor = reanchorTargetPosition(
      widget.positionsListener.itemPositions.value,
    );
    if (anchor == null) return;
    if (anchor.index == _lastIndex &&
        anchor.itemLeadingEdge == _lastAlignment) {
      return;
    }
    _lastIndex = anchor.index;
    _lastAlignment = anchor.itemLeadingEdge;
    widget.scrollController.jumpTo(
      index: anchor.index,
      alignment: anchor.itemLeadingEdge,
    );
  }
}
