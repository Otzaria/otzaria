import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';

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
}
