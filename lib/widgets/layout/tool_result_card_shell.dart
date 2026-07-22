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
    final borderColor = isFocused
        ? cs.primary.withValues(alpha: 0.75)
        : cs.outlineVariant.withValues(alpha: 0.22);
    final borderWidth = isFocused ? 1.5 : 1.0;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: borderColor, width: borderWidth),
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
