import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מצב ריק סטנדרטי למסכי כלים.
class ToolEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const ToolEmptyState({
    super.key,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
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
            message,
            style: TextStyle(
              fontSize: AppTokens.fontXL,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
