import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// פאנל צף כללי בסגנון M3.
class AppFloatingPanel extends StatelessWidget {
  final Widget child;

  const AppFloatingPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: AppTokens.elevation2,
      borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
