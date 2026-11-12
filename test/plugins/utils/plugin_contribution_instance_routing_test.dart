import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_runtime.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/plugins/utils/plugin_toolbar_actions.dart';

class _EnabledRepo extends Fake implements PluginRegistryRepository {
  @override
  Future<bool> getIsEnabled(String pluginId) async => true;

  @override
  Future<bool?> getPermission(String pluginId, String permission) async => true;
}

class _FakeController extends Fake implements InAppWebViewController {
  final List<String> jsEvents = [];

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    jsEvents.add(source);
    return null;
  }
}

void main() {
  const pid = 'routing.contrib.plugin';
  const i1 = 'instance-1';
  const i2 = 'instance-2';

  final dispatcher = PluginRuntimeDispatcher.instance;

  PluginInstanceKey key(String instanceId) => (
    pluginId: pid,
    instanceId: instanceId,
  );

  Iterable<String> clicksOf(_FakeController controller) =>
      controller.jsEvents.where((e) => e.contains('itemId'));

  setUp(() {
    dispatcher.resetVisibilityForTesting();
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    dispatcher.repositoryForTesting = _EnabledRepo();
    dispatcher.invalidatePlugin(pid);
  });

  tearDown(() {
    dispatcher.unregisterController(pid, instanceId: i1);
    dispatcher.unregisterController(pid, instanceId: i2);
    dispatcher.unregisterController(
      pid,
      instanceId: PluginInstanceIds.background,
    );
    ContextMenuRegistry.instance.removeAll(pid);
    PluginToolbarRegistry.instance.removeAll(pid);
    dispatcher.repositoryForTesting = PluginRegistryRepository();
    debugDefaultTargetPlatformOverride = null;
  });

  group('תפריט הקשר — ריבוי מופעים', () {
    test('שני מופעים רושמים אותו itemId — מוצג פעם אחת', () {
      ContextMenuRegistry.instance.registerPayload(pid, {
        'id': 'act',
        'title': 'פעולה',
      }, instanceId: i1);
      ContextMenuRegistry.instance.registerPayload(pid, {
        'id': 'act',
        'title': 'פעולה',
      }, instanceId: i2);

      expect(
        ContextMenuRegistry.instance.getAll().where((r) => r.$1 == pid),
        hasLength(1),
      );
      expect(ContextMenuRegistry.instance.instanceIdsForItem(pid, 'act'), [
        i1,
        i2,
      ]);
    });

    test('הלחיצה מנותבת למופע הקדמי הגלוי, לא לרקע ולא לטאב השני', () async {
      final a = _FakeController();
      final b = _FakeController();
      final bg = _FakeController();
      dispatcher.registerController(pid, a, instanceId: i1);
      dispatcher.registerController(pid, b, instanceId: i2);
      dispatcher.registerController(
        pid,
        bg,
        instanceId: PluginInstanceIds.background,
      );
      for (final instanceId in [PluginInstanceIds.background, i1, i2]) {
        ContextMenuRegistry.instance.registerPayload(pid, {
          'id': 'act',
          'title': 'פעולה',
        }, instanceId: instanceId);
      }
      dispatcher.setVisiblePluginInstances({key(i1)});
      await pumpEventQueue();
      a.jsEvents.clear();

      final record = ContextMenuRegistry.instance
          .getAll()
          .where((r) => r.$1 == pid)
          .single;
      final entry = buildPluginContextMenuEntries(
        records: [record],
        selection: const {'text': 'מסומן'},
      ).single;
      entry.onTap!();
      await pumpEventQueue();

      expect(clicksOf(a), isNotEmpty);
      expect(clicksOf(b), isEmpty);
      expect(clicksOf(bg), isEmpty);
    });

    test('אין מופע גלוי — הלחיצה מנותבת לקדמי האחרון שנרשם', () async {
      final a = _FakeController();
      final b = _FakeController();
      dispatcher.registerController(pid, a, instanceId: i1);
      dispatcher.registerController(pid, b, instanceId: i2);
      for (final instanceId in [i1, i2]) {
        ContextMenuRegistry.instance.registerPayload(pid, {
          'id': 'act',
          'title': 'פעולה',
        }, instanceId: instanceId);
      }

      final record = ContextMenuRegistry.instance
          .getAll()
          .where((r) => r.$1 == pid)
          .single;
      final entry = buildPluginContextMenuEntries(
        records: [record],
        selection: const {'text': 'מסומן'},
      ).single;
      entry.onTap!();
      await pumpEventQueue();

      expect(clicksOf(a), isEmpty);
      expect(clicksOf(b), isNotEmpty);
    });

    test('רק מופע הרקע רשם — הדיספצ׳ר בוחר את הרקע בעצמו', () async {
      final bg = _FakeController();
      dispatcher.registerController(
        pid,
        bg,
        instanceId: PluginInstanceIds.background,
      );
      ContextMenuRegistry.instance.registerPayload(pid, {
        'id': 'act',
        'title': 'פעולה',
      }, instanceId: PluginInstanceIds.background);

      final record = ContextMenuRegistry.instance
          .getAll()
          .where((r) => r.$1 == pid)
          .single;
      final entry = buildPluginContextMenuEntries(
        records: [record],
        selection: const {'text': 'מסומן'},
      ).single;
      entry.onTap!();
      await pumpEventQueue();

      expect(clicksOf(bg), isNotEmpty);
    });

    test('סגירת מופע אחד (removeInstance) אינה מרוקנת את התפריט', () async {
      final b = _FakeController();
      dispatcher.registerController(pid, b, instanceId: i2);
      for (final instanceId in [i1, i2]) {
        ContextMenuRegistry.instance.registerPayload(pid, {
          'id': 'act',
          'title': 'פעולה',
        }, instanceId: instanceId);
      }

      ContextMenuRegistry.instance.removeInstance(key(i1));

      final records = ContextMenuRegistry.instance.getAll().where(
        (r) => r.$1 == pid,
      );
      expect(records, hasLength(1));

      final entry = buildPluginContextMenuEntries(
        records: records.toList(),
        selection: const {'text': 'מסומן'},
      ).single;
      entry.onTap!();
      await pumpEventQueue();
      expect(clicksOf(b), isNotEmpty);
    });

    test('removeAll מנקה את הרישומים של כל המופעים', () {
      for (final instanceId in [i1, i2]) {
        ContextMenuRegistry.instance.registerPayload(pid, {
          'id': 'act',
          'title': 'פעולה',
        }, instanceId: instanceId);
      }

      ContextMenuRegistry.instance.removeAll(pid);

      expect(
        ContextMenuRegistry.instance.getAll().where((r) => r.$1 == pid),
        isEmpty,
      );
    });
  });

  group('שורת הפקדים — ריבוי מופעים', () {
    Map<String, dynamic> toolbarItem() => {
      'id': 'tool',
      'title': 'כלי',
      'icon': 'apps_24_regular',
    };

    test('שני מופעים רושמים אותו פקד — מוצג פעם אחת', () {
      PluginToolbarRegistry.instance.registerPayload(
        pid,
        toolbarItem(),
        instanceId: i1,
      );
      PluginToolbarRegistry.instance.registerPayload(
        pid,
        toolbarItem(),
        instanceId: i2,
      );

      expect(
        PluginToolbarRegistry.instance.getAll().where((r) => r.$1 == pid),
        hasLength(1),
      );
    });

    test('לחיצה בפקד מנותבת למופע הגלוי', () async {
      final a = _FakeController();
      final b = _FakeController();
      dispatcher.registerController(pid, a, instanceId: i1);
      dispatcher.registerController(pid, b, instanceId: i2);
      for (final instanceId in [i1, i2]) {
        PluginToolbarRegistry.instance.registerPayload(
          pid,
          toolbarItem(),
          instanceId: instanceId,
        );
      }
      dispatcher.setVisiblePluginInstances({key(i2)});
      await pumpEventQueue();
      b.jsEvents.clear();

      final action = buildPluginToolbarActions(
        records: PluginToolbarRegistry.instance
            .getAll()
            .where((r) => r.$1 == pid)
            .toList(),
        context: 'reader-text',
        compact: false,
        locationPayload: () async => const {},
      ).single;
      action.onPressed!();
      await pumpEventQueue();

      expect(clicksOf(b), isNotEmpty);
      expect(clicksOf(a), isEmpty);
    });

    test('סגירת מופע אחד אינה מסירה את הפקד של המופע השני', () {
      for (final instanceId in [i1, i2]) {
        PluginToolbarRegistry.instance.registerPayload(
          pid,
          toolbarItem(),
          instanceId: instanceId,
        );
      }

      PluginToolbarRegistry.instance.removeInstance(key(i1));

      expect(
        PluginToolbarRegistry.instance.getAll().where((r) => r.$1 == pid),
        hasLength(1),
      );
    });
  });
}
