// לתחזוקת כרטיסי טיפים חיים ראו: docs/guided_tour_developer_guide.md

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

class LiveTipCard extends StatelessWidget {
  /// הטקסט העברי, שהוא גם מפתח התרגום.
  final String title;
  final String description;
  final VoidCallback onDismiss;

  const LiveTipCard({
    super.key,
    required this.title,
    required this.description,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      elevation: 10,
      borderRadius: AppTokens.borderRadiusAll,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppTokens.borderRadiusAll,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.settingsText(title),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  tooltip: context.settingsText('סגור'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.settingsText(description),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionButton.neutral(
                icon: FluentIcons.checkmark_24_regular,
                text: context.settingsText('הבנתי'),
                onPressed: onDismiss,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
