import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_tab_info.dart';
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

  group('מצב שחזור של תוסף', () {
    final store = PluginRestoreStateStore.instance;

    test('נשמר ב-JSON ונזרע מחדש בטעינה', () {
      final tab = ToolTab(
        toolId: 'com.example.plugin',
        title: 'תוסף',
        instanceId: 'i-restore',
      );
      final key = (pluginId: 'com.example.plugin', instanceId: 'i-restore');
      store.set(key, {'screen': 'list'});
      final json = tab.toJson();
      expect(json['pluginRestoreState'], '{"screen":"list"}');

      store.remove(key);
      final restored = ToolTab.fromJson(json);
      expect(restored.instanceId, 'i-restore');
      expect(store.stateOf(key), {'screen': 'list'});

      restored.dispose();
      expect(store.has(key), isFalse);
    });

    // שולחנות עבודה ושחזור טאב שנסגר עוברים דרך clone, שמייצר מזהה חדש.
    test('clone מעביר את המצב למזהה החדש, ושחרור המקור אינו מוחק אותו', () {
      final tab = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
      store.set(
        (pluginId: tab.toolId, instanceId: tab.instanceId),
        {
          'screen': 'list',
        },
      );

      final copy = tab.clone() as ToolTab;
      tab.dispose();

      final copyKey = (pluginId: copy.toolId, instanceId: copy.instanceId);
      expect(store.stateOf(copyKey), {'screen': 'list'});
      expect(copy.toJson()['pluginRestoreState'], '{"screen":"list"}');
      copy.dispose();
      expect(store.has(copyKey), isFalse);
    });

    test('בלי מצב — אין שדה ב-JSON', () {
      final tab = ToolTab(toolId: 'com.example.plugin', title: 'תוסף');
      expect(tab.toJson().containsKey('pluginRestoreState'), isFalse);
    });
  });

  group('כותרת וטולטיפ שהתוסף קבע (ui.setTabInfo)', () {
    ToolTab plugin() =>
        ToolTab(toolId: 'com.example.plugin', title: 'שני טורים');

    test('בלי התאמה — title הוא שם התוסף ואין טולטיפ מותאם', () {
      final tab = plugin();
      expect(tab.title, 'שני טורים');
      expect(tab.baseTitle, 'שני טורים');
      expect(tab.titleOverride, isNull);
      expect(tab.tooltipOverride, isNull);
    });

    test('כותרת מותאמת מחליפה את title אבל baseTitle נשאר שם התוסף', () {
      final tab = plugin();
      final changed = tab.applyPluginTabInfo(
        PluginTabInfoUpdate.parse({'title': 'בראשית א', 'tooltip': 'בראשית'}),
      );
      expect(changed, isTrue);
      expect(tab.title, 'בראשית א');
      expect(tab.baseTitle, 'שני טורים');
      expect(tab.tooltipOverride, 'בראשית');
    });

    test('החלה חוזרת של אותם ערכים אינה "שינוי"', () {
      final tab = plugin();
      final update = PluginTabInfoUpdate.parse({'title': 'בראשית א'});
      expect(tab.applyPluginTabInfo(update), isTrue);
      expect(tab.applyPluginTabInfo(update), isFalse);
    });

    test('עדכון חלקי משאיר את השדה האחר, ו-null מאפס רק את שלו', () {
      final tab = plugin();
      tab.applyPluginTabInfo(
        PluginTabInfoUpdate.parse({'title': 'כותרת', 'tooltip': 'טולטיפ'}),
      );
      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': 'חדשה'}));
      expect(tab.title, 'חדשה');
      expect(tab.tooltipOverride, 'טולטיפ');

      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'tooltip': null}));
      expect(tab.title, 'חדשה');
      expect(tab.tooltipOverride, isNull);

      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': ''}));
      expect(tab.title, 'שני טורים');
    });

    test('שינוי title הרגיל (RenameTab) לא נוגע בכותרת המותאמת', () {
      final tab = plugin();
      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': 'מותאמת'}));
      tab.title = 'שם חדש לתוסף';
      expect(tab.title, 'מותאמת');
      expect(tab.baseTitle, 'שם חדש לתוסף');
      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': null}));
      expect(tab.title, 'שם חדש לתוסף');
    });

    test('נשמר ב-JSON, ו-title ב-JSON נשאר שם התוסף', () {
      final tab = plugin();
      tab.applyPluginTabInfo(
        PluginTabInfoUpdate.parse({'title': 'בראשית א', 'tooltip': 'בראשית'}),
      );
      final json = tab.toJson();
      expect(json['title'], 'שני טורים');
      expect(json['titleOverride'], 'בראשית א');
      expect(json['tooltipOverride'], 'בראשית');

      final restored = ToolTab.fromJson(json);
      expect(restored.title, 'בראשית א');
      expect(restored.baseTitle, 'שני טורים');
      expect(restored.tooltipOverride, 'בראשית');
    });

    test('בלי התאמה אין שדות ב-JSON', () {
      final json = plugin().toJson();
      expect(json.containsKey('titleOverride'), isFalse);
      expect(json.containsKey('tooltipOverride'), isFalse);
    });

    test('JSON פגום לא מפיל: ערך שאינו מחרוזת מתעלמים, ארוך נחתך', () {
      final restored = ToolTab.fromJson({
        'type': 'ToolTab',
        'toolId': 'com.example.plugin',
        'title': 'תוסף',
        'titleOverride': 7,
        'tooltipOverride': 'א' * 5000,
      });
      expect(restored.title, 'תוסף');
      expect(restored.tooltipOverride!.length, kMaxPluginTabTooltipLength);
    });

    test('clone משמר כותרת וטולטיפ, ו-baseTitle לא נדרס בכותרת המותאמת', () {
      final tab = plugin();
      tab.applyPluginTabInfo(
        PluginTabInfoUpdate.parse({'title': 'בראשית א', 'tooltip': 'בראשית'}),
      );
      final copy = tab.clone() as ToolTab;
      expect(copy.title, 'בראשית א');
      expect(copy.baseTitle, 'שני טורים');
      expect(copy.tooltipOverride, 'בראשית');
      copy.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': null}));
      expect(copy.title, 'שני טורים');
    });

    test('toTransferJson (גרירה בין חלונות) משמר את ההתאמה', () {
      final tab = plugin();
      tab.applyPluginTabInfo(PluginTabInfoUpdate.parse({'title': 'בראשית א'}));
      final restored = OpenedTab.fromJson(tab.toTransferJson()) as ToolTab;
      expect(restored.instanceId, isNot(tab.instanceId));
      expect(restored.title, 'בראשית א');
    });
  });
}
