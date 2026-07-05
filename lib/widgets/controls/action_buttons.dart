// lib/widgets/controls/action_buttons.dart
// כפתורי פעולה גנריים בסגנון M3.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

// ── ActionButton ──────────────────────────────────────────────────────────────

enum _Variant { recommended, neutral, ghost, warning }

/// כפתור פעולה גנרי בסגנון M3. השתמש בבנאים הממוינים:
/// - [ActionButton.recommended] — FilledButton (Primary) לפעולה מומלצת
/// - [ActionButton.neutral] — FilledButton.tonal לפעולה ניטרלית
/// - [ActionButton.ghost] — TextButton שקוף וניטרלי
/// - [ActionButton.warning] — TextButton שקוף עם טקסט cs.error לפעולות מסוכנות
class ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Widget? iconWidget;
  final TextAlign textAlign;
  final _Variant _variant;
  final FocusNode? focusNode;
  final bool autofocus;

  const ActionButton.recommended({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.iconWidget,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.autofocus = false,
  }) : _variant = _Variant.recommended;

  const ActionButton.neutral({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.iconWidget,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.autofocus = false,
  }) : _variant = _Variant.neutral;

  const ActionButton.ghost({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.iconWidget,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.autofocus = false,
  }) : _variant = _Variant.ghost;

  const ActionButton.warning({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.iconWidget,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.autofocus = false,
  }) : _variant = _Variant.warning;

  Color _loadingColor(ColorScheme cs) => switch (_variant) {
        _Variant.recommended => cs.onPrimary,
        _Variant.neutral => cs.onSecondaryContainer,
        _Variant.ghost => cs.primary,
        _Variant.warning => cs.error,
      };

  ButtonStyle? _buttonStyle(ColorScheme cs) => _variant == _Variant.warning
      ? TextButton.styleFrom(foregroundColor: cs.error)
      : null;

  Widget _plain({
    required VoidCallback? onPressed,
    required Widget child,
    required ButtonStyle? style,
  }) =>
      switch (_variant) {
        _Variant.recommended => FilledButton(
            onPressed: onPressed,
            focusNode: focusNode,
            autofocus: autofocus,
            child: child),
        _Variant.neutral => FilledButton.tonal(
            onPressed: onPressed,
            focusNode: focusNode,
            autofocus: autofocus,
            child: child),
        _Variant.ghost || _Variant.warning => TextButton(
            onPressed: onPressed,
            style: style,
            focusNode: focusNode,
            autofocus: autofocus,
            child: child),
      };

  Widget _withIcon({required Widget leading, required ButtonStyle? style}) {
    final label = Text(text, textAlign: textAlign);
    return switch (_variant) {
      _Variant.recommended => FilledButton.icon(
          onPressed: onPressed,
          focusNode: focusNode,
          autofocus: autofocus,
          icon: leading,
          label: label),
      _Variant.neutral => FilledButton.tonalIcon(
          onPressed: onPressed,
          focusNode: focusNode,
          autofocus: autofocus,
          icon: leading,
          label: label),
      _Variant.ghost || _Variant.warning => TextButton.icon(
          onPressed: onPressed,
          icon: leading,
          label: label,
          style: style,
          focusNode: focusNode,
          autofocus: autofocus),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leading = iconWidget ?? (icon != null ? RtlIcon(icon!) : null);
    final style = _buttonStyle(cs);

    if (isLoading) {
      return _plain(
        onPressed: null,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: _loadingColor(cs)),
        ),
        style: style,
      );
    }
    if (leading != null) {
      if (textAlign == TextAlign.center) {
        return _plain(
          onPressed: onPressed,
          child: _CenteredButtonContent(text: text, leading: leading),
          style: style,
        );
      }
      return _withIcon(leading: leading, style: style);
    }
    return _plain(
      onPressed: onPressed,
      child: Text(text, textAlign: textAlign),
      style: style,
    );
  }
}

// ── _CenteredButtonContent ────────────────────────────────────────────────────

// Stack במקום Row כדי שהטקסט יהיה ממורכז יחסית לרוחב הכפתור המלא,
// והאייקון צף בצד ה-start מבלי להזזת הטקסט.
class _CenteredButtonContent extends StatelessWidget {
  final String text;
  final Widget leading;

  const _CenteredButtonContent({
    required this.text,
    required this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _BalancedText(text, textAlign: TextAlign.center),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: leading,
          ),
        ),
      ],
    );
  }
}

// ── _BalancedText ─────────────────────────────────────────────────────────────

/// מציג טקסט עם חלוקה מאוזנת בין שורות:
/// בודק את כל נקודות השבירה האפשריות (בין מילים) ובוחר את זו
/// שמביאה לשורות בעלות רוחב שווה ככל האפשר.
class _BalancedText extends StatelessWidget {
  final String text;
  final TextAlign textAlign;

  const _BalancedText(
    this.text, {
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        DefaultTextStyle.of(context).style.copyWith(inherit: true);
    final textDir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        final singleLinePainter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: textDir,
          maxLines: 1,
        )..layout(maxWidth: double.infinity);

        if (singleLinePainter.width <= maxWidth) {
          return Text(text, textAlign: textAlign);
        }

        final words = text.split(' ');
        if (words.length <= 1) {
          return Text(text, textAlign: textAlign);
        }

        String bestText = text;
        double bestDiff = double.infinity;

        for (int i = 1; i < words.length; i++) {
          final line1 = words.sublist(0, i).join(' ');
          final line2 = words.sublist(i).join(' ');

          final p1 = TextPainter(
            text: TextSpan(text: line1, style: effectiveStyle),
            textDirection: textDir,
            maxLines: 1,
          )..layout(maxWidth: double.infinity);

          if (p1.width > maxWidth) continue;

          final p2 = TextPainter(
            text: TextSpan(text: line2, style: effectiveStyle),
            textDirection: textDir,
            maxLines: 1,
          )..layout(maxWidth: double.infinity);

          final diff = (p1.width - p2.width).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestText = '$line1\n$line2';
          }
        }

        return Text(bestText, textAlign: textAlign);
      },
    );
  }
}

// ── SecondaryIconButton / PrimaryIconButton ───────────────────────────────────

class SecondaryIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  const SecondaryIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: RtlIcon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class PrimaryIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  const PrimaryIconButton({
    super.key,
    required this.onPressed,
    this.icon = FluentIcons.open_24_regular,
    this.tooltip = 'פתח מקור',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: RtlIcon(icon, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── ToolbarActionButton ──────────────────────────────────────────────────────
/// כפתור סרגל עליון בסגנון M3 והגדרת מראה במצב נבחר.

class ToolbarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Widget? iconWidget;
  // null → הכפתור מוצג מושבת (עמעום ולחיצה מנוטרלת).
  final VoidCallback? onPressed;
  final bool selected;
  final String? label;
  final bool compact;
  final bool flipInRtl;

  const ToolbarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.iconWidget,
    required this.onPressed,
    this.selected = false,
    this.label,
    this.compact = false,
    this.flipInRtl = false,
  });

  @override
  Widget build(BuildContext context) {
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
            ? RtlIcon(icon, size: iconSize, color: fg)
            : Icon(icon, size: iconSize, color: fg);

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
