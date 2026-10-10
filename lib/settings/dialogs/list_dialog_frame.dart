import 'package:flutter/material.dart';

/// מסגרת משותפת לדיאלוגי רשימות הספרים: רוחב וגובה מוגבלים, ושורת כותרת
/// עם אייקון, שם ומונה. [children] נוספים מתחת לכותרת.
class ListDialogFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final String counter;
  final double maxWidth;
  final double heightFactor;
  final List<Widget> children;

  const ListDialogFrame({
    super.key,
    required this.icon,
    required this.title,
    required this.counter,
    this.maxWidth = 720,
    this.heightFactor = 0.85,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final width = media.size.width * 0.9;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width > maxWidth ? maxWidth : width,
          maxHeight: media.size.height * heightFactor,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleLarge),
                  ),
                  Text(
                    counter,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
