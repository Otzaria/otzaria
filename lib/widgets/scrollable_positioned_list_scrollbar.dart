import 'dart:math';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ScrollablePositionedListScrollbar extends StatefulWidget {
  final ItemScrollController scrollController;
  final ItemPositionsListener itemPositionsListener;
  final int itemCount;
  final Widget child;

  const ScrollablePositionedListScrollbar({
    super.key,
    required this.scrollController,
    required this.itemPositionsListener,
    required this.itemCount,
    required this.child,
  });

  @override
  State<ScrollablePositionedListScrollbar> createState() =>
      _ScrollablePositionedListScrollbarState();
}

class _ScrollablePositionedListScrollbarState
    extends State<ScrollablePositionedListScrollbar> {
  double _thumbPosition = 0.0;
  double _thumbHeight = 0.1; // יחס גובה ברירת מחדל
  bool _isDragging = false;
  double _dragPointerOffsetInThumb = 0.0;

  // להחלקת הקפיצות במיקום
  int _lastFirstIndex = 0;
  int _lastVisibleItems = 1;

  @override
  void initState() {
    super.initState();
    widget.itemPositionsListener.itemPositions
        .addListener(_updateScrollPosition);
  }

  @override
  void dispose() {
    widget.itemPositionsListener.itemPositions
        .removeListener(_updateScrollPosition);
    super.dispose();
  }

  void _updateScrollPosition() {
    if (_isDragging) return;

    final positions = widget.itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || widget.itemCount == 0) return;

    // מציאת האינדקסים הראשונים והאחרונים הנראים
    int minIndex = positions.first.index;
    int maxIndex = positions.first.index;

    for (var position in positions) {
      if (position.index < minIndex) minIndex = position.index;
      if (position.index > maxIndex) maxIndex = position.index;
    }

    _lastFirstIndex = minIndex;

    // חישוב גובה הפס ביחס לכמות הפריטים
    // מוסיפים 1 כדי למנוע חילוק ב-0
    final visibleItems = (maxIndex - minIndex + 1).clamp(1, widget.itemCount);
    _lastVisibleItems = visibleItems;
    final proportion = visibleItems / max(widget.itemCount, 1);

    // גובה מינימלי בפיקסלים ל"אגודל" הגלילה הוא בדרך כלל סביב 40-50 פיקסלים במסכים רגילים
    // אבל כאן אנחנו עובדים באחוזים (0.0 עד 1.0)
    // נניח שגובה המסך הוא H, גובה מינימלי h_min. אחוז מינימלי הוא h_min/H
    // נניח באופן שמרני שרצוי לפחות 5%
    final newHeight = proportion.clamp(0.05, 1.0);

    // חישוב המיקום היחסי (0.0 למעלה, 1.0 למטה)
    // האינדקסים הם 0-based.
    // אם minIndex הוא 0 -> top 0.
    // אם maxIndex הוא itemCount-1 -> bottom 1.0 (בערך)

    final maxScrollableIndex = max(widget.itemCount - visibleItems, 1);
    final scrollProgress = (minIndex / maxScrollableIndex).clamp(0.0, 1.0);
    final newPosition = scrollProgress * (1.0 - newHeight);

    setState(() {
      _thumbHeight = newHeight;
      _thumbPosition = newPosition;
    });
  }

  double _positionToProgress() {
    final maxThumbPosition = 1.0 - _thumbHeight;
    if (maxThumbPosition <= 0) return 0.0;
    return (_thumbPosition / maxThumbPosition).clamp(0.0, 1.0);
  }

  int _calculateTargetIndexFromThumb() {
    if (widget.itemCount <= 0) return 0;
    final visibleItems = _lastVisibleItems.clamp(1, widget.itemCount);
    final maxScrollableIndex = max(widget.itemCount - visibleItems, 0);
    if (maxScrollableIndex == 0) return 0;
    final progress = _positionToProgress();
    return (progress * maxScrollableIndex).round().clamp(0, maxScrollableIndex);
  }

  void _jumpToCurrentThumbPosition() {
    final targetIndex = _calculateTargetIndexFromThumb();
    if (targetIndex == _lastFirstIndex) return;
    widget.scrollController.jumpTo(index: targetIndex);
    _lastFirstIndex = targetIndex;
  }

  void _updateThumbFromPointer(
    double pointerY,
    double trackHeight, {
    required bool keepAnchor,
  }) {
    if (trackHeight <= 0) return;
    final thumbPixelHeight = trackHeight * _thumbHeight;
    final maxThumbTop = max(trackHeight - thumbPixelHeight, 0.0);

    double newThumbTop;
    if (keepAnchor) {
      newThumbTop = pointerY - _dragPointerOffsetInThumb;
    } else {
      newThumbTop = pointerY - (thumbPixelHeight / 2);
    }
    newThumbTop = newThumbTop.clamp(0.0, maxThumbTop);

    final newPosition = maxThumbTop <= 0 ? 0.0 : (newThumbTop / maxThumbTop);
    setState(() {
      _isDragging = true;
      _thumbPosition = newPosition;
    });

    _jumpToCurrentThumbPosition();
  }

  void _onDragEnd() {
    setState(() {
      _isDragging = false;
    });
    // עדכון סופי ליתר ביטחון
    _updateScrollPosition();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: widget.child,
        ),
        if (widget.itemCount > 0)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 12,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final trackHeight = constraints.maxHeight;
                final thumbPixelHeight = trackHeight * _thumbHeight;
                final thumbPixelTop = trackHeight * _thumbPosition;

                return GestureDetector(
                  onVerticalDragStart: (details) {
                    final pointerY = details.localPosition.dy;
                    final isOnThumb = pointerY >= thumbPixelTop &&
                        pointerY <= thumbPixelTop + thumbPixelHeight;
                    _dragPointerOffsetInThumb = isOnThumb
                        ? (pointerY - thumbPixelTop)
                        : (thumbPixelHeight / 2);
                    _updateThumbFromPointer(
                      pointerY,
                      trackHeight,
                      keepAnchor: true,
                    );
                  },
                  onVerticalDragUpdate: (details) {
                    _updateThumbFromPointer(
                      details.localPosition.dy,
                      trackHeight,
                      keepAnchor: true,
                    );
                  },
                  onVerticalDragEnd: (_) => _onDragEnd(),
                  onTapDown: (details) {
                    _updateThumbFromPointer(
                      details.localPosition.dy,
                      trackHeight,
                      keepAnchor: false,
                    );
                    setState(() {
                      _isDragging = false;
                    });
                    _updateScrollPosition();
                  },
                  child: Container(
                    color: Colors.transparent, // כדי לתפוס מגע
                    child: Stack(
                      children: [
                        // ה"אגודל" (Thumb) עצמו
                        Positioned(
                          top: thumbPixelTop,
                          left: 2, // רווח קטן מהקצה
                          right: 2,
                          height: thumbPixelHeight,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isDragging
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.8)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
