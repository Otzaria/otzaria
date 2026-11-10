import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// "מה אפשר לעשות": תיבת הצעדים במסכי השגיאה של התוספים, מתחת לכותרת של
/// [OtzariaErrorState]. ברוחב עד 540, כדי שהשורות לא יימתחו.
class PluginAdviceBox extends StatelessWidget {
  const PluginAdviceBox({super.key, required this.text, this.header});

  final String text;

  /// תוכן נוסף מעל התיבה, למשל הנתיב החסום.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: AppTokens.spaceMD),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('מה אפשר לעשות:', style: tt.titleSmall),
                  const SizedBox(height: AppTokens.spaceSM),
                  Text(text, style: tt.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
