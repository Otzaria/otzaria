import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';

void main() {
  group('AppSurfaces.selectedItem', () {
    late ColorScheme lightScheme;
    late ColorScheme darkScheme;

    setUpAll(() {
      lightScheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      );
      darkScheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );
    });

    test('מחזיר primaryContainer בשקיפות 30%', () {
      final result = AppSurfaces.selectedItem(lightScheme);
      final expected = lightScheme.primaryContainer.withValues(alpha: 0.3);
      expect(result, expected);
    });

    test('עובד גם עם ערכת צבעים כהה', () {
      final result = AppSurfaces.selectedItem(darkScheme);
      final expected = darkScheme.primaryContainer.withValues(alpha: 0.3);
      expect(result, expected);
    });

    test('צבע שונה מ-primaryContainer המלא', () {
      final selected = AppSurfaces.selectedItem(lightScheme);
      final full = lightScheme.primaryContainer;
      // alpha 30% שונה מ-alpha 100%
      expect(selected.a, isNot(equals(full.a)));
    });

    test('alpha קרוב ל-0.3 (סובלנות לעיגול float)', () {
      final selected = AppSurfaces.selectedItem(lightScheme);
      expect(selected.a, closeTo(0.3, 0.01));
    });
  });

  group('AppSurfaces.paragraphSelectionBackground', () {
    ThemeData themeFor(Color seed, Brightness brightness) {
      final cs = AppThemeData.createColorScheme(seed, brightness);
      final variant = AppThemeVariant.ofSeed(seed);
      return brightness == Brightness.light
          ? AppThemeData.light(cs, compactMenuMode: false, variant: variant)
          : AppThemeData.dark(cs, compactMenuMode: false, variant: variant);
    }

    test('ערכת "לבן" במצב בהיר נותנת F8FAFC', () {
      expect(
        AppSurfaces.paragraphSelectionBackground(
          themeFor(AppSeedColors.white, Brightness.light),
        ),
        const Color(0xFFF8FAFC),
      );
    });

    test('ערכת "לבן" במצב כהה נשארת 8% primary', () {
      final theme = themeFor(AppSeedColors.white, Brightness.dark);
      expect(
        AppSurfaces.paragraphSelectionBackground(theme),
        theme.colorScheme.primary.withValues(alpha: 0.08),
      );
    });

    test('ערכת ברירת מחדל נותנת 8% primary', () {
      final theme = themeFor(Colors.blue, Brightness.light);
      expect(
        AppSurfaces.paragraphSelectionBackground(theme),
        theme.colorScheme.primary.withValues(alpha: 0.08),
      );
    });

    test('פרגמנט נשאר 8% primary — לא F8FAFC', () {
      expect(
        AppSurfaces.paragraphSelectionBackground(
          themeFor(AppSeedColors.parchment, Brightness.light),
        ),
        isNot(const Color(0xFFF8FAFC)),
      );
    });

    test('הערכה נקבעת לפי הזרע, לא לפי surface לבן', () {
      final cs = AppThemeData.createColorScheme(
        Colors.blue,
        Brightness.light,
      ).copyWith(surface: Colors.white);
      final theme = AppThemeData.light(cs, compactMenuMode: false);
      expect(
        AppSurfaces.paragraphSelectionBackground(theme),
        cs.primary.withValues(alpha: 0.08),
      );
    });
  });
}
