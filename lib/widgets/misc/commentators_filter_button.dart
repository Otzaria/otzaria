import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class CommentatorsFilterButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;
  final double? iconSize;
  final double inactiveAlpha;

  const CommentatorsFilterButton({
    super.key,
    required this.isActive,
    required this.onPressed,
    this.padding = const EdgeInsets.all(8.0),
    this.constraints,
    this.iconSize,
    this.inactiveAlpha = 0.6,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        FluentIcons.apps_list_24_regular,
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: inactiveAlpha),
        size: iconSize,
      ),
      tooltip: 'בחירת מפרשים',
      padding: padding,
      constraints: constraints,
      onPressed: onPressed,
    );
  }
}
