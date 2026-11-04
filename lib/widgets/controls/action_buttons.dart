// lib/widgets/controls/action_buttons.dart
// כפתורי פעולה גנריים בסגנון M3.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/contained_tooltip.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

// ── ActionButton ──────────────────────────────────────────────────────────────

enum _Variant { recommended, neutral, ghost, warning, warningSoft, inline }

/// כפתור פעולה גנרי בסגנון M3. השתמש בבנאים הממוינים:
/// - [ActionButton.recommended] — FilledButton (Primary) לפעולה מומלצת
/// - [ActionButton.neutral] — FilledButton.tonal לפעולה ניטרלית
/// - [ActionButton.ghost] — TextButton שקוף וניטרלי
/// - [ActionButton.warning] — FilledButton ברקע cs.error לפעולות מסוכנות,
///   בדיאלוג (אישור מחיקה)
/// - [ActionButton.warningSoft] — אותה פעולה מסוכנת על מסך הגדרות (לא בדיאלוג),
///   ברקע cs.errorContainer
/// - [ActionButton.inline] — ghost צפוף לפעולה בתוך שורה, הודעה או פירורי לחם
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

  /// טקסט אדום על כפתור [ActionButton.neutral] — לפעולה הרסנית שצריכה להישאר
  /// באותו מבנה כפתורים של הדיאלוג (למשל "בטל התראה" לצד "ביטול").
  final bool errorText;

  /// הודעת tooltip לכפתור. עדיף על עטיפה חיצונית ב-[Tooltip]: הבלון מקבל
  /// צומת סמנטיקה משלו ([ContainedTooltip]), ולכן אפשר להציב את הכפתור בתוך
  /// עוגן overlay אחר — למשל `MenuAnchor.builder`.
  final String? tooltip;

  /// צבע הטקסט של [ActionButton.inline], כשההקשר קובע אותו (למשל הודעה בטון
  /// שגיאה). null = primary.
  final Color? color;

  /// צד האייקון: [IconAlignment.start] (ברירת המחדל) לפני הטקסט, או
  /// [IconAlignment.end] אחריו ("הבא ←", "הצג עוד ⌄").
  final IconAlignment iconAlignment;

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
    this.tooltip,
    this.iconAlignment = IconAlignment.start,
  }) : errorText = false,
       color = null,
       _variant = _Variant.recommended;

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
    this.tooltip,
    this.errorText = false,
    this.iconAlignment = IconAlignment.start,
  }) : color = null,
       _variant = _Variant.neutral;

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
    this.tooltip,
    this.iconAlignment = IconAlignment.start,
  }) : errorText = false,
       color = null,
       _variant = _Variant.ghost;

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
    this.tooltip,
    this.iconAlignment = IconAlignment.start,
  }) : errorText = false,
       color = null,
       _variant = _Variant.warning;

  /// פעולה מסוכנת שיושבת על מסך הגדרות ולא בדיאלוג ("נקה הכל", "הסר"):
  /// רקע errorContainer וטקסט onErrorContainer, אדום רך שלא מושך את העין
  /// מכל שאר המסך. האדום המלא ([ActionButton.warning]) שמור לכפתור האישור
  /// שבדיאלוג שהפעולה פותחת.
  const ActionButton.warningSoft({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.iconWidget,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
    this.iconAlignment = IconAlignment.start,
  }) : errorText = false,
       color = null,
       _variant = _Variant.warningSoft;

  /// ghost צפוף: בלי גודל מינימלי, ריפוד 8×4, אזור מגע בגודל הכפתור, וטקסט
  /// 14 מודגש. לפעולה שיושבת בתוך שורה, הודעה צפה או פירורי לחם, שבהן כפתור
  /// בגובה 40 היה מגביה אותן.
  const ActionButton.inline({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
  }) : isLoading = false,
       icon = null,
       iconWidget = null,
       textAlign = TextAlign.start,
       errorText = false,
       iconAlignment = IconAlignment.start,
       _variant = _Variant.inline;

  Color _loadingColor(ColorScheme cs) => switch (_variant) {
    _Variant.recommended => cs.onPrimary,
    _Variant.neutral => cs.onSecondaryContainer,
    _Variant.ghost => cs.primary,
    _Variant.warning => cs.onError,
    _Variant.warningSoft => cs.onErrorContainer,
    _Variant.inline => color ?? cs.primary,
  };

  ButtonStyle? _buttonStyle(ThemeData theme) {
    final cs = theme.colorScheme;
    return switch (_variant) {
      _Variant.warning => FilledButton.styleFrom(
        backgroundColor: cs.error,
        foregroundColor: cs.onError,
      ),
      _Variant.warningSoft => FilledButton.styleFrom(
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
      ),
      _Variant.neutral when errorText => FilledButton.styleFrom(
        foregroundColor: cs.error,
      ),
      _Variant.inline => TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSM,
          vertical: AppTokens.spaceXS,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      _ => null,
    };
  }

  Widget _plain({
    required VoidCallback? onPressed,
    required Widget child,
    required ButtonStyle? style,
  }) => switch (_variant) {
    _Variant.recommended ||
    _Variant.warning ||
    _Variant.warningSoft => FilledButton(
      onPressed: onPressed,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      child: child,
    ),
    _Variant.neutral => FilledButton.tonal(
      onPressed: onPressed,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      child: child,
    ),
    _Variant.ghost || _Variant.inline => TextButton(
      onPressed: onPressed,
      style: style,
      focusNode: focusNode,
      autofocus: autofocus,
      child: child,
    ),
  };

  Widget _withIcon({required Widget leading, required ButtonStyle? style}) {
    final label = Text(text, textAlign: textAlign);
    return switch (_variant) {
      _Variant.recommended ||
      _Variant.warning ||
      _Variant.warningSoft => FilledButton.icon(
        onPressed: onPressed,
        style: style,
        focusNode: focusNode,
        autofocus: autofocus,
        iconAlignment: iconAlignment,
        icon: leading,
        label: label,
      ),
      _Variant.neutral => FilledButton.tonalIcon(
        onPressed: onPressed,
        style: style,
        focusNode: focusNode,
        autofocus: autofocus,
        iconAlignment: iconAlignment,
        icon: leading,
        label: label,
      ),
      _Variant.ghost || _Variant.inline => TextButton.icon(
        onPressed: onPressed,
        icon: leading,
        label: label,
        iconAlignment: iconAlignment,
        style: style,
        focusNode: focusNode,
        autofocus: autofocus,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final button = _buildButton(context);
    return ContainedTooltip(message: tooltip ?? '', child: button);
  }

  Widget _buildButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leading = iconWidget ?? (icon != null ? RtlIcon(icon!) : null);
    final style = _buttonStyle(Theme.of(context));

    if (isLoading) {
      return _plain(
        onPressed: null,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _loadingColor(cs),
          ),
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
    final effectiveStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(inherit: true);
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

// ── SquareIconButton ──────────────────────────────────────────────────────────

enum _SquareVariant { field, toolbar }

/// כפתור אייקון מרובע (פינות מעוגלות ברדיוס האחיד) בגובה שדה קלט:
/// - [SquareIconButton.field] — רקע tonal, לשורה אחת עם [OtzariaSearchField]
/// - [SquareIconButton.toolbar] — רקע שקוף, בתוך סרגל צף שכבר צבוע
///
/// [slim] = null: יורש מ-[AppDensity], בדיוק כמו שדה החיפוש,
/// כדי שהגבהים יישארו זהים בשני המצבים.
class SquareIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool? slim;
  final _SquareVariant _variant;

  const SquareIconButton.field({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.slim,
  }) : _variant = _SquareVariant.field;

  const SquareIconButton.toolbar({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.slim,
  }) : _variant = _SquareVariant.toolbar;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSlim = slim ?? AppDensity.of(context).isCompact;
    final side = AppInputTokens.height(isSlim);

    return SizedBox(
      width: side,
      height: side,
      child: IconButton(
        icon: Icon(icon, size: isSlim ? 18 : 20),
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: _variant == _SquareVariant.field
              ? cs.surfaceContainerHighest
              : Colors.transparent,
          foregroundColor: cs.onSurfaceVariant,
          shape: const RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
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
    return IconButton(
      icon: RtlIcon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: AppTokens.roundedShape,
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
    return IconButton(
      icon: RtlIcon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: AppTokens.roundedShape,
      ),
    );
  }
}
