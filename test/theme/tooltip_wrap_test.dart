import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// #5250: tooltip ארוך נפרס על כל רוחב החלון בשורה אחת.
void main() {
  final longMessage = SearchQueryBuilder
      .wordOptionDescriptions[SearchQueryBuilder.typoToleranceOptionKey]!;

  Future<Size> tooltipSize(
    WidgetTester tester,
    String message, {
    required double windowWidth,
  }) async {
    tester.view.physicalSize = Size(windowWidth, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(
          AppThemeData.createColorScheme(
            AppSeedColors.defaultLight,
            Brightness.light,
          ),
          compactMenuMode: false,
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: const Alignment(0.35, -0.6),
              child: Tooltip(
                message: message,
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    tester.state<TooltipState>(find.byType(Tooltip)).ensureTooltipVisible();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return tester.getSize(
      find
          .ancestor(
            of: find.text(message),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
  }

  for (final width in [1273.0, 900.0]) {
    testWidgets('הסבר ארוך עובר שורה ואינו רחב מרוחב קריאה (חלון $width)', (
      tester,
    ) async {
      final size = await tooltipSize(tester, longMessage, windowWidth: width);
      expect(size.width, lessThanOrEqualTo(420));
      expect(size.height, greaterThan(60), reason: 'הטקסט עטוף למספר שורות');
    });
  }

  testWidgets('הטקסט המעטפת ממורכז', (tester) async {
    await tooltipSize(tester, longMessage, windowWidth: 900);
    final text = tester.widget<Text>(find.text(longMessage));
    expect(text.textAlign, TextAlign.center);
  });

  test('בחלון צר נשאר שוליים אופקיים מקצה החלון', () {
    final theme = AppThemeData.light(
      AppThemeData.createColorScheme(
        AppSeedColors.defaultLight,
        Brightness.light,
      ),
      compactMenuMode: false,
    );
    expect(
      theme.tooltipTheme.margin,
      const EdgeInsets.symmetric(horizontal: 8),
    );
  });

  testWidgets('הסבר קצר נשאר ברוחב התוכן', (tester) async {
    final size = await tooltipSize(tester, 'הדפסה', windowWidth: 900);
    expect(size.width, lessThan(120));
    expect(size.height, inInclusiveRange(24, 60));
  });
}
