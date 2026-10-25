import 'package:flutter_test/flutter_test.dart';
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

    test('instanceId שהוענק נשמר — הקורא יודע לאן למסור אירוע', () {
      final tab = newToolTabInstance(entry, instanceId: 'fixed-id');
      expect(tab.instanceId, 'fixed-id');
    });
  });
}
