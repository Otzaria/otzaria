// lib/widgets/controls/action_buttons.dart
//
// כפתורי פעולה גנריים בסגנון M3.
//
// **שינויים v4:**
// • ToolbarActionButton — selected משתמש ב-primary/onPrimary
//   כדי לבלוט בצורה ברורה על סרגל secondaryContainer.
// • מצב לא נבחר נשאר שקט יותר עם surface containers.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ── RecommendedActionButton ───────────────────────────────────────────────────

/// כפתור פעולה מומלצת — Primary FilledButton
class RecommendedActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;
  final Widget? iconWidget;
  final TextAlign textAlign;

  const RecommendedActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.iconWidget,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leading = iconWidget ?? (icon != null ? Icon(icon) : null);

    if (isLoading) {
      return FilledButton(
          onPressed: null,
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onPrimary)));
    }
    if (leading != null) {
      if (textAlign == TextAlign.center) {
        // מירכוז אמיתי: הטקסט ממורכז יחסית לרוחב הכפתור המלא,
        // האייקון צף בצד ה-start (ימין ב-RTL)
        return FilledButton(
          onPressed: onPressed,
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: _BalancedText(
                    text,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: leading,
                ),
              ),
            ],
          ),
        );
      }
      return FilledButton.icon(
          onPressed: onPressed,
          icon: leading,
          label: Text(text, textAlign: textAlign));
    }
    return FilledButton(
        onPressed: onPressed, child: Text(text, textAlign: textAlign));
  }
}

// ── NeutralActionButton ───────────────────────────────────────────────────────

/// כפתור פעולה ניטרלית — Tonal/SecondaryContainer FilledButton
class NeutralActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;

  const NeutralActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isLoading) {
      return FilledButton.tonal(
          onPressed: null,
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onSecondaryContainer)));
    }
    if (icon != null) {
      return FilledButton.tonalIcon(
          onPressed: onPressed, icon: Icon(icon), label: Text(text));
    }
    return FilledButton.tonal(onPressed: onPressed, child: Text(text));
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // בדוק אם הטקסט נכנס בשורה אחת
        final singleLinePainter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          maxLines: 1,
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: double.infinity);

        if (singleLinePainter.width <= maxWidth) {
          return Text(text,
              textAlign: textAlign, textDirection: TextDirection.rtl);
        }

        // מצא את נקודת השבירה שנותנת שורות שוות ביותר
        final words = text.split(' ');
        if (words.length <= 1) {
          return Text(text,
              textAlign: textAlign, textDirection: TextDirection.rtl);
        }

        String bestText = text;
        double bestDiff = double.infinity;

        for (int i = 1; i < words.length; i++) {
          final line1 = words.sublist(0, i).join(' ');
          final line2 = words.sublist(i).join(' ');

          final p1 = TextPainter(
            text: TextSpan(text: line1, style: effectiveStyle),
            maxLines: 1,
            textDirection: TextDirection.rtl,
          )..layout(maxWidth: double.infinity);

          // אם שורה 1 רחבה מהמקום הפנוי — לא ניתן לשבור כאן
          if (p1.width > maxWidth) continue;

          final p2 = TextPainter(
            text: TextSpan(text: line2, style: effectiveStyle),
            maxLines: 1,
            textDirection: TextDirection.rtl,
          )..layout(maxWidth: double.infinity);

          final diff = (p1.width - p2.width).abs();
          if (diff < bestDiff) {
            bestDiff = diff;
            bestText = '$line1\n$line2';
          }
        }

        return Text(bestText,
            textAlign: textAlign, textDirection: TextDirection.rtl);
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
        icon: Icon(icon, size: 20),
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
        icon: Icon(icon, size: 20),
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
  final VoidCallback onPressed;
  final bool selected;
  final String? label;
  final bool compact;

  const ToolbarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.iconWidget,
    required this.onPressed,
    this.selected = false,
    this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg =
        selected ? cs.onSurface.withValues(alpha: 0.12) : Colors.transparent;

    final Color fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    final double iconSize = compact ? 20 : 20;
    final double fontSize = compact ? 12 : 14;
    final double minSize = compact ? 36 : 40;
    final EdgeInsets padding = compact
        ? const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0)
        : const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0);

    // אייקון עם הצבע הנכון — IconTheme מאפשר לwidgets מורכבים (RotatedBox, Transform)
    // לרשת את הצבע באופן אוטומטי דרך nested Icon.
    final Widget iconEl = iconWidget != null
        ? IconTheme(
            data: IconThemeData(color: fg, size: iconSize),
            child: iconWidget!,
          )
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
        padding:
            compact ? const EdgeInsets.all(8.0) : const EdgeInsets.all(8.0),
        constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: fg,
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Tooltip(
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
    );
  }
}
