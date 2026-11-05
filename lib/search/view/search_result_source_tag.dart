import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Text(
        label,
        // שם המדור של ספק חיצוני מגיע מהתוסף (עד 120 תווים) — התגית נחתכת
        // ולא דוחקת את שאר השורה.
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onTertiaryContainer,
        ),
      ),
    );
  }
}
