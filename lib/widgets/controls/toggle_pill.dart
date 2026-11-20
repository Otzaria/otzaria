import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/contained_tooltip.dart';
import 'package:otzaria/widgets/text/overflow_tooltip_text.dart';

/// מתג קומפקטי בגלולה: תווית ולצידה מתג קטן, ורקע מודגש כשדלוק. משמש
/// לאפשרות בודדת ליד שדה (דיאלוג החיפוש, איתור מקורות).
///
/// [tooltip] — הסבר בריחוף; null = בלי. טקסט שחוזר על [label] מוצג רק
/// כשהתווית נחתכת.
class AppTogglePill extends StatelessWidget {
  /// מידות המתג המוקטן: 3/4 מ-[Switch] ב-shrinkWrap (‏52×32).
  static const Size switchSize = Size(39, 24);

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  const AppTogglePill({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // טולטיפ שחוזר על התווית מיותר; היא מוצגת בריחוף רק כשהיא נחתכת.
    final repeatsLabel = tooltipRepeatsLabel(tooltip, label);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: value ? cs.primary : cs.onSurfaceVariant,
    );
    Widget pill = Container(
      decoration: BoxDecoration(
        color: AppSurfaces.togglePill(cs, active: value),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: repeatsLabel && tooltip != null
                ? OverflowTooltipText(
                    text: label,
                    style: labelStyle,
                  )
                : Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
          ),
          const SizedBox(width: 4),
          // FittedBox ולא Transform.scale: גם הפריסה מתכווצת, ולכן הגלולה
          // לא גולשת בגופן מוגדל.
          SizedBox.fromSize(
            size: switchSize,
            child: FittedBox(
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
    // במגע: שטח לחיצה בגובה 48 סביב הגלולה, באותו מראה (שאלה פתוחה 1).
    if (theme.materialTapTargetSize == MaterialTapTargetSize.padded) {
      pill = GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Center(widthFactor: 1, child: pill),
        ),
      );
    }
    pill = MergeSemantics(child: pill);
    if (!repeatsLabel) pill = Tooltip(message: tooltip!, child: pill);
    return pill;
  }
}
