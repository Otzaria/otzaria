// טסטים ל-entryFromZmanDefinition (בניית כרטיס בודד מהגדרת זמן) ולתקינות
// רישום הזמנים המרכזי kZmanimRegistry.

import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/tools/calendar/models/zman_definition.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_times_panel.dart';

DateTime? _noCompute(ZmanComputeContext _) => null;

ZmanDefinition _def(
  String id, {
  String subtitle = '',
  bool showHebrewDate = false,
}) => ZmanDefinition(
  id: id,
  title: 'זמן $id',
  subtitle: subtitle,
  category: 'בדיקה',
  explanation: 'הסבר',
  showHebrewDate: showHebrewDate,
  compute: _noCompute,
);

void main() {
  group('entryFromZmanDefinition — כרטיס בודד', () {
    test('מחזיר null כשהזמן חסר', () {
      expect(entryFromZmanDefinition(_def('sunset'), const {}), isNull);
    });

    test('בונה כרטיס לא-composite עם כותרת, תת-כותרת והתראה', () {
      final entry = entryFromZmanDefinition(
        _def('sunset', subtitle: 'מישורית'),
        const {'sunset': '19:50'},
      )!;

      expect(entry.id, 'sunset');
      expect(entry.name, 'זמן sunset');
      expect(entry.subtitle, 'מישורית');
      expect(entry.time, '19:50');
      expect(entry.isComposite, isFalse);
      expect(entry.canAlert, isTrue);
      expect(entry.alertOptions, hasLength(1));
      expect(entry.alertOptions.single.id, 'sunset');
    });

    test('זמן תאריך עברי (קידוש לבנה) — לא ניתן להתראה ובלי alertOptions', () {
      // הזמן מעוצב כתאריך ("ליל שבת ט״ז לחודש 02:37") ולא ניתן לתזמון
      // נקודתי, ולכן אסור לבנות עבורו אפשרות התראה.
      final entry = entryFromZmanDefinition(
        _def('tchilasKidushLevana3', showHebrewDate: true),
        const {'tchilasKidushLevana3': 'ליל שבת ט״ז לחודש 02:37'},
      )!;

      expect(entry.canAlert, isFalse);
      expect(entry.alertOptions, isEmpty);
    });
  });

  group('kZmanimRegistry — תקינות הרישום', () {
    test('כל המזהים ייחודיים', () {
      final ids = kZmanimRegistry.map((d) => d.id).toList();
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'מזהי ZmanDefinition חייבים להיות ייחודיים',
      );
    });

    test('ברירת המחדל אינה ריקה וכלולה ברישום', () {
      final allIds = kZmanimRegistry.map((d) => d.id).toSet();
      expect(kDefaultEnabledZmanim, isNotEmpty);
      expect(allIds.containsAll(kDefaultEnabledZmanim), isTrue);
    });

    test('לכל זוג (pairId) בדיוק שתי הגדרות עם pairLabel ואותה כותרת', () {
      final byPair = <String, List<ZmanDefinition>>{};
      for (final def in kZmanimRegistry) {
        if (def.pairId != null) {
          byPair.putIfAbsent(def.pairId!, () => []).add(def);
        }
      }
      expect(byPair, isNotEmpty);
      for (final entry in byPair.entries) {
        expect(
          entry.value,
          hasLength(2),
          reason: 'זיווג ${entry.key} חייב להכיל בדיוק 2 הגדרות',
        );
        // שתי ההגדרות בזיווג חולקות כותרת (title) זהה — היא הכותרת
        // המשותפת של הכרטיס המשולב.
        expect(
          entry.value[0].title,
          entry.value[1].title,
          reason: 'זיווג ${entry.key}: שתי ההגדרות צריכות אותה כותרת',
        );
        for (final def in entry.value) {
          expect(def.pairLabel, isNotEmpty, reason: '${def.id}: חסר pairLabel');
        }
      }
    });

    test('ק"ש ותפילה כוללים זיווג מג"א-גר"א', () {
      ZmanDefinition byId(String id) =>
          kZmanimRegistry.firstWhere((d) => d.id == id);
      expect(
        byId('sofZmanShmaMGA90Degrees').pairId,
        byId('sofZmanShmaGRA').pairId,
      );
      expect(byId('sofZmanShmaMGA90Degrees').pairId, isNotNull);
      expect(
        byId('sofZmanTfilaMGA90Degrees').pairId,
        byId('sofZmanTfilaGRA').pairId,
      );
      expect(byId('sofZmanShmaGRA').pairLabel, 'גר"א');
      expect(byId('sofZmanShmaMGA90Degrees').pairLabel, 'מג"א');
    });

    test('ברירות המחדל כוללות את הזמנים העיקריים שהמשתמש ביקש', () {
      expect(
        kDefaultEnabledZmanim,
        containsAll([
          'sunrise',
          'seaLevelSunrise',
          'sunset',
          'seaLevelSunset',
          'chatzos',
          'chatzosLayla',
          'alos72Degrees',
          'alos90Degrees',
          'misheyakir10point2',
          'sofZmanShmaMGA90Degrees',
          'sofZmanShmaGRA',
          'sofZmanTfilaMGA90Degrees',
          'sofZmanTfilaGRA',
          'minchaGedolaGreater30',
          'minchaKetanaGRA',
          'plagGRA',
          'tzeitTikochinsky',
          'tzeitItimLeVina',
          'rt72Shavos',
          'candleLighting',
        ]),
      );
    });

    test('כל זמני יציאת הצום מופעלים כברירת מחדל; אין "תחילת התענית"', () {
      final fastIds = kZmanimRegistry
          .where((d) => d.category == 'תעניות')
          .map((d) => d.id)
          .toList();
      expect(fastIds, isNot(contains('fastStart')));
      for (final def in kZmanimRegistry.where((d) => d.category == 'תעניות')) {
        expect(
          def.defaultEnabled,
          isTrue,
          reason: '${def.id}: כל יציאות הצום מופעלות כברירת מחדל',
        );
      }
    });

    test('זמני בין השמשות כבויים כברירת מחדל', () {
      final bin = kZmanimRegistry.where((d) => d.category == 'בין השמשות');
      expect(bin, isNotEmpty);
      for (final def in bin) {
        expect(def.defaultEnabled, isFalse);
      }
    });

    test('קידוש לבנה: לא תלוי-יום, כבוי כברירת מחדל, ומציג תאריך עברי', () {
      final levana = kZmanimRegistry.where((d) => d.category == 'קידוש לבנה');
      expect(levana, isNotEmpty);
      for (final def in levana) {
        expect(def.isRelevant, isNull);
        expect(def.defaultEnabled, isFalse);
        expect(def.showHebrewDate, isTrue);
      }
    });
  });
}
