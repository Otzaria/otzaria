import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';

void main() {
  group('AppSurfaces — מצבי שורה (DD-06)', () {
    for (final brightness in Brightness.values) {
      test('ב-$brightness: נבחר מלא, פוקוס וריחוף ב-8%', () {
        final cs = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        expect(AppSurfaces.selectedRow(cs), cs.secondaryContainer);
        expect(AppSurfaces.selectedRow(cs).a, 1.0);
        expect(AppSurfaces.focusedRow(cs).a, closeTo(0.08, 0.01));
        expect(AppSurfaces.hoverRow(cs).a, closeTo(0.08, 0.01));
        expect(
          AppSurfaces.multiSelected(cs),
          isNot(AppSurfaces.selectedRow(cs)),
        );
      });
    }
  });

  group('AppSurfaces.tintedRow', () {
    for (final brightness in Brightness.values) {
      test('ב-$brightness: 5% surfaceTint, כמו לפני שקיבל שם (#3086)', () {
        final cs = ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        );
        expect(
          AppSurfaces.tintedRow(cs),
          cs.surfaceTint.withValues(alpha: 0.05),
        );
      });
    }
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
