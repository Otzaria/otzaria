// lib/tools/aramaic_dictionary/widgets/aramaic_result_card.dart
//
// כרטיס תוצאת מילון ארמי-עברי.
// הוצא מ-aramaic_dictionary_screen.dart לרכיב עצמאי.

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

class AramaicResultCard extends StatelessWidget {
  final String aramaic;
  final String hebrew;
  final bool isHebrewToAramaic;

  const AramaicResultCard({
    super.key,
    required this.aramaic,
    required this.hebrew,
    required this.isHebrewToAramaic,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sourceLabel = isHebrewToAramaic ? 'עברית:' : 'ארמית:';
    final targetLabel = isHebrewToAramaic ? 'ארמית:' : 'עברית:';
    final sourceWord = isHebrewToAramaic ? hebrew : aramaic;
    final targetWord = isHebrewToAramaic ? aramaic : hebrew;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceMD - 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Row(
          children: [
            Expanded(child: _WordColumn(label: sourceLabel, word: sourceWord)),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMD),
              child: Icon(
                isHebrewToAramaic
                    ? FluentIcons.arrow_left_24_filled
                    : FluentIcons.arrow_right_24_filled,
                color: cs.primary,
              ),
            ),
            Expanded(child: _WordColumn(label: targetLabel, word: targetWord)),
          ],
        ),
      ),
    );
  }
}

class _WordColumn extends StatelessWidget {
  final String label;
  final String word;
  const _WordColumn({required this.label, required this.word});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.spaceXS),
        Text(
          word,
          style: const TextStyle(
            fontSize: AppTokens.fontXL,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }
}
