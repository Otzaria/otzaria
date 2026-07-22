import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מעטפת משותפת לכרטיסי תוצאה במסכי כלים.
class ToolResultCardShell extends StatelessWidget {
  final Widget child;
  final bool isFocused;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const ToolResultCardShell({
    super.key,
    required this.child,
    this.isFocused = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTokens.spaceMD,
      vertical: AppTokens.spaceSM,
    ),
    this.margin = const EdgeInsets.only(bottom: 4),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusAll,
        border: isFocused
            ? Border.all(color: cs.primary.withValues(alpha: 0.75), width: 1.5)
            : null,
      ),
      child: Material(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.borderRadiusAll,
          focusColor: Colors.transparent,
          child: AppSelectionArea(
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
