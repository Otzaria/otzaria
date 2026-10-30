import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';

/// סיכום החיפוש: ערך הגימטריה, מספר התוצאות ופרמטרי החיפוש הפעילים.
class GematriaStatusBar extends StatelessWidget {
  final int value;
  final String resultsText;
  final List<String> params;

  const GematriaStatusBar({
    super.key,
    required this.value,
    required this.resultsText,
    required this.params,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMD,
        AppTokens.spaceMD,
        AppTokens.spaceMD,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceMD,
                    vertical: AppTokens.spaceSM,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ערך גימטריה',
                        style: TextStyle(
                          fontSize: AppTokens.fontMD,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSM),
                      Text(
                        '$value',
                        style: TextStyle(
                          fontSize: AppTokens.fontXL,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceMD),
              Expanded(
                child: Text(
                  resultsText,
                  style: TextStyle(
                    fontSize: AppTokens.fontMD,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (params.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceXS,
              children: [
                for (final label in params) MetaChip(label: label),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
