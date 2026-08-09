import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// העיטור המשותף לתפריטים הנפתחים בשורת החיפוש — היקף החיפוש וסוג החיפוש.
/// שניהם נפתחים זה לצד זה, ולכן חייבים להיראות מאותה משפחה.
abstract class SearchMenuSurface {
  static const double elevation = 8;
  static const EdgeInsets listPadding = EdgeInsets.symmetric(vertical: 4);

  static Color background(ColorScheme cs) => cs.surfaceContainerHigh;

  static ShapeBorder shape(ColorScheme cs) => RoundedRectangleBorder(
    borderRadius: AppTokens.borderRadiusAll,
    side: BorderSide(color: cs.outlineVariant),
  );
}

/// שורה בתפריטי החיפוש. תוכן בלבד — המפעיל אחראי על הלחיצה, כי תפריט ההיקף
/// עוטף ב-InkWell משלו והתפריט הנפתח מקבל אחד מ-[PopupMenuItem].
class SearchMenuRow extends StatelessWidget {
  const SearchMenuRow({
    super.key,
    required this.label,
    this.subtitle = '',
    this.icon,
    this.useRtlIcon = false,
    this.iconColor,
    this.leading,
    this.trailing,
    this.highlighted = false,
  });

  /// גובה השורה — גם ניווט המקלדת בתפריט ההיקף גולל לפיו.
  static const double height = 44;

  /// רוחב עמודת הסימון שבראש השורה. שמור גם כשאין סימון, כדי שכל התוויות
  /// יתחילו באותו קו.
  static const double markerWidth = 28;

  final String label;
  final String subtitle;
  final IconData? icon;
  final bool useRtlIcon;
  final Color? iconColor;
  final Widget? leading;
  final Widget? trailing;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? cs.onSurfaceVariant;

    return Container(
      constraints: const BoxConstraints(minHeight: height),
      color: highlighted ? AppSurfaces.menuKeyboardHighlight(cs) : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          SizedBox(width: markerWidth, height: markerWidth, child: leading),
          const SizedBox(width: 2),
          if (icon != null) ...[
            useRtlIcon
                ? RtlIcon(icon!, size: 18, color: effectiveIconColor)
                : Icon(icon, size: 18, color: effectiveIconColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    // outline — אפור עמום יותר מ-onSurfaceVariant, כדי שההסבר
                    // לא יתחרה בשם הפריט שמעליו.
                    style: TextStyle(fontSize: 11, color: cs.outline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            trailing!,
          ],
        ],
      ),
    );
  }
}
