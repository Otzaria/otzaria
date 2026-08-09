import 'package:flutter/material.dart';

/// תווית קטנה מעל שדה קלט, במקום תווית צפה בתוכו.
///
/// שדה מלא ללא מסגרת שמכיל גם כפתורים (מונה, ניקוי, הוספה) — תווית צפה
/// בתוכו דוחקת את התוכן והכפתורים מהמרכז.
class LabeledInput extends StatelessWidget {
  const LabeledInput({
    super.key,
    required this.label,
    required this.child,
    this.width,
  });

  final String label;
  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        child,
      ],
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}
