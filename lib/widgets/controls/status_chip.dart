import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// "גלולת מצב" לחיצה בשורת הכותרת (עדכון זמין, מוריד, מוכן להתקנה):
/// משטח primaryContainer עם מסגרת primary, אייקון ותווית מודגשת.
///
/// [onPressed] null מצייר את הגלולה מושבתת. [icon] הוא Widget כדי שאפשר יהיה
/// להעביר מחוון התקדמות במקום אייקון.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.tooltip,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(color: cs.primary, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: cs.onPrimaryContainer,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: icon,
          label: Text(label),
        ),
      ),
    );
  }
}
