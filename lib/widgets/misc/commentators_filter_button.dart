import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

class CommentatorsFilterButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;
  final double? iconSize;

  const CommentatorsFilterButton({
    super.key,
    required this.isActive,
    required this.onPressed,
    this.padding = const EdgeInsets.all(8.0),
    this.constraints,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        OtzariaIcons.apps_list_24_regular,
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        size: iconSize,
      ),
      tooltip: 'בחירת מפרשים',
      padding: padding,
      constraints: constraints,
      onPressed: onPressed,
    );
  }
}
