import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';

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

  for (final brightness in Brightness.values) {
    test('כל סוגי התפריטים על אותו רקע ב-$brightness', () {
      final cs = AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        brightness,
      );
      final theme = brightness == Brightness.light
          ? AppThemeData.light(cs, compactMenuMode: false)
          : AppThemeData.dark(cs, compactMenuMode: false);
      Color? background(MenuStyle? style) =>
          style?.backgroundColor?.resolve(const <WidgetState>{});

      expect(theme.popupMenuTheme.color, background(theme.menuTheme.style));
      expect(
        theme.popupMenuTheme.color,
        background(theme.dropdownMenuTheme.menuStyle),
      );
    });
  }

  test('בוחרי תאריך מצוירים באותו רדיוס כמו שאר הדיאלוגים', () {
    final theme = AppThemeData.light(
      AppThemeData.createColorScheme(Colors.deepPurple, Brightness.light),
      compactMenuMode: false,
    );

    expect(theme.datePickerTheme.shape, AppTokens.roundedShape);
    expect(theme.datePickerTheme.rangePickerShape, AppTokens.roundedShape);
  });

  // q12 Q8, ss6: הסרגל התחתון בטלפון 64 ולא 80, ותווית לכל יעד.
  testWidgets('סרגל הניווט התחתון בגובה 64, עם תווית לכל יעד', (
    tester,
  ) async {
    final theme = AppThemeData.light(
      AppThemeData.createColorScheme(Colors.deepPurple, Brightness.light),
      compactMenuMode: true,
    );
    expect(
      theme.navigationBarTheme.height,
      LayoutConstraints.bottomNavigationBarHeight,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.abc), label: 'ספרייה'),
              NavigationDestination(icon: Icon(Icons.abc), label: 'עיון'),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(NavigationBar)).height,
      LayoutConstraints.bottomNavigationBarHeight,
    );
    // תווית גם ליעד שלא נבחר.
    expect(find.text('עיון').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('הערכה נגזרת מהזרע ונישאת ב-ThemeData', () {
    expect(AppThemeVariant.ofSeed(AppSeedColors.white), AppThemeVariant.white);
    expect(
      AppThemeVariant.ofSeed(AppSeedColors.parchment),
      AppThemeVariant.parchment,
    );
    expect(
      AppThemeVariant.ofSeed(AppSeedColors.grey),
      AppThemeVariant.standard,
    );

    final cs = AppThemeData.createColorScheme(
      AppSeedColors.white,
      Brightness.light,
    );
    expect(
      AppThemeVariantTheme.of(
        AppThemeData.light(
          cs,
          compactMenuMode: false,
          variant: AppThemeVariant.white,
        ),
      ),
      AppThemeVariant.white,
    );
    expect(
      AppThemeVariantTheme.of(AppThemeData.light(cs, compactMenuMode: false)),
      AppThemeVariant.standard,
    );
  });

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

    test(
      'הסרגלים, החלוניות והדיאלוגים לבנים כמעט, ועדיין נבדלים מהקריאה (#2850)',
      () {
        final cs = AppThemeData.createColorScheme(
          AppSeedColors.white,
          Brightness.light,
        );
        final s = AppSurfaceColors.fromScheme(cs);
        int level(Color c) => (c.r * 255).round();
        // סרגל עליון, חלונית הניווט, דיאלוג ותפריט (surfaceContainerHigh).
        for (final (name, color) in [
          ('topBar', s.topBarBackground),
          ('navPanel', s.navPanelBackground),
          ('surfaceContainerHigh', cs.surfaceContainerHigh),
          ('panel', s.panelBackground),
        ]) {
          expect(level(color), greaterThanOrEqualTo(0xF6), reason: name);
          expect(level(color), lessThan(0xFF), reason: '$name נבדל מהקריאה');
        }
        expect(level(cs.surfaceContainerHighest), greaterThanOrEqualTo(0xF0));
        expect(s.readerBackground, Colors.white);
        // נייטרלי: בלי גוון.
        for (final c in [s.topBarBackground, s.panelBackground]) {
          expect(c.r, c.g);
          expect(c.g, c.b);
        }
      },
    );

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

    test('קישורי ספר מובחנים מהטקסט בערכות נייטרליות (#2589)', () {
      for (final seed in [AppSeedColors.white, AppSeedColors.grey]) {
        for (final brightness in Brightness.values) {
          final cs = AppThemeData.createColorScheme(seed, brightness);
          final name = '${AppSeedColors.nameOf(seed)} $brightness';
          final link = AppSurfaces.readerLink(cs);
          expect(
            _contrastRatio(link, cs.onSurface),
            greaterThanOrEqualTo(2.0),
            reason: '$name: link $link מול onSurface ${cs.onSurface}',
          );
          for (final background in [
            cs.surface,
            cs.surfaceContainerHighest,
            if (brightness == Brightness.dark) AppColors.darkScaffold,
          ]) {
            expect(
              _contrastRatio(link, background),
              greaterThanOrEqualTo(4.5),
              reason: '$name: link $link מול $background',
            );
          }
        }
      }
    });

    test('צבעי הממשק נשמרים בכל ערכות הבסיס (#2589)', () {
      for (final option in AppSeedColors.options) {
        final neutral = HSLColor.fromColor(option.color).saturation < 0.1;
        for (final brightness in Brightness.values) {
          final cs = AppThemeData.createColorScheme(option.color, brightness);
          final base = ColorScheme.fromSeed(
            seedColor: option.color,
            brightness: brightness,
            dynamicSchemeVariant: neutral
                ? DynamicSchemeVariant.monochrome
                : DynamicSchemeVariant.tonalSpot,
          );
          if (!neutral) {
            expect(AppSurfaces.readerLink(cs), base.primary);
          }
          expect(
            cs.primary,
            base.primary,
            reason: '${option.name} $brightness',
          );
          expect(cs.onPrimary, base.onPrimary, reason: option.name);
        }
      }
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
