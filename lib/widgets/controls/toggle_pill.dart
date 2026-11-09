import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/controls/custom_switch.dart';

/// מתג קומפקטי בגלולה: תווית ולצידה מתג קטן, ורקע מודגש כשדלוק. משמש
/// לאפשרות בודדת ליד שדה (דיאלוג החיפוש, איתור מקורות).
///
/// [tooltip] — הסבר בריחוף; null = בלי.
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
    final cs = Theme.of(context).colorScheme;
    Widget pill = Container(
      decoration: BoxDecoration(
        color: AppSurfaces.togglePill(cs, active: value),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: value ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // FittedBox ולא Transform.scale: גם הפריסה מתכווצת, ולכן הגלולה
            // לא גולשת בגופן מוגדל.
            SizedBox.fromSize(
              size: switchSize,
              child: FittedBox(
                child: CustomSwitch(
                  value: value,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (tooltip != null) pill = Tooltip(message: tooltip!, child: pill);
    return pill;
  }
}
