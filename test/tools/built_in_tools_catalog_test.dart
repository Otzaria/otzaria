import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';

void main() {
  group('kBuiltInToolsCatalog invariants', () {
    test('catalog is non-empty', () {
      // הקטלוג הוא מקור סמכותי לכל המקומות שמציגים כלים מובנים
      // (ToolsScreen, ToolsManagementPanel, main_window_screen nav rail).
      // אם הוא ריק — אין כלים מובנים בכלל ⇒ באג קריטי.
      expect(kBuiltInToolsCatalog, isNotEmpty);
    });

    test('every toolId is unique', () {
      final ids = kBuiltInToolsCatalog.map((m) => m.toolId).toList();
      expect(
        ids.toSet().length,
        ids.length,
        reason:
            'duplicate toolIds would cause both rows to collapse into one '
            'entry in ToolsManagementPanel (selection state mixed up) '
            'and would create duplicate tabs in ToolsScreen',
      );
    });

    test('every toolId starts with the "builtin." namespace', () {
      for (final m in kBuiltInToolsCatalog) {
        expect(
          m.toolId,
          startsWith('builtin.'),
          reason:
              'tool IDs are persisted in SharedPreferences (hidden/pinned '
              'sets) and DB tables; the namespace prevents collisions with '
              'plugin IDs',
        );
      }
    });

    test('every entry has either icon or imageIcon (visual identity)', () {
      for (final m in kBuiltInToolsCatalog) {
        expect(
          m.icon != null || m.imageIcon != null,
          isTrue,
          reason:
              'tool "${m.toolId}" has no visual — it would render as a '
              'blank space in the nav rail and tools tab',
        );
      }
    });

    test('every entry has a non-empty label', () {
      for (final m in kBuiltInToolsCatalog) {
        expect(
          m.label.trim(),
          isNotEmpty,
          reason: 'empty labels make the tool unidentifiable to the user',
        );
      }
    });

    test('orders are unique (no two tools share the same order)', () {
      // המיון נקבע לפי `order`. אם שני כלים חולקים אותו ערך, הסדר ביניהם
      // לא דטרמיניסטי בין הפעלות (ב-Dart, Stable sort שומר על סדר ההכנסה,
      // אבל כאן יש לנו רשימה const אז הסדר מובטח. עדיין: סדר ייחודי ברור
      // יותר לתחזוקה ומבטיח שאפשר להזיז כלי בודד בלי להפיל אחרים).
      final orders = kBuiltInToolsCatalog.map((m) => m.order).toList();
      expect(
        orders.toSet().length,
        orders.length,
        reason: 'duplicate orders cause non-deterministic display order',
      );
    });

    test('orders fit within the built-in range (<1000)', () {
      // userOrderToolTabOffset = 1000 ⇒ תוספים בעלי userOrder מוקצים החל
      // מ-1000+ כדי להישאר *אחרי* הכלים המובנים. אם כלי מובנה מקבל
      // order ≥ 1000, הוא ערבב עם תוספים בלשונית הכלים.
      for (final m in kBuiltInToolsCatalog) {
        expect(
          m.order,
          lessThan(1000),
          reason:
              'built-in tool order must stay below the plugin userOrder '
              'offset (1000); see InstalledPlugin.userOrderToolTabOffset',
        );
      }
    });

    test('shamor_zachor uses imageIcon (regression for P3: it must not be '
        'wrench-icon in the nav rail)', () {
      final shamor = kBuiltInToolsCatalog.firstWhere(
        (m) => m.toolId == 'builtin.shamor_zachor',
      );
      expect(
        shamor.imageIcon,
        isNotNull,
        reason:
            'shamor_zachor uses its own logo image; if this becomes null '
            'the nav rail will fall back to a generic wrench icon (P3 bug)',
      );
      expect(
        shamor.icon,
        isNull,
        reason:
            'when imageIcon is set, icon should be null to make the choice '
            'explicit (NavRailItem prefers imageAsset when both are set, '
            'but having both is confusing)',
      );
    });

    test('המילון הארמי משתמש באייקון האותיות של Otzaria', () {
      final dictionary = kBuiltInToolsCatalog.firstWhere(
        (tool) => tool.toolId == 'builtin.aramaic_dictionary',
      );

      expect(dictionary.icon, OtzariaIcons.beit_behind_alef_24_regular);
      expect(dictionary.iconFilled, OtzariaIcons.beit_behind_alef_24_regular);
    });
  });
}
