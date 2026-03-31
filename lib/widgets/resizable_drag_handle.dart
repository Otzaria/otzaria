import 'dart:ui';

import 'package:flutter/material.dart';

class ResizableDragHandle extends StatefulWidget {
  const ResizableDragHandle({
    super.key,
    required this.isVertical,
    this.cursor,
    this.hitSize = 8,
    this.onDragDelta,
    this.onDragStart,
    this.onDragEnd,
    this.showDivider = true,
  });

  /// True for a vertical handle (between left/right panes), false for horizontal.
  final bool isVertical;

  /// Optional cursor override. Defaults to resizeColumn/resizeRow.
  final MouseCursor? cursor;

  /// Total interactive thickness (width for vertical, height for horizontal).
  final double hitSize;

  /// Called with the delta along the resize axis (dx if vertical, dy if horizontal).
  final ValueChanged<double>? onDragDelta;

  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Whether to show the divider line in idle state. If false, the line only appears on hover/drag.
  final bool showDivider;

  @override
  State<ResizableDragHandle> createState() => _ResizableDragHandleState();
}

class _ResizableDragHandleState extends State<ResizableDragHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _setDragging(bool value) {
    if (_isDragging == value) return;
    setState(() => _isDragging = value);
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onDragDelta != null;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dividerColor = theme.dividerColor.withValues(alpha: 0.55);
    final activeColor = cs.primary.withValues(alpha: 0.95);

    final targetBlend = !isEnabled
        ? 0.0
        : _isDragging
            ? 1.0
            : _isHovered
                ? 0.5
                : 0.0;

    final cursor = widget.cursor ??
        (widget.isVertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow);

    return MouseRegion(
      cursor: isEnabled ? cursor : SystemMouseCursors.basic,
      onEnter: isEnabled ? (_) => _setHovered(true) : null,
      onExit: isEnabled ? (_) => _setHovered(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: !isEnabled
            ? null
            : (_) {
                _setDragging(true);
                widget.onDragStart?.call();
              },
        onPanUpdate: !isEnabled
            ? null
            : (details) {
                final delta =
                    widget.isVertical ? details.delta.dx : details.delta.dy;
                widget.onDragDelta?.call(delta);
              },
        onPanEnd: !isEnabled
            ? null
            : (_) {
                _setDragging(false);
                _setHovered(false);
                widget.onDragEnd?.call();
              },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: targetBlend),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          builder: (context, blend, _) {
            final highlightColor = cs.primary.withValues(alpha: 0.10 * blend);
            final thickness = lerpDouble(2.0, 4.0, blend) ?? 2.0;
            final gripLength =
                lerpDouble(widget.hitSize * 0.55, widget.hitSize * 0.8, blend) ??
                    widget.hitSize * 0.55;
            final showGrip = widget.showDivider || blend > 0;
            final lineColor = showGrip
                ? (Color.lerp(dividerColor, activeColor, blend) ?? dividerColor)
                : Colors.transparent;

            return Container(
              color: Colors.transparent,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: widget.isVertical ? thickness + 10 : gripLength,
                height: widget.isVertical ? gripLength : thickness + 10,
                decoration: BoxDecoration(
                  color: highlightColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: lineColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: SizedBox(
                    width: widget.isVertical ? thickness : gripLength,
                    height: widget.isVertical ? gripLength : thickness,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
