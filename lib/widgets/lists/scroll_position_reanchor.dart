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

/// מעגן מחדש את הרשימה ברגיעה כדי ששינוי רוחב לא יסחוף את מקום הקריאה.
/// החבילה שומרת היסט מעוגן שמתעדכן רק בקפיצה תכנותית.
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

  /// החוב שייך למקור הגלילה המקוננת; ניווט שמפרק אותו משנה גם את העוגן.
  ({double pixels, BuildContext? context})? _owedAt;
  double _pixels = 0;

  @override
  void initState() {
    super.initState();
    widget.positionsListener.itemPositions.addListener(_trackSelected);
  }

  @override
  void didUpdateWidget(covariant ScrollPositionReanchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final listenerChanged =
        widget.positionsListener != oldWidget.positionsListener;
    if (listenerChanged) {
      oldWidget.positionsListener.itemPositions.removeListener(_trackSelected);
      widget.positionsListener.itemPositions.addListener(_trackSelected);
    }
    if (listenerChanged || widget.preferredIndex != oldWidget.preferredIndex) {
      _trackSelected();
    }
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
    var index = widget.preferredIndex;
    var edge = _selectedEdge;
    if (previous == null || previous == width || !widget.enabled) return;
    if (index == null || edge == null) {
      final owed = _owedAt != null
          ? reanchorTargetPosition(widget.positionsListener.itemPositions.value)
          : null;
      if (owed == null) return;
      index = owed.index;
      edge = owed.itemLeadingEdge;
    }
    // קפיצה לפני שהגלילה נחה מפילה את layout cycles של החבילה.
    if (_idleTimer?.isActive ?? false) return;
    _owedAt = null;
    final (targetIndex, alignment) = (index, edge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.scrollController.isAttached) return;
      _lastIndex = targetIndex;
      _lastAlignment = alignment;
      widget.scrollController.jumpTo(index: targetIndex, alignment: alignment);
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
        // גלילה ברשימה מקוננת (כרטיס המפרשים): קפיצה הייתה בונה את הפריט מחדש
        // ומאפסת אותה — ולכן גם עיגון שכבר תוזמן מגלילה חיצונית מתבטל.
        if (notification.depth != 0) {
          if (_idleTimer?.isActive ?? false) {
            _owedAt = (pixels: _pixels, context: notification.context);
          }
          _idleTimer?.cancel();
          return false;
        }
        final metrics = notification.metrics;
        _pixels = metrics.pixels;
        final owedAt = _owedAt;
        // רשימה מקוננת אינה גבוהה מהמסך, ולכן שני מסכים ממנה היא כבר מחוצה לו.
        if (owedAt != null &&
            (_pixels - owedAt.pixels).abs() >= 2 * metrics.viewportDimension) {
          _owedAt = null;
        }
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
    final owedAt = _owedAt;
    if (owedAt != null && owedAt.context?.mounted != false) return;
    _owedAt = null;
    if (!mounted || !widget.enabled || !widget.scrollController.isAttached) {
      return;
    }
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
