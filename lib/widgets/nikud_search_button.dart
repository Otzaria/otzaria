import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// כפתור לחיפוש עם ניקוד - מופיע רק כאשר הטקסט מכיל ניקוד
class NikudSearchButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isActive;

  const NikudSearchButton({
    super.key,
    required this.onPressed,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'חפש עם ניקוד',
      child: IconButton(
        icon: Icon(
          isActive
              ? FluentIcons.text_font_24_filled
              : FluentIcons.text_font_24_regular,
          size: 20,
        ),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: isActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(32, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
