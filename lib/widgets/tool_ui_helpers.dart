import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// צבע רקע כרטיסי תוצאות בכלי האפליקציה — תואם לסגנון SettingsCard.
Color toolCardColor(BuildContext context) {
  return AppSurfaces.card(context);
}

/// עוטף תוכן כלי עם אפשרות למרכוז אופקי והגבלת רוחב.
class ToolPanelWrapper extends StatelessWidget {
  final Widget child;
  final bool centerContent;
  final bool paintBackground;

  const ToolPanelWrapper({
    super.key,
    required this.child,
    this.centerContent = true,
    this.paintBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    if (centerContent) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LayoutConstraints.panelContentMaxWidth,
          ),
          child: child,
        ),
      );
    }

    if (!paintBackground) {
      return content;
    }

    return ColoredBox(
      color: AppSurfaces.panelBackground(context),
      child: content,
    );
  }
}
