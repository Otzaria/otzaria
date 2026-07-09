// lib/widgets/controls/bar_button.dart
// כפתורי סרגל (BarButton) — פריטים בסגנון M3 המשמשים ב-AppTopBar בכל האפליקציה.

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

enum _Variant { icon, text }

/// כפתור סרגל בסגנון M3. השתמש בבנאים הממוינים:
/// - [BarButton.icon] — כפתור אייקון (עם [label] אופציונלי) ומצב נבחר [selected].
/// - [BarButton.text] — כפתור טקסט ghost בצבע מושתק המתאים לאייקונים הלא-נבחרים.
class BarButton extends StatelessWidget {
  final _Variant _variant;

  // null → הכפתור מוצג מושבת (עמעום ולחיצה מנוטרלת).
  final VoidCallback? onPressed;

  // ── icon ──
  final String tooltip;
  final IconData? icon;
  final Widget? iconWidget;
  final bool selected;
  final String? label;
  final bool compact;
  final bool flipInRtl;

  // ── text ──
  final String text;
  final bool isLoading;

  const BarButton.icon({
    super.key,
    required this.tooltip,
    required IconData this.icon,
    this.iconWidget,
    required this.onPressed,
    this.selected = false,
    this.label,
    this.compact = false,
    this.flipInRtl = false,
  })  : _variant = _Variant.icon,
        text = '',
        isLoading = false;

  const BarButton.text({
    super.key,
    required this.text,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
  })  : _variant = _Variant.text,
        tooltip = '',
        iconWidget = null,
        selected = false,
        label = null,
        compact = false,
        flipInRtl = false;

  @override
  Widget build(BuildContext context) => switch (_variant) {
        _Variant.icon => _buildIcon(context),
        _Variant.text => _buildText(context),
      };

  // ── text ────────────────────────────────────────────────────────────────

  Widget _buildText(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // מיזוג עם סגנון התמה (ולא החלפתו) — שומר על roundedShape וה-overlay
    // ומחליף רק את צבע הטקסט/אייקון לגוון המושתק של הסרגל.
    final mergedStyle =
        (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? theme.disabledColor
            : cs.onSurfaceVariant,
      ),
    );
    return TextButtonTheme(
      data: TextButtonThemeData(style: mergedStyle),
      child: ActionButton.ghost(
        text: text,
        icon: icon,
        onPressed: onPressed,
        isLoading: isLoading,
      ),
    );
  }

  // ── icon ────────────────────────────────────────────────────────────────

  Widget _buildIcon(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool disabled = onPressed == null;

    final Color bg = selected && !disabled
        ? cs.onSurface.withValues(alpha: 0.12)
        : Colors.transparent;
    final Color fg = disabled
        ? theme.disabledColor
        : (selected ? cs.onSecondaryContainer : cs.onSurfaceVariant);

    const double iconSize = 20;
    final double fontSize = compact ? 12 : 14;
    final double minSize = compact ? 36 : 40;
    final EdgeInsets padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0)
        : const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0);

    // IconTheme מאפשר לwidgets מורכבים (RotatedBox, Transform) לרשת את הצבע אוטומטית.
    final Widget iconEl = iconWidget != null
        ? IconTheme(
            data: IconThemeData(color: fg, size: iconSize),
            child: iconWidget!,
          )
        : flipInRtl
            ? RtlIcon(icon!, size: iconSize, color: fg)
            : Icon(icon!, size: iconSize, color: fg);

    Widget button;
    if (label != null) {
      button = FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: fg,
          padding: padding,
          shape: const StadiumBorder(),
          minimumSize: compact ? const Size(0, 36) : const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: iconEl,
        label: AnimatedDefaultTextStyle(
          duration: AppTokens.animFast,
          style: TextStyle(
              fontSize: fontSize,
              color: fg,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal),
          child: Text(label!),
        ),
      );
    } else {
      button = IconButton(
        onPressed: onPressed,
        icon: iconEl,
        padding: const EdgeInsets.all(8.0),
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: fg,
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: AppTokens.animFast,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: bg,
            shape: label != null ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: label != null ? BorderRadius.circular(100) : null,
          ),
          child: button,
        ),
      ),
    );
  }
}
