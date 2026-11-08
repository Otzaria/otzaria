import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// שורת סיכום מעל רשימת תוצאות בכלי: מספר התוצאות, ולפניו באותה שורה
/// [leading] אופציונלי (למשל ערך החיפוש). [child] מוצג מתחת לשורה.
class ToolResultsHeader extends StatelessWidget {
  final String label;
  final Widget? leading;
  final Widget? child;

  const ToolResultsHeader({
    super.key,
    required this.label,
    this.leading,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Text(
      label,
      style: TextStyle(fontSize: AppTokens.fontSM, color: cs.onSurfaceVariant),
    );
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
            if (leading == null)
              text
            else
              Row(
                children: [
                  leading!,
                  const SizedBox(width: AppTokens.spaceMD),
                  Expanded(child: text),
                ],
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
