import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// הטון של [MetaChip] (DD-13).
enum MetaChipTone {
  /// מידע רגיל: תקופה, דור, מונה, מצב כבוי.
  neutral,

  /// הדגשה: שעה, מצב "זמין".
  primary,

  /// תקלה: "התיקייה לא נמצאה".
  error,

  /// דורש תשומת לב: "סריקה חלקית".
  warning,

  /// הושלם או פעיל. בגוון החום הנייטרלי (secondaryContainer), לא בירוק (DD-24).
  success,
}

/// הגודל של [MetaChip]: regular לכרטיסים, small לשורות צפופות.
enum MetaChipSize { regular, small }

/// תגית קטנה לקריאה בלבד: תקופה, דור, קטגוריה, מצב ועוד (DD-13).
/// לבחירה משתמשים ב־[FilterChip] / [ChoiceChip] של Material (chipTheme).
class MetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final MetaChipTone tone;
  final MetaChipSize size;

  /// טקסט הריחוף. בלעדיו אין tooltip.
  final String? tooltip;

  /// מספר השורות של התווית, למשל תאריך עברי ולועזי בשתי שורות.
  final int maxLines;

  const MetaChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = MetaChipTone.neutral,
    this.size = MetaChipSize.regular,
    this.tooltip,
    this.maxLines = 1,
  });

  static const double _smallIconSize = 12;

  /// רקע וצבע התוכן של כל טון.
  static ({Color background, Color foreground}) colorsOf(
    BuildContext context,
    MetaChipTone tone,
  ) {
    final cs = Theme.of(context).colorScheme;
    return switch (tone) {
      MetaChipTone.neutral => (
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurfaceVariant,
      ),
      MetaChipTone.primary => (
        background: cs.primaryContainer,
        foreground: cs.onPrimaryContainer,
      ),
      MetaChipTone.error => (
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
      ),
      MetaChipTone.warning => (
        background: AppSurfaces.warningContainer(context),
        foreground: AppSurfaces.onWarningContainer(context),
      ),
      MetaChipTone.success => (
        background: cs.secondaryContainer,
        foreground: cs.onSecondaryContainer,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context, tone);
    final small = size == MetaChipSize.small;
    final textTheme = Theme.of(context).textTheme;
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Padding(
        padding: small
            ? const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceXS + AppTokens.space2XS,
                vertical: AppTokens.space2XS,
              )
            : const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceSM,
                vertical: AppTokens.spaceXS,
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              RtlIcon(
                icon!,
                size: small ? _smallIconSize : AppTokens.iconSM,
                color: colors.foreground,
              ),
              const SizedBox(width: AppTokens.spaceXS),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: (small ? textTheme.labelSmall : textTheme.labelMedium)
                    ?.copyWith(color: colors.foreground),
              ),
            ),
          ],
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}
