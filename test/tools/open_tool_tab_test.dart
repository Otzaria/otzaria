import 'package:flutter_test/flutter_test.dart';
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

    test('התקרה היא עשר כרטיסיות לתוסף', () {
      expect(kMaxPluginToolInstances, 10);
    });
  });
}
