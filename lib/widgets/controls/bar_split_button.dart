// lib/widgets/controls/bar_split_button.dart
// לחצן סרגל מפוצל (split button) — פעולה ראשית וחץ שפותח תפריט לצידה.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// לחצן סרגל מפוצל בסגנון [BarButton]: החלק עם האייקון מפעיל את [onPressed],
/// והחלק עם החץ פותח את [entries]. שני החלקים חולקים רקע ומופרדים בקו דק.
class BarSplitButton<T> extends StatefulWidget {
  static const double compactHeight = 36.0;
  static const double regularHeight = 40.0;

  static const double compactActionWidth = 34.0;
  static const double regularActionWidth = 38.0;

  static const double compactArrowWidth = 22.0;
  static const double regularArrowWidth = 24.0;

  static const double dividerWidth = 1.0;
  static const double outerHorizontalPadding = 2.0;

  static double toolbarWidth(bool compact) =>
      (compact ? compactActionWidth : regularActionWidth) +
      dividerWidth +
      (compact ? compactArrowWidth : regularArrowWidth) +
      outerHorizontalPadding * 2;

  final IconData icon;

  /// tooltip של החלק הראשי.
  final String tooltip;

  /// null → החלק הראשי מוצג מושבת.
  final VoidCallback? onPressed;

  /// פריטי התפריט שנפתח מהחץ. רשימה ריקה → החץ מושבת.
  final List<AppMenuEntry<T>> entries;
  final ValueChanged<T>? onSelected;

  /// הפריט המסומן בתפריט (✓).
  final T? initialValue;
  final String menuTooltip;
  final bool compact;
  final bool selected;

  const BarSplitButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.entries,
    required this.onSelected,
    this.initialValue,
    this.menuTooltip = 'אפשרויות נוספות',
    this.compact = false,
    this.selected = false,
  });

  @override
  State<BarSplitButton<T>> createState() => _BarSplitButtonState<T>();
}

class _BarSplitButtonState<T> extends State<BarSplitButton<T>> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _openMenu() async {
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;
    final selected = await showAnchoredAppMenu<T>(
      context: context,
      anchorContext: anchorContext,
      offset: const Offset(0, 8),
      initialValue: widget.initialValue,
      itemsBuilder: (metrics) => [
        for (final entry in widget.entries)
          buildAppPopupMenuItem<T>(
            context,
            entry,
            metrics,
            widget.initialValue,
          ),
      ],
    );
    if (selected != null) widget.onSelected?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final actionEnabled = widget.onPressed != null;
    final menuEnabled = widget.entries.isNotEmpty && widget.onSelected != null;

    Color foreground(bool enabled) => !enabled
        ? theme.disabledColor
        : (widget.selected ? cs.onSecondaryContainer : cs.onSurfaceVariant);

    final double height = widget.compact
        ? BarSplitButton.compactHeight
        : BarSplitButton.regularHeight;

    final double actionWidth = widget.compact
        ? BarSplitButton.compactActionWidth
        : BarSplitButton.regularActionWidth;

    final double arrowWidth = widget.compact
        ? BarSplitButton.compactArrowWidth
        : BarSplitButton.regularArrowWidth;
    final radius = Radius.circular(height / 2);
    final direction = Directionality.of(context);

    Widget half({
      required Widget child,
      required VoidCallback? onTap,
      required String tooltip,
      required double width,
      required BorderRadiusDirectional borderRadius,
    }) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius.resolve(direction),
          child: SizedBox(
            width: width,
            height: height,
            child: Center(child: child),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BarSplitButton.outerHorizontalPadding,
      ),
      child: AnimatedContainer(
        key: _anchorKey,
        duration: AppTokens.animFast,
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: widget.selected
              ? AppSurfaces.barButtonSelected(cs)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              half(
                tooltip: widget.tooltip,
                onTap: widget.onPressed,
                width: actionWidth,
                borderRadius: BorderRadiusDirectional.horizontal(
                  start: radius,
                ),
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: foreground(actionEnabled),
                ),
              ),
              Container(
                width: BarSplitButton.dividerWidth,
                height: height - 16,
                color: cs.outlineVariant,
              ),
              half(
                tooltip: widget.menuTooltip,
                onTap: menuEnabled ? _openMenu : null,
                width: arrowWidth,
                borderRadius: BorderRadiusDirectional.horizontal(end: radius),
                child: Icon(
                  FluentIcons.chevron_down_16_regular,
                  size: 14,
                  color: foreground(menuEnabled),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
