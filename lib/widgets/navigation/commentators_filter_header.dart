import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class CommentatorsFilterHeader extends StatelessWidget {
  final VoidCallback onBack;
  final String title;

  const CommentatorsFilterHeader({
    super.key,
    required this.onBack,
    this.title = 'בחירת מפרשים',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(FluentIcons.arrow_left_24_regular),
            tooltip: 'חזרה למפרשים',
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}
