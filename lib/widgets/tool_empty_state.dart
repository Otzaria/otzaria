import 'package:flutter/material.dart';
import 'package:otzaria/localization/app_localizations.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מצב ריק סטנדרטי למסכי כלים.
class ToolEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subtitle;

  const ToolEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: cs.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              context.trLiteral(message),
              style: TextStyle(
                fontSize: AppTokens.fontXL,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
              textDirection:
                  context.isEnglishMode ? TextDirection.ltr : TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                context.trLiteral(subtitle!),
                textDirection: context.isEnglishMode
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
