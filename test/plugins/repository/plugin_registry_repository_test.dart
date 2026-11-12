import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';

PluginManifest _manifest({String id = 'p', int? toolTabOrder}) {
  return PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {
        'title': id,
        'order': ?toolTabOrder,
      },
    },
  });
}

InstalledPlugin _plugin({
  required String id,
  int? userOrder,
  int? manifestToolTabOrder,
  DateTime? installedAt,
}) {
  return InstalledPlugin(
    pluginId: id,
    name: id,
    version: '1.0.0',
    installPath: '/x/$id',
    entrypointPath: 'index.html',
    enabled: true,
    pinned: true,
    manifest: _manifest(id: id, toolTabOrder: manifestToolTabOrder),
    installedAt: installedAt ?? DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    userOrder: userOrder,
  );
}

/// Fake DB שמיישם רק את המתודות שהטסטים צריכים. שאר השיחות זורקות
/// `NoSuchMethodError` אם יקראו להן בטעות (זה רצוי לאיתור bugs בטסט).
class _FakeDb implements PluginSystemDatabase {
  final List<InstalledPlugin> plugins;
  final List<Map<String, int>> userOrderCalls = [];

  _FakeDb(this.plugins);

  @override
  Future<String?> getNewTabPageOwner() async => plugins.firstOrNull?.pluginId;

  @override
  Future<List<InstalledPlugin>> getAllInstalledPlugins() async =>
      List.of(plugins);

  @override
  Future<bool> hasEnabledPlugin() async => plugins.any((p) => p.enabled);

  @override
  Future<InstalledPlugin?> getInstalledPlugin(String pluginId) async =>
      plugins.where((p) => p.pluginId == pluginId).firstOrNull;

  @override
  Future<void> insertOrUpdatePlugin(InstalledPlugin plugin) async {
    plugins
      ..removeWhere((p) => p.pluginId == plugin.pluginId)
      ..add(plugin);
  }

  @override
  Future<void> updatePluginsUserOrder(Map<String, int> ordering) async {
    userOrderCalls.add(Map.of(ordering));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('PluginRegistryRepository in safe mode', () {
    setUp(() => PluginSafeMode.active.value = true);
    tearDown(PluginSafeMode.resetForTesting);

    test('all runtime reads wait for the safe-mode decision', () async {
      PluginSafeMode.active.value = false;
      final decision = Completer<void>();
      PluginSafeMode.ready = decision.future;
      final repo = PluginRegistryRepository(
        database: _FakeDb([_plugin(id: 'a')]),
      );
      var completed = 0;
      final all = repo.getAllPlugins().then((v) {
        completed++;
        return v;
      });
      final one = repo.getPlugin('a').then((v) {
        completed++;
        return v;
      });
      final enabled = repo.getIsEnabled('a').then((v) {
        completed++;
        return v;
      });
      final owner = repo.getNewTabPageOwner().then((v) {
        completed++;
        return v;
      });
      final anyEnabled = repo.hasEnabledPlugin().then((v) {
        completed++;
        return v;
      });
      await pumpEventQueue();
      expect(completed, 0);
      PluginSafeMode.active.value = true;
      decision.complete();
      expect((await all).single.enabled, isFalse);
      expect((await one)!.enabled, isFalse);
      expect(await enabled, isFalse);
      expect(await owner, isNull);
      expect(await anyEnabled, isFalse);
    });

    test(
      'safe mode suppresses ownership sync and opening without writes',
      () async {
        final fake = _FakeDb([_plugin(id: 'a')]);
        final repo = PluginRegistryRepository(database: fake);
        final registry = PluginNewTabPageRegistry.forTesting(repo);
        final service = PluginNewTabPageService(registry: registry);
        final launcher = PluginPageLauncher.instance;
        final previousNavigator = launcher.navigator;
        final opened = <String>[];
        launcher.navigator = opened.add;
        addTearDown(() {
          launcher.navigator = previousNavigator;
          registry.dispose();
        });
        registry.selectOwner('a');
        await registry.open();
        expect(opened, isEmpty);
        expect(registry.activePluginId, isNull);
        registry.selectOwner('a');
        await service.syncOwner(repo);
        expect(registry.activePluginId, isNull);
        expect(await fake.getNewTabPageOwner(), 'a');
        PluginSafeMode.active.value = false;
        await service.syncOwner(repo);
        await registry.open();
        expect(opened, ['a']);
      },
    );

    test('every plugin reads as disabled', () async {
      final repo = PluginRegistryRepository(
        database: _FakeDb([_plugin(id: 'a'), _plugin(id: 'b')]),
      );

      expect((await repo.getAllPlugins()).map((p) => p.enabled), [
        false,
        false,
      ]);
      expect((await repo.getPlugin('a'))!.enabled, isFalse);
      expect(await repo.getIsEnabled('a'), isFalse);
      expect(await repo.hasEnabledPlugin(), isFalse);
    });

    test('saving keeps the stored enabled flag', () async {
      final fake = _FakeDb([_plugin(id: 'a')]);
      final repo = PluginRegistryRepository(database: fake);

      final plugin = await repo.getPlugin('a');
      await repo.savePlugin(plugin!.copyWith(userOrder: 3));

      final stored = fake.plugins.single;
      expect(stored.enabled, isTrue);
      expect(stored.userOrder, 3);
    });

    test('the stored choice is shown and can be changed', () async {
      final fake = _FakeDb([_plugin(id: 'a')]);
      final repo = PluginRegistryRepository(database: fake);

      final plugin = (await repo.getPlugin('a'))!;
      expect(plugin.enabled, isFalse);
      expect(plugin.savedEnabled, isTrue);

      await repo.saveEnabledChoice('a', false);
      expect(fake.plugins.single.enabled, isFalse);
      expect((await repo.getPlugin('a'))!.savedEnabled, isFalse);
    });

    test('turning safe mode off restores the stored state', () async {
      final repo = PluginRegistryRepository(
        database: _FakeDb([_plugin(id: 'a')]),
      );
      PluginSafeMode.active.value = false;

      expect(await repo.getIsEnabled('a'), isTrue);
      expect(await repo.hasEnabledPlugin(), isTrue);
    });
  });

  group('PluginRegistryRepository.reorderPlugins', () {
    test('maps an ordered list of ids to {id: 0, id: 1, ...}', () async {
      final fake = _FakeDb([]);
      final repo = PluginRegistryRepository(database: fake);

      await repo.reorderPlugins(['c.id', 'a.id', 'b.id']);

      expect(fake.userOrderCalls, hasLength(1));
      expect(fake.userOrderCalls.single, {
        'c.id': 0,
        'a.id': 1,
        'b.id': 2,
      });
    });

    test(
      'empty list still forwards an empty map (caller decides no-op)',
      () async {
        final fake = _FakeDb([]);
        final repo = PluginRegistryRepository(database: fake);

        await repo.reorderPlugins([]);

        expect(fake.userOrderCalls, hasLength(1));
        expect(fake.userOrderCalls.single, isEmpty);
      },
    );

    test('a single id gets order 0', () async {
      final fake = _FakeDb([]);
      final repo = PluginRegistryRepository(database: fake);

      await repo.reorderPlugins(['only.one']);

      expect(fake.userOrderCalls.single, {'only.one': 0});
    });
  });

  group('PluginRegistryRepository.getAllPlugins sorting', () {
    test(
      'orders by effectiveToolTabOrder (manifest order when no userOrder)',
      () async {
        final fake = _FakeDb([
          _plugin(id: 'late', manifestToolTabOrder: 900),
          _plugin(id: 'early', manifestToolTabOrder: 100),
          _plugin(id: 'mid', manifestToolTabOrder: 500),
        ]);
        final repo = PluginRegistryRepository(database: fake);

        final result = await repo.getAllPlugins();

        expect(result.map((p) => p.pluginId).toList(), [
          'early',
          'mid',
          'late',
        ]);
      },
    );

    test(
      'userOrder beats manifest order (moves to the user-order range)',
      () async {
        // 'b' has the lowest manifest order (50) but no userOrder.
        // 'a' has high manifest order (9999) but userOrder=0 → ends up
        // at offset+0=1000 — AFTER 'b' (50), not before.
        final fake = _FakeDb([
          _plugin(id: 'a', userOrder: 0, manifestToolTabOrder: 9999),
          _plugin(id: 'b', manifestToolTabOrder: 50),
        ]);
        final repo = PluginRegistryRepository(database: fake);

        final result = await repo.getAllPlugins();

        expect(
          result.map((p) => p.pluginId).toList(),
          ['b', 'a'],
          reason:
              'plugins without userOrder (relying on manifest) sort by '
              'manifest order; userOrder is offset by 1000 to move them into '
              'the dedicated manual-order range',
        );
      },
    );

    test(
      'between two plugins with userOrder, the lower index comes first',
      () async {
        final fake = _FakeDb([
          _plugin(id: 'second', userOrder: 1),
          _plugin(id: 'first', userOrder: 0),
          _plugin(id: 'third', userOrder: 2),
        ]);
        final repo = PluginRegistryRepository(database: fake);

        final result = await repo.getAllPlugins();

        expect(result.map((p) => p.pluginId).toList(), [
          'first',
          'second',
          'third',
        ]);
      },
    );

    test('empty plugin list returns empty', () async {
      final fake = _FakeDb([]);
      final repo = PluginRegistryRepository(database: fake);
      expect(await repo.getAllPlugins(), isEmpty);
    });

    test('ties on effectiveToolTabOrder are broken deterministically by '
        'installedAt then pluginId (the common case: many plugins with the '
        'default manifest order of 900)', () async {
      // הקלט מסודר *הפוך* מהצפי כדי לוודא שהמיון באמת רץ.
      final fake = _FakeDb([
        _plugin(
          id: 'z',
          manifestToolTabOrder: 900,
          installedAt: DateTime.utc(2026, 1, 3),
        ),
        _plugin(
          id: 'a',
          manifestToolTabOrder: 900,
          installedAt: DateTime.utc(2026, 1, 1),
        ),
        _plugin(
          id: 'm',
          manifestToolTabOrder: 900,
          installedAt: DateTime.utc(2026, 1, 2),
        ),
      ]);
      final repo = PluginRegistryRepository(database: fake);

      final result = await repo.getAllPlugins();

      expect(
        result.map((p) => p.pluginId).toList(),
        ['a', 'm', 'z'],
        reason: 'tied orders must be broken by installedAt (ascending)',
      );
    });

    test('identical installedAt falls back to pluginId — fully deterministic '
        'even when timestamps collide', () async {
      final sameTime = DateTime.utc(2026, 1, 1, 12);
      final fake = _FakeDb([
        _plugin(id: 'beta', manifestToolTabOrder: 900, installedAt: sameTime),
        _plugin(id: 'alpha', manifestToolTabOrder: 900, installedAt: sameTime),
      ]);
      final repo = PluginRegistryRepository(database: fake);

      final result = await repo.getAllPlugins();

      expect(
        result.map((p) => p.pluginId).toList(),
        ['alpha', 'beta'],
        reason: 'tied orders + tied installedAt → pluginId asc',
      );
    });
  });

  group('PluginRegistryRepository.getNextUserOrderForNewPlugin', () {
    test('returns null when no plugin has a manual userOrder', () async {
      final fake = _FakeDb([
        _plugin(id: 'a'),
        _plugin(id: 'b'),
      ]);
      final repo = PluginRegistryRepository(database: fake);

      expect(
        await repo.getNextUserOrderForNewPlugin(),
        isNull,
        reason: 'no manual order yet → new plugin keeps manifest order',
      );
    });

    test(
      'returns null when the plugin list is empty (very first install)',
      () async {
        final fake = _FakeDb([]);
        final repo = PluginRegistryRepository(database: fake);

        expect(await repo.getNextUserOrderForNewPlugin(), isNull);
      },
    );

    test('returns max(userOrder) + 1 so a freshly installed plugin lands '
        'AFTER the user-ordered block — not before (which is what would '
        'happen with userOrder=null, since manifest.toolTabOrder defaults '
        'to 900 which is below the 1000 offset)', () async {
      final fake = _FakeDb([
        _plugin(id: 'a', userOrder: 0),
        _plugin(id: 'b', userOrder: 1),
        _plugin(id: 'c', userOrder: 2),
      ]);
      final repo = PluginRegistryRepository(database: fake);

      expect(await repo.getNextUserOrderForNewPlugin(), 3);
    });

    test('ignores plugins with userOrder=null when computing the max — '
        'mixed state (some sorted, some not) still picks the highest '
        'manual value', () async {
      final fake = _FakeDb([
        _plugin(id: 'a', userOrder: 5),
        _plugin(id: 'b'), // userOrder=null
        _plugin(id: 'c', userOrder: 2),
      ]);
      final repo = PluginRegistryRepository(database: fake);

      expect(await repo.getNextUserOrderForNewPlugin(), 6);
    });
  });
}
