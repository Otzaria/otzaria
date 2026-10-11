import 'package:flutter/material.dart';

/// התיאור המורחב להצגה, או null כשהוא ריק או זהה לתיאור הקצר.
String? distinctFullDescription(String? short, String? full) {
  final trimmed = full?.trim() ?? '';
  return trimmed.isEmpty || trimmed == short?.trim() ? null : full;
}

/// מקטע תווית־וערך אחיד לדיאלוגי מידע.
class DetailsInfoSection extends StatelessWidget {
  const DetailsInfoSection({
    super.key,
    required this.title,
    required this.value,
    this.icon,
    this.valueDirection,
  });

  /// התווית המודגשת שמופיעה לפני הערך.
  final String title;

  /// הערך המלא. הבחירה וההעתקה מסופקות ע"י AppSelectionArea שעוטף את הדיאלוג.
  final String value;

  /// אייקון שמזהה את סוג הפרט, מוצג לפני התווית.
  final IconData? icon;

  /// כיוון הערך, כאשר הוא שונה מכיוון הממשק.
  final TextDirection? valueDirection;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon == null)
            titleText
          else
            Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                titleText,
              ],
            ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
            textDirection: valueDirection,
          ),
        ],
      ),
    );
  }
}
