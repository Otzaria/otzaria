import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מספר התוצאה בתחילת שורת הכותרת של הכרטיס. קטן מספיק כדי לשבת בגובה
/// השורה, בלי לשמור לעצמו עמודה לכל גובה הכרטיס.
class SearchResultRankBadge extends StatelessWidget {
  final int rank;

  const SearchResultRankBadge({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(
        minWidth: AppTokens.iconLG,
        minHeight: AppTokens.iconLG,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceXS),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          '$rank',
          style: theme.textTheme.labelLarge?.copyWith(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
