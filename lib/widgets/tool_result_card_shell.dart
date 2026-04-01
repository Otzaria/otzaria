import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

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
      child: Material(
        color: AppSurfaces.card(context),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          hoverColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          focusColor: Colors.transparent,
          child: SelectionArea(
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
