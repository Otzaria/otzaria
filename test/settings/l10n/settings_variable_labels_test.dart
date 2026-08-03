// תוויות שמגיעות ל-settingsText דרך משתנה — לא כמחרוזת קבועה בתוך הקריאה.
// הסורק של הולידציה רואה רק ארגומנטים קבועים, ולכן אלו חומקות מבדיקת
// "לכל מפתח בקוד יש תרגום": הן הוצגו בעברית גם כשההגדרות באנגלית.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/tabs/about_settings_data.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

import '../../../tool/src/settings_l10n_generator.dart';

void main() {
  final catalog = kSettingsCatalogs['en']!;

  group('תוויות מטבלאות נתונים', () {
    const dataLabels = <String, List<String>>{
      'about_settings_data.dart': [
        aboutTopEditorsLabel,
        aboutRegularEditorsLabel,
        aboutMainSourcesLabel,
        aboutAdditionalSourcesLabel,
      ],
    };

    for (final entry in dataLabels.entries) {
      for (final label in entry.value) {
        test('[${entry.key}] "$label"', () {
          expect(catalog, contains(label));
        });
      }
    }

    test('שמות צבעי הבסיס', () {
      for (final option in AppSeedColors.options) {
        expect(catalog, contains(option.name), reason: option.name);
      }
    });
  });

  group('סרגל הניווט ופס הכותרת', () {
    // `_navData` פרטי ל-State, ולכן הרשימה כאן מפורשת — והבדיקה שאחריה
    // מאמתת שהיא עדיין מכסה אותו, כדי שפריט ניווט חדש לא יישאר בעברית.
    const navLabels = [
      'ספרייה',
      'איתור',
      'עיון',
      'חיפוש',
      'כלים',
      'הגדרות',
    ];

    test('כל תווית ניווט מתורגמת', () {
      for (final label in [...navLabels, 'אוצריא']) {
        expect(catalog, contains(label), reason: label);
      }
    });

    test('הרשימה כאן מכסה את _navData', () {
      final source = File(
        'lib/navigation/view/main_window_screen.dart',
      ).readAsStringSync();
      final block = RegExp(
        r'static const _navData = \[(.*?)\n  \];',
        dotAll: true,
      ).firstMatch(source);
      expect(block, isNotNull, reason: '_navData לא נמצא — עדכן את הבדיקה');
      final labels = RegExp(
        r"label: '([^']*)'",
      ).allMatches(block!.group(1)!).map((m) => m.group(1)!).toList();
      expect(labels, navLabels);
    });
  });

  group('אורך תוויות בפקד סגמנטד', () {
    // AppSegmentedControl עוטף כל תווית ב-FittedBox, שמקטין אותה בנפרד.
    // תרגום ארוך מוצג לכן בגופן קטן משכניו, כפי שקרה ל"שם וכותרת".
    // התווית הארוכה ביום כתיבת הבדיקה היא 14 תווים.
    const maxLabelLength = 16;

    test('אין תווית ארוכה מ-$maxLabelLength תווים', () {
      final tooLong = <String>[];
      for (final entry in scanSegmentOptionKeys(Directory.current)) {
        final label = resolveSettingsText(
          entry.hebrew,
          language: SettingsLanguage.english,
          context: entry.context,
        );
        if (label.length > maxLabelLength) {
          tooLong.add('"${entry.hebrew}" → "$label" (${label.length})');
        }
      }
      expect(
        tooLong,
        isEmpty,
        reason:
            'תווית ארוכה מדי תוצג בגופן מוקטן לעומת האפשרויות שלידה:\n'
            '${tooLong.join('\n')}',
      );
    });
  });
}
