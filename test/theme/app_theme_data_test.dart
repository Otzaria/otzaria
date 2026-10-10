import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// ניגודיות WCAG בין שני צבעים (יחס בהירות).
double _contrastRatio(Color a, Color b) {
  double linear(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final la = 0.2126 * linear(a.r) + 0.7152 * linear(a.g) + 0.0722 * linear(a.b);
  final lb = 0.2126 * linear(b.r) + 0.7152 * linear(b.g) + 0.0722 * linear(b.b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('בועות מידע משתמשות בצבעי הנושא ב-$brightness', () {
      final colorScheme = AppThemeData.createColorScheme(
        Colors.deepPurple,
        brightness,
      );
      final theme = brightness == Brightness.light
          ? AppThemeData.light(colorScheme, compactMenuMode: false)
          : AppThemeData.dark(colorScheme, compactMenuMode: false);
      final decoration = theme.tooltipTheme.decoration! as BoxDecoration;

      expect(decoration.color, colorScheme.surfaceContainerHigh);
      expect(theme.tooltipTheme.textStyle?.color, colorScheme.onSurface);
    });
  }

  group('ערכת צבע "לבן"', () {
    test('במצב בהיר רקע מסך העיון לבן מוחלט', () {
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.white,
        Brightness.light,
      );
      expect(cs.surface, Colors.white);
    });

    test('סולם המשטחים בהיר מזה של "אפור" ושומר על סדר עולה (issue #1221)', () {
      final white = AppThemeData.createColorScheme(
        AppSeedColors.white,
        Brightness.light,
      );
      final grey = AppThemeData.createColorScheme(
        AppSeedColors.grey,
        Brightness.light,
      );

      final whiteRamp = [
        white.surfaceContainerLow,
        white.surfaceContainer,
        white.surfaceContainerHigh,
        white.surfaceContainerHighest,
      ];
      final greyRamp = [
        grey.surfaceContainerLow,
        grey.surfaceContainer,
        grey.surfaceContainerHigh,
        grey.surfaceContainerHighest,
      ];

      for (var i = 0; i < whiteRamp.length; i++) {
        expect(whiteRamp[i].r, greaterThan(greyRamp[i].r), reason: 'שלב $i');
      }
      // סדר יורד בבהירות — ההיררכיה בין שכבות המשטח נשמרת.
      for (var i = 1; i < whiteRamp.length; i++) {
        expect(whiteRamp[i].r, lessThan(whiteRamp[i - 1].r), reason: 'שלב $i');
      }
      expect(white.surfaceContainerLow.r, lessThan(white.surface.r));
    });

    test('במצב כהה הרקע נשאר כהה', () {
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.white,
        Brightness.dark,
      );
      expect(cs.surface, isNot(Colors.white));
    });

    test('שאר צבעי הבסיס אינם מקבלים surface לבן', () {
      for (final option in AppSeedColors.options) {
        if (option.color.toARGB32() == AppSeedColors.white.toARGB32()) {
          continue;
        }
        final cs = AppThemeData.createColorScheme(
          option.color,
          Brightness.light,
        );
        expect(cs.surface, isNot(Colors.white), reason: option.name);
      }
    });

    test('primaryContainer/onPrimaryContainer תמיד קריאים (ניגודיות WCAG)', () {
      // רכיבים נבחרים משתמשים בזוג צבעים זה.
      for (final option in AppSeedColors.options) {
        for (final brightness in Brightness.values) {
          final cs = AppThemeData.createColorScheme(option.color, brightness);
          final ratio = _contrastRatio(
            cs.primaryContainer,
            cs.onPrimaryContainer,
          );
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${option.name} $brightness: primaryContainer '
                '${cs.primaryContainer} מול onPrimaryContainer '
                '${cs.onPrimaryContainer} — ניגודיות $ratio',
          );
        }
      }
    });

    test('הזיווג primaryContainer/onSurface כהה-על-כהה אסור בערכת "לבן"', () {
      // בערכת "לבן" הבהירה onSurface אינו צבע קדמי מתאים לרקע זה.
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.white,
        Brightness.light,
      );
      final ratio = _contrastRatio(cs.primaryContainer, cs.onSurface);
      expect(
        ratio,
        lessThan(3.0),
        reason:
            'primaryContainer ${cs.primaryContainer} עם onSurface '
            '${cs.onSurface} חייב להישאר בלתי-קריא כדי למנוע שימוש בטעות',
      );
    });

    test('secondaryContainer עם onSurface/onSurfaceVariant תמיד קריא', () {
      // רכיבים על secondaryContainer משתמשים בזוגות צבעים אלה.
      for (final option in AppSeedColors.options) {
        for (final brightness in Brightness.values) {
          final cs = AppThemeData.createColorScheme(option.color, brightness);
          for (final pair in [
            (cs.secondaryContainer, cs.onSurface),
            (cs.secondaryContainer, cs.onSurfaceVariant),
          ]) {
            final ratio = _contrastRatio(pair.$1, pair.$2);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '${option.name} $brightness: secondaryContainer '
                  '${pair.$1} מול ${pair.$2} — ניגודיות $ratio',
            );
          }
        }
      }
    });
  });

  test('"פרגמנט" ו"חום זהבהב" נראים כשמם — בעיגול ובערכה (issue #2056)', () {
    double hue(Color c) => HSLColor.fromColor(c).hue;
    final golden = AppThemeData.createColorScheme(
      AppSeedColors.darkBrown,
      Brightness.light,
    );
    expect(AppSeedColors.swatchOf(AppSeedColors.darkBrown), golden.primary);

    final parchment = AppThemeData.createColorScheme(
      AppSeedColors.parchment,
      Brightness.light,
    );
    final brown = AppThemeData.createColorScheme(
      AppSeedColors.brown,
      Brightness.light,
    );
    expect(parchment.surface, isNot(brown.surface));
    for (final c in [
      parchment.surface,
      AppSeedColors.swatchOf(AppSeedColors.parchment),
    ]) {
      expect(hue(c), inInclusiveRange(30, 50), reason: '$c');
      expect(HSLColor.fromColor(c).saturation, greaterThan(0.3), reason: '$c');
    }
  });
}
