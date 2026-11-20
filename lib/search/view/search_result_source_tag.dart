import 'package:flutter/material.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';

/// תגית המקור שעל כרטיס תוצאת חיפוש — 'אוצריא' לתוצאות המנוע המובנה, ושם
/// המדור (`resultsTitle`) לתוצאות של ספק חיצוני מתוסף.
///
/// שני סוגי התוצאות מוצגים באותה רשימה, ולכן שניהם נושאים תגית באותו עיצוב
/// ובאותו מקום — בקצה השורה, לצד כפתור ההעתקה — כדי שאפשר יהיה להבחין
/// ביניהם במבט אחד.
class SearchResultSourceTag extends StatelessWidget {
  final String label;

  const SearchResultSourceTag({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    // שם המדור של ספק חיצוני מגיע מהתוסף (עד 120 תווים) — ‏[MetaChip] חותך
    // אותו בשורה אחת ולא דוחק את שאר השורה.
    return MetaChip(
      label: label,
      tone: MetaChipTone.tertiary,
      size: MetaChipSize.small,
    );
  }
}
