import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

void main() {
  group('ToolTab', () {
    test('מזהה כלי מובנה מול תוסף', () {
      expect(
        ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה').isBuiltIn,
        isTrue,
      );
      expect(
        ToolTab(toolId: 'com.example.plugin', title: 'תוסף').isBuiltIn,
        isFalse,
      );
      expect(
        ToolTab(toolId: 'com.example.plugin', title: 'תוסף').isPlugin,
        isTrue,
      );
    });

    test('dedupeKey שייך לכל כלי', () {
      final calendar = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final plugin = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
      expect(calendar.dedupeKey, 'tool:builtin.calendar');
      expect(plugin.dedupeKey, 'tool:com.example.plugin');
    });

    test('dedupeKey מבוטל כשהטאב נפתח כמופע נוסף', () {
      final plugin = ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      );
      expect(plugin.dedupeKey, isNull);
    });

    test('toJson/fromJson roundtrip', () {
      final builtIn = ToolTab(
        toolId: 'builtin.notes',
        title: 'הערות אישיות',
        isPinned: true,
      );
      final plugin = ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        isPinned: true,
      );

      final restoredBuiltIn = ToolTab.fromJson(builtIn.toJson());
      final restoredPlugin = ToolTab.fromJson(plugin.toJson());

      expect(restoredBuiltIn.dedupeKey, 'tool:builtin.notes');
      expect(restoredPlugin.dedupeKey, 'tool:com.example.plugin');
      expect(restoredBuiltIn.isPinned, isTrue);
      expect(restoredPlugin.isPinned, isTrue);
      expect(restoredBuiltIn.instanceId, builtIn.instanceId);
      expect(restoredPlugin.instanceId, plugin.instanceId);
    });

    test('roundtrip של מופע נוסף משמר את היעדר ה-dedupeKey', () {
      final tab = ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      );
      final restored = ToolTab.fromJson(tab.toJson());
      expect(restored.dedupeKey, isNull);
      expect(restored.allowMultipleInstances, isTrue);
      expect(restored.instanceId, tab.instanceId);
    });

    test('JSON ישן בלי instanceId מקבל מזהה טרי ו-dedupeKey רגיל', () {
      final restored = ToolTab.fromJson({
        'type': 'ToolTab',
        'toolId': 'com.example.plugin',
        'title': 'תוסף',
      });
      expect(restored.instanceId, isNotEmpty);
      expect(restored.dedupeKey, 'tool:com.example.plugin');
      expect(restored.allowMultipleInstances, isFalse);
    });

    test('OpenedTab.fromJson מפענח ToolTab', () {
      final tab = ToolTab(toolId: 'builtin.measurements', title: 'מדות');
      final restored = OpenedTab.fromJson(tab.toJson());
      expect(restored, isA<ToolTab>());
      expect((restored as ToolTab).toolId, 'builtin.measurements');
    });

    test('OpenedTab.fromJson זורק על טיפוס לא מוכר במקום ליצור טאב רפאים', () {
      expect(
        () => OpenedTab.fromJson({'type': 'SomeFutureTab', 'title': 'x'}),
        throwsFormatException,
      );
    });

    test('OpenedTab.fromJson עדיין מפענח טאב חיפוש שמור', () {
      final restored = OpenedTab.fromJson({
        'type': 'SearchingTabWindow',
        'title': 'חיפוש',
        'searchText': 'בראשית',
      });
      expect(restored.title, 'חיפוש');
    });

    // clone חייב להחזיר מופע חדש: workspace_bloc משכפל טאבים בכל החלפת
    // שולחן עבודה, ואובייקט משותף יוצר GlobalObjectKey כפול בעץ.
    test('clone מחזיר מופע נפרד', () {
      final tab = ToolTab(
        toolId: 'builtin.calendar',
        title: 'לוח שנה',
        isPinned: true,
      );
      final cloned = tab.clone();
      expect(identical(cloned, tab), isFalse);
      expect(cloned, isA<ToolTab>());
      expect((cloned as ToolTab).toolId, tab.toolId);
      expect(cloned.isPinned, isTrue);
    });

    // שכפול טאב = מופע ריצה חדש; מזהה משותף היה גורם לשני טאבים
    // להירשם אצל הדיספצ'ר תחת אותו מופע.
    test('clone מייצר instanceId חדש ומשמר allowMultipleInstances', () {
      final tab = ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        allowMultipleInstances: true,
      );
      final cloned = tab.clone() as ToolTab;
      expect(cloned.instanceId, isNot(tab.instanceId));
      expect(cloned.allowMultipleInstances, isTrue);
      expect(cloned.dedupeKey, isNull);
    });

    test('שני טאבים חדשים מקבלים instanceId שונה', () {
      final a = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      final b = ToolTab(toolId: 'builtin.calendar', title: 'לוח שנה');
      expect(a.instanceId, isNot(b.instanceId));
    });

    test('OpenedTab.from משכפל ולא מחזיר את אותו אובייקט', () {
      final tab = ToolTab(toolId: 'builtin.gematria', title: 'גימטריה');
      final copy = OpenedTab.from(tab);
      expect(identical(copy, tab), isFalse);
      expect((copy as ToolTab).toolId, 'builtin.gematria');
    });

    test('כותרת גיבוי לכלי מובנה נגזרת מהקטלוג', () {
      expect(ToolTab.fallbackTitleFor('builtin.calendar'), 'לוח שנה');
      expect(ToolTab.fallbackTitleFor('unknown.plugin'), 'כלי');
    });

    test('fromJson ללא כותרת נופל לכותרת הגיבוי', () {
      final restored = ToolTab.fromJson({
        'type': 'ToolTab',
        'toolId': 'builtin.gematria',
      });
      expect(restored.title, 'גימטריה');
    });
  });
}
