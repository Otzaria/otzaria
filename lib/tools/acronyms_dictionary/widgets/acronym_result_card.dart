// lib/tools/acronyms_dictionary/widgets/acronym_result_card.dart
//
// כרטיס תוצאת מילון ראשי תיבות.
// הוצא מ-acronyms_dictionary_screen.dart לרכיב עצמאי.

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

class AcronymResultCard extends StatelessWidget {
  final String acronym;
  final List<String> meanings;

  const AcronymResultCard({
    super.key,
    required this.acronym,
    required this.meanings,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
            Expanded(
              child: _WordColumn(
                label: 'ראשי תיבות:',
                child: Text(
                  acronym,
                  style: const TextStyle(
                    fontSize: AppTokens.fontXL,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTokens.spaceMD),
              child: Icon(Icons.arrow_back, color: cs.primary),
            ),
            Expanded(
              child: _WordColumn(
                label: 'פירוש:',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: meanings.asMap().entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceXS),
                      child: Text(
                        meanings.length > 1
                            ? '${e.key + 1}. ${e.value}'
                            : e.value,
                        style: const TextStyle(
                          fontSize: AppTokens.fontXL,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordColumn extends StatelessWidget {
  final String label;
  final Widget child;
  const _WordColumn({required this.label, required this.child});

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
        child,
      ],
    );
  }
}
