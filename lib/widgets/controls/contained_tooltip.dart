// lib/widgets/controls/contained_tooltip.dart
// Tooltip עם צומת סמנטיקה משלו, לעטיפת רכיב שאין לו פרמטר tooltip.

import 'package:flutter/material.dart';

/// האם [tooltip] רק חוזר על [label] הגלוי על הפקד: אותו טקסט, עד כדי רווחים,
/// סימני פיסוק וניקוד. טולטיפ כזה מיותר — הוא לא מוסיף מידע על מה שכבר
/// כתוב. טולטיפ ריק או חסר נחשב גם הוא כחוזר (אין מה להציג).
bool tooltipRepeatsLabel(String? tooltip, String? label) {
  if (tooltip == null || tooltip.trim().isEmpty) return true;
  if (label == null) return false;
  return _comparable(tooltip) == _comparable(label);
}

final _nonWordChars = RegExp(r'[^\p{L}\p{N}]', unicode: true);

String _comparable(String text) => text.replaceAll(_nonWordChars, '');

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
