// lib/widgets/layout/floating_panel.dart

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// פאנל צף: רמת הגבהה 3 ([AppTokens.elevation2]) עם הצל של [AppShadows]
/// ומסגרת `outlineVariant` (DD-12).
class FloatingPanel extends StatelessWidget {
  /// התוכן בתוך הפאנל
  final Widget child;

  /// ריפוד פנימי אופציונלי
  final EdgeInsetsGeometry? padding;

  /// דריסת צבע הפאנל (אופציונלי)
  final Color? color;

  const FloatingPanel({
    super.key,
    required this.child,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final panelColor = color ?? AppSurfaces.panelBackground(context);

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    return Material(
      color: panelColor,
      elevation: AppTokens.elevation2,
      shadowColor: AppShadows.color(cs),
      surfaceTintColor: Colors.transparent,
      // "לבן": המסגרת בקו האזורים (#2850).
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
        side: BorderSide(
          color: AppSurfaces.regionBorder(context) ?? cs.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}
