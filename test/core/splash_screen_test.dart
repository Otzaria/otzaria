import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/splash_screen.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('מסך הפתיחה עוקב אחרי בהירות המערכת ($brightness)', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(const SplashApp());

      final expected = AppThemeData.createColorScheme(
        brightness == Brightness.dark
            ? AppSeedColors.defaultDark
            : AppSeedColors.defaultLight,
        brightness,
      ).surface;
      final scaffold = tester.element(find.byType(Scaffold));
      expect(Theme.of(scaffold).brightness, brightness);
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(Scaffold),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        expected,
      );
    });
  }
}
