// תוויות שמגיעות ל-settingsText דרך משתנה — לא כמחרוזת קבועה בתוך הקריאה.
// הסורק של הולידציה רואה רק ארגומנטים קבועים, ולכן אלו חומקות מבדיקת
// "לכל מפתח בקוד יש תרגום": הן הוצגו בעברית גם כשההגדרות באנגלית.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/tabs/about_settings_data.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_step.dart';
import 'package:otzaria/tour/models/tour_steps.dart';

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
      for (final label in navLabels) {
        expect(catalog, contains(label), reason: label);
      }
    });

    // שמות המסכים בפס הכותרת. 'ספריה' שם הוא שם המסך, ולכן הקשר נפרד
    // מלשונית ההגדרות שנושאת את אותה מילה.
    test('שמות המסכים בפס הכותרת מתורגמים', () {
      for (final key in ['אוצריא', 'ספריה|titleBar']) {
        expect(catalog, contains(key), reason: key);
      }
      expect(catalog['ספריה|titleBar'], catalog['ספרייה']);
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

  group('הסיור המודרך', () {
    // הכרטיסים מקבלים את הטקסט מתוך TourStep / LiveTipSpec, ולכן הסורק אינו
    // רואה אותו. השלבים נבנים כאן בפועל, כך שגם שלב חדש וגם שינוי נוסח
    // בשלב קיים נתפסים.
    final steps = [
      ...TourSteps.build(libraryLoaded: true),
      ...TourSteps.build(libraryLoaded: false),
      ...TourSteps.build(libraryLoaded: true, isRestart: true),
      ...TourSteps.build(libraryLoaded: false, isRestart: true),
    ];

    test('נבנו שלבים לכל הגלגולים', () {
      expect(steps, isNotEmpty);
    });

    for (final id in steps.map((step) => step.id).toSet()) {
      final step = steps.firstWhere((step) => step.id == id);
      test('[$id] הכותרת והגוף מתורגמים', () {
        for (final text
            in steps
                .where((other) => other.id == id)
                .expand((other) => [other.title, other.body])
                .toSet()) {
          expect(catalog, contains(text), reason: '"$text"');
        }
      });

      test('[$id] הגוף מכיל {shortcut} רק כשיש קיצור', () {
        final hasPlaceholder = step.body.contains('{shortcut}');
        expect(
          hasPlaceholder,
          step.shortcut != TourShortcutHint.none,
          reason: hasPlaceholder
              ? 'יש placeholder בלי קיצור — יוצג "{shortcut}" למשתמש'
              : 'יש קיצור בלי placeholder — הקיצור לא יוצג',
        );
        if (hasPlaceholder) {
          expect(
            catalog[step.body],
            contains('{shortcut}'),
            reason: 'התרגום איבד את ה-placeholder',
          );
        }
      });
    }

    for (final tip in liveTipSpecs) {
      test('[${tip.id.name}] הטיפ מתורגם', () {
        expect(catalog, contains(tip.title), reason: tip.title);
        expect(catalog, contains(tip.description), reason: tip.description);
      });
    }
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
