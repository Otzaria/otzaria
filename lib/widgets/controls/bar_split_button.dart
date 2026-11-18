// lib/widgets/controls/bar_split_button.dart
// לחצן סרגל מפוצל (split button) — פעולה ראשית וחץ שפותח תפריט לצידה.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/contained_tooltip.dart';
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

  /// כשמוגדר, החץ מפעיל אותו (עם ההקשר של העוגן) במקום לפתוח את [entries].
  /// ה-Future מסתיים כשהחלון נסגר — עד אז החץ מוצג הפוך.
  final Future<void> Function(BuildContext anchorContext)? onArrowPressed;

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
    this.onArrowPressed,
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

  /// החלון שנפתח מהחץ פתוח כרגע — החץ מתהפך עד שייסגר (בכל דרך שהיא).
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null || _menuOpen) return;
    setState(() => _menuOpen = true);
    try {
      await _showMenu(anchorContext);
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  Future<void> _showMenu(BuildContext anchorContext) async {
    if (widget.onArrowPressed != null) {
      await widget.onArrowPressed!(anchorContext);
      return;
    }
    final onSelected = widget.onSelected;
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
    if (selected != null) onSelected?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final actionEnabled = widget.onPressed != null;
    final menuEnabled =
        widget.onArrowPressed != null ||
        (widget.entries.isNotEmpty && widget.onSelected != null);

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
    // פינות מעוגלות קלות (רדיוס התוכנה) בצד החיצוני בלבד — לא חצי עיגול.
    // שני החצאים יחד = מלבן אחד עם פינות מעוגלות.
    const radius = Radius.circular(AppTokens.radius);
    final direction = Directionality.of(context);

    // ריחוף ולחיצה כמו ב-IconButton של BarButton.icon (bar_button.dart):
    // IconButton.styleFrom(foregroundColor: fg) נותן ריחוף fg@8%, ולחיצה
    // ופוקוס fg@10%, בלי highlight נפרד.
    Widget half({
      required Widget child,
      required VoidCallback? onTap,
      required String tooltip,
      required double width,
      required Color fg,
      required BorderRadiusDirectional borderRadius,
    }) {
      return ContainedTooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          // מעוגל רק בצד החיצוני, שטוח מול הקו המפריד — חצי של כמוסה אחת.
          // customBorder חותך את ההדגשה לצורה.
          customBorder: RoundedRectangleBorder(
            borderRadius: borderRadius.resolve(direction),
          ),
          overlayColor: AppSurfaces.barSplitOverlay(fg),
          splashColor: AppSurfaces.barSplitPressed(fg),
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
        duration: AppMotion.duration(context, AppTokens.animFast),
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
                fg: foreground(actionEnabled),
                borderRadius: BorderRadiusDirectional.horizontal(start: radius),
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
                fg: foreground(menuEnabled),
                borderRadius: BorderRadiusDirectional.horizontal(end: radius),
                // החץ מתהפך כשהחלון פתוח, סביב מרכז האייקון.
                child: AnimatedRotation(
                  turns: _menuOpen ? 0.5 : 0,
                  duration: AppTokens.animFast,
                  curve: Curves.easeInOut,
                  child: Icon(
                    FluentIcons.chevron_down_16_regular,
                    size: 14,
                    color: foreground(menuEnabled),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
