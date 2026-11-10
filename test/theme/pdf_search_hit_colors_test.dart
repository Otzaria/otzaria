import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// DD-17: ההדגשה בעמוד PDF נגזרת מטוקני החיפוש, שקופה כי היא מעל הטקסט.
void main() {
  for (final brightness in Brightness.values) {
    test('צבעי ההדגשה ב-PDF, ${brightness.name}', () {
      final cs = AppThemeData.createColorScheme(
        brightness == Brightness.dark
            ? AppSeedColors.defaultDark
            : AppSeedColors.defaultLight,
        brightness,
      );
      final hit = AppSurfaces.pdfSearchHit(cs);
      final current = AppSurfaces.pdfSearchHitCurrent(cs);
      expect(hit.withValues(alpha: 1), AppSurfaces.searchHit(cs));
      expect(hit.a, closeTo(0.35, 0.01));
      expect(
        current.withValues(alpha: 1),
        AppSurfaces.searchHitCurrentBackground(cs).withValues(alpha: 1),
      );
      expect(current.a, closeTo(0.5, 0.01));
    });
  }
}
