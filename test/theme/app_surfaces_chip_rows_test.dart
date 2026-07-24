import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// גבולות הפער הנתפס בין שתי שורות צ׳יפי הסינון בפאנל הקישורים.
///
/// מתחת ל-[_minDeltaLuminance] השורות נראות כגוש אחד והפיצול מאבד את טעמו;
/// מעל ל-[_maxDeltaLuminance] הרצועה צועקת ומסיחה מטקסט הספר.
const double _minDeltaLuminance = 0.02;
const double _maxDeltaLuminance = 0.06;

/// מודד את שתי שורות הצ׳יפים אחרי שיטוח מעל רקע הפאנל.
///
/// השיטוח הכרחי: שני הצבעים מוחזרים עם אלפא, והשוואת הצבע הגולמי מסתירה
/// קריסת ניגודיות מעל [AppSurfaces.panelBackground] הכהה שהוא שחור טהור.
Future<({Color type, Color era})> _flattenedChipRows(
  WidgetTester tester, {
  required Color seedColor,
  required Brightness brightness,
}) async {
  final colorScheme = AppThemeData.createColorScheme(seedColor, brightness);
  late Color background;
  late Color typeRow;
  late Color eraRow;

  await tester.pumpWidget(
    MaterialApp(
      // מפתח ייחודי מכריח בנייה מחדש של ה-Builder בכל איטרציה של הלולאה.
      key: ValueKey('$seedColor$brightness'),
      theme: ThemeData(colorScheme: colorScheme),
      home: Builder(
        builder: (context) {
          background = AppSurfaces.panelBackground(context);
          typeRow = AppSurfaces.linkTypeChipsRow(context);
          eraRow = AppSurfaces.linkEraChipsRow(context);
          return const SizedBox();
        },
      ),
    ),
  );

  return (
    type: Color.alphaBlend(typeRow, background),
    era: Color.alphaBlend(eraRow, background),
  );
}

void main() {
  group('רקעי שורות צ׳יפי הסינון בפאנל הקישורים', () {
    for (final option in AppSeedColors.options) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'הפער בין השורות נראה אך עדין — ${option.name} / ${brightness.name}',
          (tester) async {
            final rows = await _flattenedChipRows(
              tester,
              seedColor: option.color,
              brightness: brightness,
            );

            final delta =
                (rows.type.computeLuminance() - rows.era.computeLuminance())
                    .abs();

            expect(
              delta,
              greaterThanOrEqualTo(_minDeltaLuminance),
              reason: 'הפער בין השורות קטן מדי — הן נראות כגוש אחד',
            );
            expect(
              delta,
              lessThanOrEqualTo(_maxDeltaLuminance),
              reason: 'הפער בין השורות גדול מדי — הרצועה צועקת',
            );
          },
        );
      }
    }

    for (final option in AppSeedColors.options) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'שורת הסוגים בולטת מהרקע יותר משורת הדורות — '
          '${option.name} / ${brightness.name}',
          (tester) async {
            late Color background;
            await tester.pumpWidget(
              MaterialApp(
                key: ValueKey('${option.color}$brightness'),
                theme: ThemeData(
                  colorScheme: AppThemeData.createColorScheme(
                    option.color,
                    brightness,
                  ),
                ),
                home: Builder(
                  builder: (context) {
                    background = AppSurfaces.panelBackground(context);
                    return const SizedBox();
                  },
                ),
              ),
            );

            final rows = await _flattenedChipRows(
              tester,
              seedColor: option.color,
              brightness: brightness,
            );

            final backgroundLuminance = background.computeLuminance();
            final typeContrast =
                (rows.type.computeLuminance() - backgroundLuminance).abs();
            final eraContrast =
                (rows.era.computeLuminance() - backgroundLuminance).abs();

            expect(
              typeContrast,
              greaterThan(eraContrast),
              reason: 'ציר הסוגים הוא הראשי ולכן חייב להיות הבולט מבין השניים',
            );
          },
        );
      }
    }

    testWidgets('ערכת "אפור" לא חורגת מיתר הצבעים', (tester) async {
      // רגרסיה: primaryContainer בווריאנט monochrome הפך לאפור כהה
      // והפער קפץ פי 17 מכל צבע אחר.
      final deltas = <double>[];

      for (final option in AppSeedColors.options) {
        final rows = await _flattenedChipRows(
          tester,
          seedColor: option.color,
          brightness: Brightness.light,
        );
        deltas.add(
          (rows.type.computeLuminance() - rows.era.computeLuminance()).abs(),
        );
      }

      final greyIndex = AppSeedColors.options.indexWhere(
        (option) => option.color == AppSeedColors.grey,
      );
      final greyDelta = deltas[greyIndex];
      final maxOther = deltas
          .where((delta) => delta != greyDelta)
          .reduce((a, b) => a > b ? a : b);

      expect(greyDelta, lessThan(maxOther * 2));
    });
  });
}
