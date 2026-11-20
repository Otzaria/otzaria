// lib/widgets/controls/contained_tooltip.dart
// Tooltip עם צומת סמנטיקה משלו, לעטיפת רכיב שאין לו פרמטר tooltip.

import 'package:flutter/material.dart';

/// [Tooltip] בתוך מכולת סמנטיקה משלו. לכפתור שיש לו פרמטר `tooltip`
/// (כמו IconButton) עדיף להשתמש בפרמטר.
class ContainedTooltip extends StatelessWidget {
  final String message;
  final Widget child;

  const ContainedTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;
    // בלי מכולה, עוגן הבלון מתמזג לצומת שמעליו; אם שם כבר יש עוגן overlay
    // אחר (OverlayPortal, MenuAnchor) הוא נשמט והבלון נשלח בלי אב — Windows קורס.
    return Semantics(
      container: true,
      child: Tooltip(message: message, child: child),
    );
  }
}
