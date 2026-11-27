import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';

double _contrast(Color a, Color b) {
  final l = [a.computeLuminance(), b.computeLuminance()];
  return (l.reduce(math.max) + .05) / (l.reduce(math.min) + .05);
}

/// #3127 (DD-17): רקע מילות החיפוש שומר על האדום קריא בכל ערכה, בהיר וכהה,
/// ונבדל מרקע התוצאה הנוכחית ומהסימון.
void main() {
  for (final brightness in Brightness.values) {
    for (final seed in AppSeedColors.options) {
      test('רקע מילות החיפוש: ${seed.name}/${brightness.name}', () {
        final cs = AppThemeData.createColorScheme(seed.color, brightness);
        final variant = AppThemeVariant.ofSeed(seed.color);
        final theme = brightness == Brightness.dark
            ? AppThemeData.dark(cs, compactMenuMode: false, variant: variant)
            : AppThemeData.light(cs, compactMenuMode: false, variant: variant);
        final scheme = theme.colorScheme;
        final background = AppSurfaces.searchHitBackground(scheme);
        expect(background.a, closeTo(0.8, 0.01));
        expect(
          background,
          isNot(AppSurfaces.searchHitCurrentBackground(scheme)),
        );
        expect(background, isNot(AppSurfaces.permanentMark(scheme)));
        for (final surface in [
          scheme.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          theme.scaffoldBackgroundColor,
        ]) {
          expect(
            _contrast(
              AppSurfaces.searchHit(scheme),
              Color.alphaBlend(background, surface),
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
      });
    }
  }
}
