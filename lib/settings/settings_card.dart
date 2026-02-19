import 'package:flutter/material.dart';

/// כרטיס הגדרות מעוצב בסגנון Material 3 / Google Account
class SettingsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const SettingsCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת ותת-כותרת מעל הכרטיס
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 16, top: 24, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        // הכרטיס הלבן המכיל את ההגדרות
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: _buildChildrenWithDividers(),
          ),
        ),
      ],
    );
  }

  /// הוספת קו מפריד בין כל שני פריטים
  List<Widget> _buildChildrenWithDividers() {
    if (children.isEmpty) {
      return [];
    }
    return List.generate(children.length * 2 - 1, (i) {
      if (i.isEven) {
        return children[i ~/ 2];
      }
      return const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
      );
    });
  }
}