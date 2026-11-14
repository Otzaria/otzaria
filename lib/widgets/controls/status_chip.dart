import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// גוון הגלולה: [primary] כברירת מחדל, [error] לכשל.
enum StatusChipTone { primary, error }

/// "גלולת מצב" לחיצה בשורת הכותרת (עדכון זמין, מוריד, מוכן להתקנה):
/// משטח primaryContainer עם מסגרת primary, אייקון ותווית מודגשת.
///
/// [tone] [StatusChipTone.error] צובע במשטח וגבול השגיאה של ערכת הנושא.
/// [onPressed] null מצייר את הגלולה מושבתת. [icon] הוא Widget כדי שאפשר יהיה
/// להעביר מחוון התקדמות במקום אייקון.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.tooltip,
    this.tone = StatusChipTone.primary,
  }) : busy = false;

  /// מצב פעיל שאינו פעולה (למשל "מוריד..."): אותם צבעים כמו גלולה לחיצה,
  /// בלי ריחוף ובלי הכרזה ככפתור; קורא מסך קורא את התווית כטקסט.
  const StatusChip.busy({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
  }) : onPressed = null,
       busy = true,
       tone = StatusChipTone.primary;

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool busy;
  final StatusChipTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (container, accent, onContainer) = switch (tone) {
      StatusChipTone.primary => (
        cs.primaryContainer,
        cs.primary,
        cs.onPrimaryContainer,
      ),
      StatusChipTone.error => (
        cs.errorContainer,
        cs.error,
        cs.onErrorContainer,
      ),
    };
    final chip = Tooltip(
      message: tooltip,
      child: Material(
        color: container,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: accent, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: onContainer,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            disabledForegroundColor: busy ? onContainer : null,
            disabledIconColor: busy ? onContainer : null,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: icon,
          label: Text(label),
        ),
      ),
    );
    if (!busy) return chip;
    return Semantics(
      container: true,
      label: label,
      hint: tooltip,
      excludeSemantics: true,
      child: chip,
    );
  }
}
