import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';

/// מעטפת עיצובית לחלוניות הצד במסכי הקריאה.
///
/// מוסיפה מראה צף עם פינות מעוגלות, צל ורווח קטן מהקצה החיצוני,
/// כדי להבדיל את החלונית מתוכן הקריאה עצמו.
class ReaderSidePanelShell extends StatelessWidget {
  final Widget child;
  final AlignmentDirectional alignment;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  const ReaderSidePanelShell({
    super.key,
    required this.child,
    required this.alignment,
    this.color,
    this.margin,
  });

  EdgeInsets _resolveMargin(BuildContext context) {
    final resolvedMargin = margin?.resolve(Directionality.of(context));
    if (resolvedMargin != null) {
      return resolvedMargin;
    }

    final resolvedAlignment = alignment.resolve(Directionality.of(context));
    final isOnRightSide = resolvedAlignment.x > 0;

    return EdgeInsets.only(
      top: 12,
      bottom: 10,
      left: isOnRightSide ? 0 : 10,
      right: isOnRightSide ? 10 : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _resolveMargin(context),
      child: FloatingPanel(
        color: color ?? AppSurfaces.solidPanelBackground(context),
        elevation: 8,
        shadowColor: Theme.of(
          context,
        ).colorScheme.shadow.withValues(alpha: 0.22),
        child: child,
      ),
    );
  }
}
