import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// כמה משטח המגע של הידית נכנס פנימה לתוך הפאנל. בקצה הפנימי יושב גם פס
/// הגלילה, והידית מצוירת מעליו ב-Stack — כניסה גדולה קוברת אותו. 4px היה
/// הערך בפועל עד שהגדלת שטח המגע מיקמה חצי ממנו בתוך הפאנל; היתרה גולשת
/// החוצה, אל הרווח שבין הפאנל לתוכן.
const double kPaneHandleInnerReach = 4;

/// שטח המגע המלא של הידית: 24px רגיל, 18px במצב קומפקטי.
double handleHitSize(BuildContext context) {
  final isCompact =
      context.read<SettingsBloc?>()?.state.compactMenuMode ?? false;
  return isCompact
      ? AppTokens.dragHandleCompactHitSize
      : AppTokens.dragHandleRegularHitSize;
}

/// היתרה שגולשת החוצה מהפאנל, אל הרווח שבינו לתוכן.
double handleHitOutreach(BuildContext context) =>
    handleHitSize(context) - kPaneHandleInnerReach;

/// בכמה להזיז את הקו הנראה כדי שיישב על דופן הפאנל: שטח המגע אינו ממורכז
/// עליה אלא גולש החוצה, ובלי ההזזה הקו מרחף מנותק ממנה.
double paneHandleGripOffset(BuildContext context, {required bool paneOnRight}) {
  final shift = handleHitSize(context) / 2 - kPaneHandleInnerReach;
  return paneOnRight ? shift : -shift;
}

class ResizableDragHandle extends StatefulWidget {
  const ResizableDragHandle({
    super.key,
    required this.isVertical,
    this.cursor,
    this.hitSize,
    this.onDragDelta,
    this.onDragStart,
    this.onDragEnd,
    this.showDivider = true,
    this.gripOffset = 0,
  });

  /// True for a vertical handle (between left/right panes), false for horizontal.
  final bool isVertical;

  /// Optional cursor override. Defaults to resizeColumn/resizeRow.
  final MouseCursor? cursor;

  /// Total interactive thickness (width for vertical, height for horizontal).
  /// If null, auto-selects 24 when compactMenuMode is off, 18 when on.
  final double? hitSize;

  /// Called with the delta along the resize axis (dx if vertical, dy if horizontal).
  final ValueChanged<double>? onDragDelta;

  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  /// Whether to show the divider line in idle state. If false, the line only appears on hover/drag.
  final bool showDivider;

  /// הזזת הקו הנראה בפיקסלים לאורך ציר השינוי. ראה [paneHandleGripOffset].
  final double gripOffset;

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
    final isCompact =
        context.read<SettingsBloc?>()?.state.compactMenuMode ?? false;
    final effectiveHitSize =
        widget.hitSize ??
        (isCompact
            ? AppTokens.dragHandleCompactHitSize
            : AppTokens.dragHandleRegularHitSize);
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

    final cursor =
        widget.cursor ??
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
                final delta = widget.isVertical
                    ? details.delta.dx
                    : details.delta.dy;
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
          duration: _isDragging ? Duration.zero : AppTokens.animFast,
          curve: Curves.easeOut,
          builder: (context, blend, _) {
            final highlightColor = cs.primary.withValues(alpha: 0.22 * blend);
            final thickness = lerpDouble(3.0, 5.0, blend) ?? 3.0;
            final gripLength = lerpDouble(24.0, 32.0, blend) ?? 24.0;
            final showGrip = widget.showDivider || blend > 0;
            final idleOpacity = lerpDouble(0.35, 1.0, blend) ?? 0.35;
            final lineColor = showGrip
                ? (Color.lerp(
                        dividerColor.withValues(alpha: idleOpacity),
                        activeColor,
                        blend,
                      ) ??
                      dividerColor)
                : Colors.transparent;
            final dividerThickness = lerpDouble(1.0, 2.0, blend) ?? 1.0;

            return SizedBox(
              width: widget.isVertical ? effectiveHitSize : null,
              height: widget.isVertical ? null : effectiveHitSize,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dividerExtent = widget.isVertical
                      ? (constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : gripLength)
                      : (constraints.hasBoundedWidth
                            ? constraints.maxWidth
                            : gripLength);

                  final grip = Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.showDivider)
                        Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: lineColor,
                              borderRadius: AppTokens.borderRadiusAll,
                            ),
                            child: SizedBox(
                              width: widget.isVertical
                                  ? dividerThickness
                                  : dividerExtent,
                              height: widget.isVertical
                                  ? dividerExtent
                                  : dividerThickness,
                            ),
                          ),
                        ),
                      AnimatedContainer(
                        duration: AppTokens.animFast,
                        curve: Curves.easeOut,
                        width: widget.isVertical ? thickness + 10 : gripLength,
                        height: widget.isVertical ? gripLength : thickness + 10,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: AppTokens.borderRadiusAll,
                        ),
                        alignment: Alignment.center,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: lineColor,
                            borderRadius: AppTokens.borderRadiusAll,
                          ),
                          child: SizedBox(
                            width: widget.isVertical ? thickness : gripLength,
                            height: widget.isVertical ? gripLength : thickness,
                          ),
                        ),
                      ),
                    ],
                  );

                  if (widget.gripOffset == 0) return grip;
                  // שטח המגע גולש החוצה ואינו ממורכז על דופן הפאנל; ההזזה
                  // מחזירה את הקו הנראה אל הדופן עצמה.
                  return Transform.translate(
                    offset: widget.isVertical
                        ? Offset(widget.gripOffset, 0)
                        : Offset(0, widget.gripOffset),
                    child: grip,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
