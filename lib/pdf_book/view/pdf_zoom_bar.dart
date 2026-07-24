import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class PdfZoomBar extends StatelessWidget {
  final double currentZoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;

  const PdfZoomBar({
    super.key,
    required this.currentZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
  });

  @override
  Widget build(BuildContext context) {
    final zoomPercentage = (currentZoom * 100).round();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      elevation: 4,
      borderRadius: AppTokens.borderRadiusAll,
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: AppTokens.borderRadiusAll,
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // כפתור איפוס
            TextButton(
              onPressed: onResetZoom,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(60, 36),
              ),
              child: const Text(
                'אפס',
                style: TextStyle(fontSize: 14),
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // כפתור הגדלה
            IconButton(
              icon: const Icon(FluentIcons.add_24_regular, size: 20),
              onPressed: onZoomIn,
              tooltip: 'הגדל את התצוגה',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            // כפתור הקטנה
            IconButton(
              icon: const Icon(FluentIcons.subtract_24_regular, size: 20),
              onPressed: onZoomOut,
              tooltip: 'הקטן את התצוגה',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            const SizedBox(width: 12),
            // תצוגת אחוזים
            SizedBox(
              width: 50,
              child: Text(
                '$zoomPercentage%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
