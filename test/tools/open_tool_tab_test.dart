import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/open_tool_tab.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';

void main() {
  const entry = ToolCatalogEntry(
    toolId: 'com.example.plugin',
    label: 'תוסף',
    order: 1,
  );

  group('newToolTabInstance', () {
    test('הטאב נבנה בלי dedupeKey — פתיחתו לא תמקד טאב קיים', () {
      final tab = newToolTabInstance(entry);
      expect(tab.toolId, 'com.example.plugin');
      expect(tab.title, 'תוסף');
      expect(tab.allowMultipleInstances, isTrue);
      expect(tab.dedupeKey, isNull);
    });

    test('כל קריאה מייצרת מופע ריצה חדש', () {
      final a = newToolTabInstance(entry);
      final b = newToolTabInstance(entry);
      expect(a.instanceId, isNot(b.instanceId));
    });
  });

  group('openToolInstanceCount', () {
    test('סופר רק כרטיסיות של אותו כלי, כולל מופעים נוספים', () {
      final tabs = [
        ToolTab(toolId: 'com.example.plugin', title: 'א'),
        newToolTabInstance(entry),
        ToolTab(toolId: 'com.example.other', title: 'ב'),
      ];
      expect(openToolInstanceCount(tabs, 'com.example.plugin'), 2);
      expect(openToolInstanceCount(tabs, 'com.example.other'), 1);
      expect(openToolInstanceCount(tabs, 'com.example.none'), 0);
    });
  });

  group('hasRoomForPluginInstance', () {
    List<ToolTab> instances(int count, {String toolId = 'com.example.plugin'}) =>
        [
          for (var i = 0; i < count; i++)
            ToolTab(toolId: toolId, title: 'א', allowMultipleInstances: true),
        ];

    test('מתחת לתקרה אפשר לפתוח, ובתקרה לא', () {
      expect(
        hasRoomForPluginInstance(
          instances(kMaxPluginToolInstances - 1),
          'com.example.plugin',
        ),
        isTrue,
      );
      expect(
        hasRoomForPluginInstance(
          instances(kMaxPluginToolInstances),
          'com.example.plugin',
        ),
        isFalse,
      );
    });

    test('פתיחות שנשלחו ועדיין אינן ב-state נספרות', () {
      final tabs = instances(kMaxPluginToolInstances - 1);
      expect(
        hasRoomForPluginInstance(tabs, 'com.example.plugin', pending: 1),
        isFalse,
      );
    });

    test('כרטיסיות של תוסף אחר אינן נספרות', () {
      expect(
        hasRoomForPluginInstance(
          instances(kMaxPluginToolInstances, toolId: 'com.example.other'),
          'com.example.plugin',
        ),
        isTrue,
      );
    });

    test('מופעים בחלוניות מפוצלות נספרים', () {
      final panes = instances(kMaxPluginToolInstances - 1);
      final split = CombinedTab(
        rightTab: panes.removeLast(),
        leftTab: ToolTab(
          toolId: 'com.example.plugin',
          title: 'ב',
          allowMultipleInstances: true,
        ),
      );
      // שמונה כרטיסיות רגילות + כרטיסיה מפוצלת בת שני מופעים = עשרה.
      expect(
        hasRoomForPluginInstance([...panes, split], 'com.example.plugin'),
        isFalse,
      );
    });
  });
}
