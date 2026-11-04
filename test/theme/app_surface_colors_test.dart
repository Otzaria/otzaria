import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';

ThemeData _theme(Color seed, Brightness brightness) {
  final cs = AppThemeData.createColorScheme(seed, brightness);
  final variant = AppThemeVariant.ofSeed(seed);
  return brightness == Brightness.light
      ? AppThemeData.light(cs, compactMenuMode: false, variant: variant)
      : AppThemeData.dark(cs, compactMenuMode: false, variant: variant);
}

Future<BuildContext> _pumpTheme(WidgetTester tester, ThemeData theme) async {
  late BuildContext captured;
  await tester.pumpWidget(
    Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('AppSurfaceColors', () {
    for (final seed in [
      AppSeedColors.defaultLight,
      AppSeedColors.white,
      AppSeedColors.parchment,
      AppSeedColors.darkBrown,
    ]) {
      for (final brightness in Brightness.values) {
        test('נבנה ב-AppThemeData מהסכמה ($seed, $brightness)', () {
          final theme = _theme(seed, brightness);
          expect(
            theme.extension<AppSurfaceColors>(),
            AppSurfaceColors.fromScheme(
              theme.colorScheme,
              variant: AppThemeVariant.ofSeed(seed),
            ),
          );
        });
      }
    }

    test('קו האזורים: אפור בינוני בערכת "לבן" בבהיר, ובשאר הערכות אין', () {
      for (final seed in [
        AppSeedColors.defaultLight,
        AppSeedColors.white,
        AppSeedColors.grey,
        AppSeedColors.parchment,
        AppSeedColors.blue,
      ]) {
        for (final brightness in Brightness.values) {
          final theme = _theme(seed, brightness);
          final s = theme.extension<AppSurfaceColors>()!;
          if (seed == AppSeedColors.white && brightness == Brightness.light) {
            // 9F9F9F, אטום ונייטרלי (סקירת 4.11: "פחות כהים"; סבב שלישי:
            // "9F, בהיר יותר").
            final c = s.regionBorder!;
            expect((c.r * 255).round(), 0x9F);
            expect(c.a, 1);
            expect(c.r, c.g);
            expect(c.g, c.b);
            // עדיין גלוי: ניגודיות 2.5:1 לפחות מול הסרגלים (FC) והקריאה.
            // מתחת ל־3:1 בכוונה (הכרעת בעל הפרויקט): 2.58 ו־2.65.
            double contrast(Color a, Color b) {
              final la = a.computeLuminance(), lb = b.computeLuminance();
              return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
            }

            expect(
              contrast(c, theme.colorScheme.surfaceContainerHigh),
              greaterThanOrEqualTo(2.5),
            );
            expect(
              contrast(c, s.readerBackground),
              greaterThanOrEqualTo(2.5),
            );
          } else {
            expect(s.regionBorder, isNull, reason: '$seed $brightness');
          }
        }
      }
    });

    testWidgets('העטיפות ב-AppSurfaces קוראות את ההרחבה', (tester) async {
      for (final brightness in Brightness.values) {
        final theme = _theme(AppSeedColors.defaultLight, brightness);
        final context = await _pumpTheme(tester, theme);
        final s = theme.extension<AppSurfaceColors>()!;
        expect(AppSurfaces.readerBackground(context), s.readerBackground);
        expect(AppSurfaces.panelBackground(context), s.panelBackground);
        expect(AppSurfaces.topBarBackground(context), s.topBarBackground);
        expect(AppSurfaces.navPanelBackground(context), s.navPanelBackground);
        expect(AppSurfaces.card(context), s.card);
        expect(AppSurfaces.panelSection(context), s.panelSection);
        expect(AppSurfaces.panelSectionAccent(context), s.panelSectionAccent);
        expect(
          AppSurfaces.panelSectionAccentBorder(context),
          s.panelSectionAccentBorder,
        );
        expect(AppSurfaces.cardRowDivider(context), s.cardRowDivider);
        expect(AppSurfaces.paneCard(context), s.paneCard);
        expect(AppSurfaces.paneGutter(context), s.paneGutter);
      }
    });

    testWidgets('דריסה לתת-עץ משנה רק את המשטח שנדרס', (tester) async {
      final theme = _theme(AppSeedColors.defaultLight, Brightness.light);
      final base = theme.extension<AppSurfaceColors>()!;
      final context = await _pumpTheme(
        tester,
        theme.copyWith(
          extensions: [base.copyWith(topBarBackground: Colors.teal)],
        ),
      );
      expect(AppSurfaces.topBarBackground(context), Colors.teal);
      expect(AppSurfaces.card(context), base.card);
    });

    testWidgets('Theme בלי ההרחבה מחושב מה-ColorScheme שלו', (tester) async {
      final cs = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
      final context = await _pumpTheme(tester, ThemeData(colorScheme: cs));
      expect(AppSurfaceColors.of(context), AppSurfaceColors.fromScheme(cs));
      expect(AppSurfaces.panelBackground(context), cs.surfaceContainerLow);
    });

    test('lerp מחזיר את הקצוות ומערבב באמצע', () {
      final light = _theme(
        AppSeedColors.defaultLight,
        Brightness.light,
      ).extension<AppSurfaceColors>()!;
      final dark = _theme(
        AppSeedColors.defaultDark,
        Brightness.dark,
      ).extension<AppSurfaceColors>()!;
      expect(light.lerp(dark, 0), light);
      expect(light.lerp(dark, 1), dark);
      expect(light.lerp(null, 0.5), light);
      expect(
        light.lerp(dark, 0.5).card,
        Color.lerp(light.card, dark.card, 0.5),
      );
    });
  });

  testWidgets('ReaderSurfaceScope נותן ל-Scaffold את רקע הקריאה', (
    tester,
  ) async {
    final theme = _theme(AppSeedColors.defaultDark, Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const ReaderSurfaceScope(child: Scaffold(body: SizedBox())),
      ),
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(Scaffold),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      material.color,
      theme.extension<AppSurfaceColors>()!.readerBackground,
    );
  });
}
