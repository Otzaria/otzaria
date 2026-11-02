import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_motion.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// כפתור pin עם אנימציה — מסתובב 45° ומחליף אייקון ל-filled כשנעוץ.
class AnimatedPinButton extends StatelessWidget {
  final bool isPinned;
  final VoidCallback? onPressed;
  final String? tooltip;

  const AnimatedPinButton({
    super.key,
    required this.isPinned,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      isSelected: isPinned,
      onPressed: onPressed,
      color: isPinned ? Theme.of(context).colorScheme.primary : null,
      icon: AnimatedRotation(
        turns: isPinned ? -0.125 : 0.0,
        duration: AppMotion.duration(context, AppTokens.animPanelOpacity),
        child: Icon(
          isPinned ? FluentIcons.pin_24_filled : FluentIcons.pin_24_regular,
        ),
      ),
    );
  }
}
