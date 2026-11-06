import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

/// מציג פירוש של מילה במילון הארמי-עברי בצורה מונגשת ומובנית.
class AramaicDictionaryEntryView extends StatelessWidget {
  const AramaicDictionaryEntryView({
    super.key,
    required this.definition,
    this.skipRepeatedMeanings = false,
  });

  final String definition;

  /// מדלג על פירוש שכל חלקיו כבר הופיעו קודם (לערך שמוזג מכמה מילונים).
  final bool skipRepeatedMeanings;

  @override
  Widget build(BuildContext context) {
    final parsed = AramaicDictionaryEntryPresentation.parse(definition);
    final meanings =
        (skipRepeatedMeanings ? parsed.withoutRepeatedMeanings() : parsed)
            .meanings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < meanings.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _MeaningView(meaning: meanings[index], index: index),
        ],
      ],
    );
  }
}

class _MeaningView extends StatelessWidget {
  const _MeaningView({required this.meaning, required this.index});

  final ParsedAramaicMeaning meaning;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          margin: const EdgeInsetsDirectional.only(top: 2, end: 10),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Text(
            '${index + 1}',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (meaning.expression != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: Text(
                    meaning.expression!,
                    style: textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (meaning.mainText.isNotEmpty)
                Text(
                  // הטקסט כבר מודגש; הסימון עצמו לא מוצג.
                  AramaicDictionaryEntryPresentation.stripBold(
                    meaning.mainText,
                  ),
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              if (meaning.expansion != null) ...[
                const SizedBox(height: 4),
                Text(
                  meaning.expansion!,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
