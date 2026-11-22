// עיגול צבע שדומה לרקע הדיאלוג (לבן על דיאלוג בהיר, כחול כהה על
// כהה) חייב להיראות. לכל זרע בכל ערכה: העיגול עצמו או המסגרת שלו מובחנים
// מרקע הדיאלוג ביחס של 3:1 לפחות (WCAG 1.4.11, רכיב ממשק גרפי).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/color_picker_dialog.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final themeSeed in AppSeedColors.options) {
      testWidgets(
        'עיגולי הצבע מובחנים מהדיאלוג: ערכת ${themeSeed.name} '
        '(${brightness.name})',
        (tester) async {
          final scheme = AppThemeData.createColorScheme(
            themeSeed.color,
            brightness,
          );
          final theme = brightness == Brightness.light
              ? AppThemeData.light(scheme, compactMenuMode: false)
              : AppThemeData.dark(scheme, compactMenuMode: false);
          tester.view.physicalSize = const Size(900, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: ColorPickerTile(
                    // צבע מותאם שאינו ברשימה: אף עיגול אינו "נבחר", כך שכולם
                    // בלי טבעת הבחירה.
                    currentColor: const Color(0xFF123456),
                    defaultColor: AppSeedColors.defaultLight,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('שינוי צבע'));
          await tester.pumpAndSettle();

          final dialogBackground = theme.dialogTheme.backgroundColor!;
          final swatches = find.byWidgetPredicate((widget) {
            if (widget is! Container) return false;
            final decoration = widget.decoration;
            return decoration is BoxDecoration &&
                decoration.shape == BoxShape.circle &&
                widget.constraints?.maxWidth == 40;
          });
          expect(swatches, findsNWidgets(AppSeedColors.options.length));

          final weak = <String>[];
          for (final element in swatches.evaluate()) {
            final decoration =
                (element.widget as Container).decoration! as BoxDecoration;
            final fill = decoration.color!;
            final border = decoration.border;
            final borderColor = border is Border ? border.top.color : null;
            final visible = [
              _contrast(fill, dialogBackground),
              if (borderColor != null) _contrast(borderColor, dialogBackground),
            ].reduce((a, b) => a > b ? a : b);
            if (visible < 3) {
              weak.add(
                '#${fill.toARGB32().toRadixString(16)} '
                '${visible.toStringAsFixed(2)}:1',
              );
            }
          }
          expect(weak, isEmpty, reason: 'עיגולים כמעט בלתי נראים: $weak');
        },
      );
    }
  }
}
