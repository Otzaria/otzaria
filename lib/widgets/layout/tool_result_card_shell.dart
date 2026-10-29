import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מעטפת משותפת לכרטיסי תוצאה במסכי כלים.
class ToolResultCardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// ריפוד פנימי; ברירת המחדל מתאימה לכרטיס של שורה אחת.
  final EdgeInsetsGeometry padding;

  /// המרווח מתחת לכרטיס.
  final double bottomGap;

  /// מסגרת דקה סביב הכרטיס, כשצבעו קרוב לרקע שמאחוריו.
  final bool outlined;

  const ToolResultCardShell({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTokens.spaceMD,
      vertical: AppTokens.spaceSM,
    ),
    this.bottomGap = 4,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Material(
        color: AppSurfaces.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: outlined
              ? BorderSide(color: Theme.of(context).colorScheme.outlineVariant)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        // The tap target sits inside the selection area: a tap on the text
        // would otherwise go to the selection and never reach the card.
        child: AppSelectionArea(
          child: InkWell(
            onTap: onTap,
            borderRadius: AppTokens.borderRadiusAll,
            focusColor: Colors.transparent,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
