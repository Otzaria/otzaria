import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מספר התוצאה בראש הכרטיס.
class SearchResultRankBadge extends StatelessWidget {
  final int rank;

  const SearchResultRankBadge({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          '$rank',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: AppTokens.fontLG,
          ),
        ),
      ),
    );
  }
}
