import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// שורת סיכום מעל רשימת תוצאות בכלי: מספר התוצאות ותוספת אופציונלית.
class ToolResultsHeader extends StatelessWidget {
  final String label;
  final Widget? child;

  const ToolResultsHeader({super.key, required this.label, this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMD,
        AppTokens.spaceSM,
        AppTokens.spaceMD,
        0,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTokens.fontSM,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (child != null) ...[
              const SizedBox(height: AppTokens.spaceSM),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}
