// lib/widgets/misc/tool_ui_helpers.dart
//
// עזרי UI משותפים למסכי כלים.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
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

/// מפעיל קיצור "חפש בחלון" לפי ההגדרות. נקרא מתוך build, כדי שהמסך ייבנה
/// מחדש כשהמשתמש משנה את הקיצור.
ShortcutActivator currentWindowSearchActivator(
  BuildContext context, {
  bool mapCtrlToMeta = true,
}) {
  const key = ShortcutValidator.currentWindowSearchKey;
  final shortcut = context.select(
    (SettingsBloc bloc) =>
        bloc.state.shortcuts[key] ??
        ShortcutValidator.defaultShortcuts[key] ??
        'ctrl+f',
  );
  return ShortcutHelper.activatorFromShortcut(
        shortcut,
        mapCtrlToMeta: mapCtrlToMeta,
      ) ??
      const SingleActivator(LogicalKeyboardKey.keyF, control: true);
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
  controller.animateTo(
    target,
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOut,
  );
}
