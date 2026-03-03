import 'package:flutter/material.dart';

/// כרטיס הגדרות מעוצב בסגנון Material 3 / Google Account
class SettingsCard extends StatelessWidget {
  final dynamic title; // יכול להיות String או Widget
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
    final isDark = theme.brightness == Brightness.dark;

    // [תיקון מצב כהה] בכהה: surfaceContainer (אפור כהה מעט בולט מהרקע השחור)
    //                 בבהיר: surface (לבן — ברירת המחדל הישנה)
    final cardColor =
        isDark ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת ותת-כותרת מעל הכרטיס
        Padding(
          padding:
              const EdgeInsets.only(right: 16, left: 16, top: 24, bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title is String
                  ? Text(
                      title as String,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : DefaultTextStyle(
                      style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ) ??
                          const TextStyle(),
                      child: title as Widget,
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
        // הכרטיס המכיל את ההגדרות
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: cardColor,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            side: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            children: _buildChildrenWithDividers(context),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildChildrenWithDividers(BuildContext context) {
    return [
      for (int i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1)
          Divider(
            height: 1,
            thickness: 1.5,
            indent: 0,
            endIndent: 0,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
      ],
    ];
  }
}
