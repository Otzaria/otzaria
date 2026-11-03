// lib/widgets/misc/tool_ui_helpers.dart
//
// עזרי UI משותפים למסכי כלים.

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

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

/// גולל את [controller] בעמוד אחד (85% מגובה התצוגה) קדימה או אחורה.
void scrollToolContentByPage(
  ScrollController controller, {
  required bool forward,
}) {
  if (!controller.hasClients) return;
  final position = controller.position;
  final delta = (position.viewportDimension * 0.85) * (forward ? 1 : -1);
  final target = (position.pixels + delta).clamp(
    0.0,
    position.maxScrollExtent,
  );
  AppMotion.scrollPosition(
    position,
    target,
    const Duration(milliseconds: 180),
    curve: Curves.easeOut,
  );
}
