import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// תגית קטנה לקריאה בלבד: תקופה, דור, קטגוריה ועוד.
class MetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// תגית ניטרלית עם מסגרת, במקום תגית בצבע משני.
  final bool outlined;

  const MetaChip({
    super.key,
    required this.label,
    this.icon,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = outlined ? cs.onSurfaceVariant : cs.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined ? null : cs.secondaryContainer,
        border: outlined ? Border.all(color: cs.outlineVariant) : null,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSM,
          vertical: AppTokens.spaceXS,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: AppTokens.fontMD, color: foreground),
              const SizedBox(width: AppTokens.spaceXS),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: AppTokens.fontSM, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
