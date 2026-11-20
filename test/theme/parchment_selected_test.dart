// ערכת "פרגמנט" בבהיר (פריט 23, theme-dark-08): secondaryContainer של M3
// יצא ורדרד באותה בהירות כמו הלוח (1.01:1), והשורה הנבחרת כמעט לא נבדלה
// מהרקע. הערכה דורסת אותו כמו ב"לבן" (white_selected_test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';

double _ratio(Color a, Color b) {
  final f = a.computeLuminance() + 0.05;
  final g = b.computeLuminance() + 0.05;
  return f > g ? f / g : g / f;
}

void main() {
  final cs = AppThemeData.createColorScheme(
    AppSeedColors.parchment,
    Brightness.light,
  );
  final surfaces = AppSurfaceColors.fromScheme(
    cs,
    variant: AppThemeVariant.parchment,
  );
  final selected = AppSurfaces.selectedRow(cs);

  test('שורה נבחרת נבדלת מהלוח, מהקריאה ומהכרטיס כמו ב"לבן" (1.3:1 ומעלה)', () {
    expect(
      _ratio(selected, surfaces.panelBackground),
      greaterThanOrEqualTo(1.3),
    );
    expect(
      _ratio(selected, surfaces.readerBackground),
      greaterThanOrEqualTo(1.4),
    );
    expect(_ratio(selected, surfaces.card), greaterThanOrEqualTo(1.4));
  });

  test('טקסט, טקסט משני וטבעת פוקוס על שורה נבחרת עוברים את הסף', () {
    expect(
      _ratio(AppSurfaces.onSelectedRow(cs), selected),
      greaterThanOrEqualTo(4.5),
    );
    expect(_ratio(cs.onSurface, selected), greaterThanOrEqualTo(4.5));
    expect(_ratio(cs.onSurfaceVariant, selected), greaterThanOrEqualTo(4.5));
    expect(_ratio(cs.primary, selected), greaterThanOrEqualTo(3));
  });

  test('הגוון חום-חול ולא ורוד, וה"פרגמנט" בכהה ללא שינוי', () {
    final hue = HSLColor.fromColor(selected).hue;
    expect(hue, inInclusiveRange(20, 50));
    final dark = AppThemeData.createColorScheme(
      AppSeedColors.parchment,
      Brightness.dark,
    );
    final raw = ColorScheme.fromSeed(
      seedColor: AppSeedColors.parchment,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    expect(dark.secondaryContainer, raw.secondaryContainer);
  });
}
