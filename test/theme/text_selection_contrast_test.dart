// צבע בחירת הטקסט (פריט 22, theme-dark-03). ברירת המחדל של Flutter היא
// primary ב-40%, ובכהה של סכמה נייטרלית ("לבן", "אפור") primary כמעט לבן,
// והטקסט מעל הבחירה ירד ל-3.24:1. הערכה קובעת שקיפות לפי בהירות: הצבע הראשי
// נשאר, והשקיפות בכהה נמוכה יותר.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

double _ratio(Color a, Color b) {
  final f = a.computeLuminance() + 0.05;
  final g = b.computeLuminance() + 0.05;
  return f > g ? f / g : g / f;
}

ThemeData _theme(Color seed, Brightness brightness) {
  final cs = AppThemeData.createColorScheme(seed, brightness);
  final variant = AppThemeVariant.ofSeed(seed);
  return brightness == Brightness.light
      ? AppThemeData.light(cs, compactMenuMode: false, variant: variant)
      : AppThemeData.dark(cs, compactMenuMode: false, variant: variant);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final option in AppSeedColors.options) {
      test(
        'טקסט על בחירה: ${option.name} (${brightness.name}), 4.5:1 לפחות',
        () {
          final theme = _theme(option.color, brightness);
          final cs = theme.colorScheme;
          final selection = theme.textSelectionTheme.selectionColor;
          expect(selection, isNotNull, reason: 'הערכה לא קובעת צבע בחירה');
          final surfaces = AppSurfaceColors.fromScheme(
            cs,
            variant: AppThemeVariant.ofSeed(option.color),
          );
          for (final (name, background) in [
            ('קריאה', surfaces.readerBackground),
            ('כרטיס', surfaces.card),
          ]) {
            final fill = Color.alphaBlend(selection!, background);
            final ratio = _ratio(cs.onSurface, fill);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: 'טקסט על בחירה מעל $name: ${ratio.toStringAsFixed(2)}:1',
            );
          }
        },
      );
    }
  }

  test('הצבע הראשי נשמר, והשקיפות לפי בהירות: 0.38 בבהיר ו-0.28 בכהה', () {
    for (final brightness in Brightness.values) {
      final theme = _theme(AppSeedColors.white, brightness);
      final selection = theme.textSelectionTheme.selectionColor!;
      expect(
        selection.a,
        closeTo(brightness == Brightness.dark ? 0.28 : 0.38, 0.005),
      );
      expect(
        selection.withValues(alpha: 1),
        theme.colorScheme.primary.withValues(alpha: 1),
      );
    }
  });
}
