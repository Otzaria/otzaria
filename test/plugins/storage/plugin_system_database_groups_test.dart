import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/plugins/$id',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': id,
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'contributes': {
      'toolTab': {'title': id},
    },
  }),
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = PluginSystemDatabase.instance;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_groups_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    db.resetForTests();
    for (final id in ['a', 'b', 'c']) {
      await db.insertOrUpdatePluginWithPermissions(_plugin(id), {});
    }
  });

  tearDown(() async {
    await db.close();
    db.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  Future<PluginGroup> group(String name) async =>
      (await db.getPluginGroups()).singleWhere((g) => g.name == name);

  test(
    'migrates an existing database idempotently without changing plugins',
    () async {
      await db.setPluginKV('a', 'default', 'kept', '1');
      final connection = await db.database;
      connection.execute('DROP TABLE plugin_group_member');
      connection.execute('DROP TABLE plugin_group');
      await db.close();

      expect(await db.getPluginGroups(), isEmpty);
      await db.close();
      expect(await db.getPluginGroups(), isEmpty);
      expect((await db.getAllInstalledPlugins()).map((p) => p.pluginId), [
        'a',
        'b',
        'c',
      ]);
      expect(await db.getPluginKV('a', 'default', 'kept'), '1');
    },
  );

  test(
    'round trips trimmed names, deduplicated members and empty groups',
    () async {
      await db.createPluginGroup('  לימוד  ', ['b', 'a', 'b', 'missing']);
      await db.createPluginGroup('לשימוש בהמשך', []);
      final saved = await db.getPluginGroups();
      expect(saved.map((g) => g.name), ['לימוד', 'לשימוש בהמשך']);
      expect(saved.first.pluginIds, ['b', 'a']);
      expect(saved.last.pluginIds, isEmpty);
      expect(() => saved.first.pluginIds.add('c'), throwsUnsupportedError);

      await db.close();
      expect(await db.getPluginGroups(), saved);
    },
  );

  test(
    'target-first creation preserves its anchor and invalidates cached order',
    () async {
      await db.insertOrUpdatePlugin(_plugin('d'));
      final cached = await db.getAllInstalledPlugins();
      final snapshot = await db.createPluginGroup('יעד', ['c', 'a']);
      expect(snapshot.groups.single.pluginIds, ['c', 'a']);
      expect(
        snapshot.applyOrderTo(cached).map((p) => p.pluginId),
        ['b', 'c', 'd', 'a'],
      );
      final refreshed = await db.getAllInstalledPlugins();
      refreshed.sort(InstalledPlugin.compareForDisplay);
      expect(refreshed.map((p) => p.pluginId), ['b', 'c', 'd', 'a']);
      expect(refreshed.map((p) => p.userOrder), [0, 1, 2, 3]);
      expect(cached.every((p) => p.userOrder == null), isTrue);
      expect(refreshed.every((p) => p.updatedAt == DateTime.utc(2026)), isTrue);
    },
  );

  test(
    'moving an earlier plugin preserves interleaved and hidden target anchors',
    () async {
      await db.insertOrUpdatePlugin(_plugin('d'));
      await db.insertOrUpdatePlugin(_plugin('e'));
      await db.createPluginGroup('יעד', ['c', 'd']);
      final target = await group('יעד');
      await db.insertOrUpdatePlugin(_plugin('c').copyWith(showInTools: false));
      await db.insertOrUpdatePlugin(_plugin('d').copyWith(enabled: false));
      await db.updatePluginsUserOrder({'a': 0, 'b': 1, 'c': 2, 'd': 3, 'e': 4});
      final snapshot = await db.movePluginToGroup('a', target.id);
      final ordered = snapshot.applyOrderTo(await db.getAllInstalledPlugins());
      expect(ordered.map((p) => p.pluginId), ['b', 'c', 'd', 'e', 'a']);
      expect(
        ordered.where((p) => p.enabled && p.showInTools).map((p) => p.pluginId),
        ['b', 'e', 'a'],
      );
      expect(snapshot.groups.single.pluginIds, ['c', 'd', 'a']);
      expect(ordered.every((p) => p.updatedAt == DateTime.utc(2026)), isTrue);
    },
  );

  test(
    'editing appends only additions while rename and removal keep order',
    () async {
      await db.createPluginGroup('יעד', ['c']);
      final original = await group('יעד');
      final added = await db.updatePluginGroup(
        PluginGroup(id: original.id, name: 'יעד', pluginIds: ['a', 'c']),
        expectedGroup: original,
      );
      expect(added.userOrders, {'b': 0, 'c': 1, 'a': 2});
      final renamed = await db.updatePluginGroup(
        PluginGroup(id: original.id, name: 'שם חדש', pluginIds: ['a', 'c']),
        expectedGroup: added.groups.single,
      );
      expect(renamed.userOrders, added.userOrders);
      final removed = await db.updatePluginGroup(
        PluginGroup(id: original.id, name: 'שם חדש', pluginIds: ['c']),
        expectedGroup: renamed.groups.single,
      );
      expect(removed.userOrders, added.userOrders);
    },
  );

  test(
    'moving and replacing members keeps every plugin in at most one group',
    () async {
      await db.createPluginGroup('א', ['a', 'b']);
      await db.createPluginGroup('ב', ['c']);
      final target = await group('ב');
      await db.movePluginToGroup('a', target.id);
      expect((await group('א')).pluginIds, ['b']);
      expect((await group('ב')).pluginIds, ['c', 'a']);

      await db.updatePluginGroup(
        PluginGroup(id: target.id, name: 'ב', pluginIds: ['b', 'c']),
      );
      expect((await group('א')).pluginIds, isEmpty);
      expect((await group('ב')).pluginIds, ['b', 'c']);
      await db.movePluginToGroup('c', null);
      expect((await group('ב')).pluginIds, ['b']);
      expect(await db.getInstalledPlugin('c'), isNotNull);
    },
  );

  test(
    'repeated drop into the same group does not reorder its members',
    () async {
      await db.createPluginGroup('א', ['a', 'b', 'c']);
      final saved = await group('א');
      final before = await db.getPluginGroupsSnapshot();
      final after = await db.movePluginToGroup('a', saved.id);
      expect(await group('א'), saved);
      expect(after.userOrders, before.userOrders);
    },
  );

  test(
    'grouping never changes installation timestamps or stored plugin data',
    () async {
      await db.setPluginKV('a', 'default', 'kept', '1');
      await db.createPluginGroup('א', ['a', 'b']);
      final first = await group('א');
      await db.updatePluginGroup(
        PluginGroup(id: first.id, name: 'חדש', pluginIds: ['b', 'a']),
        expectedGroup: first,
      );
      for (final plugin in await db.getAllInstalledPlugins()) {
        expect(plugin.updatedAt, DateTime.utc(2026));
      }
      expect(await db.getPluginKV('a', 'default', 'kept'), '1');
    },
  );

  test(
    'upgrades, visibility, disabling and data reset preserve membership',
    () async {
      await db.createPluginGroup('א', ['a', 'b']);
      final saved = await group('א');
      await db.insertOrUpdatePluginWithPermissions(
        _plugin('a').copyWith(version: '2.0.0', enabled: false),
        {},
      );
      await db.updatePluginShowInTools('b', false);
      await db.updatePluginNavRailPinState('b', true);
      await db.clearPluginData('a');
      expect(await group('א'), saved);
    },
  );

  test(
    'deleting a group releases its members without uninstalling them',
    () async {
      await db.createPluginGroup('א', ['a', 'b']);
      await db.setPluginKV('a', 'default', 'kept', '1');
      final saved = await group('א');
      await db.deletePluginGroup(saved.id);

      expect(await db.getPluginGroups(), isEmpty);
      expect(await db.getInstalledPlugin('a'), isNotNull);
      expect(await db.getInstalledPlugin('b'), isNotNull);
      expect(await db.getPluginKV('a', 'default', 'kept'), '1');
      expect(
        (await db.database).select('SELECT * FROM plugin_group_member'),
        isEmpty,
      );
    },
  );

  test(
    'an upgrade prepared before grouping keeps the folder in place',
    () async {
      final previous = (await db.getInstalledPlugin('a'))!;
      final grouped = await db.createPluginGroup('לימוד', ['c', 'a']);
      expect(grouped.userOrders, {'b': 0, 'c': 1, 'a': 2});

      await db.insertOrUpdatePluginWithPermissions(
        previous.copyWith(version: '2.0.0'),
        {},
      );

      expect((await db.getInstalledPlugin('a'))!.version, '2.0.0');
      final after = await db.getPluginGroupsSnapshot();
      expect(after.groups, grouped.groups);
      expect(after.userOrders, grouped.userOrders);
    },
  );

  test(
    'an install uses its initial order and an upgrade preserves null',
    () async {
      await db.insertOrUpdatePluginWithPermissions(
        _plugin('new').copyWith(userOrder: 7),
        {},
      );
      await db.insertOrUpdatePluginWithPermissions(_plugin('default'), {});
      await db.insertOrUpdatePluginWithPermissions(
        _plugin('a').copyWith(version: '2.0.0', userOrder: 9),
        {},
      );
      expect((await db.getInstalledPlugin('new'))!.userOrder, 7);
      expect((await db.getInstalledPlugin('default'))!.userOrder, isNull);
      expect((await db.getInstalledPlugin('a'))!.userOrder, isNull);
    },
  );

  test(
    'uninstall removes membership and retains the empty personal group',
    () async {
      await db.createPluginGroup('א', ['a']);
      await db.deletePlugin('a');
      expect((await group('א')).pluginIds, isEmpty);
      expect(await db.getInstalledPlugin('a'), isNull);
      await db.insertOrUpdatePlugin(_plugin('a'));
      expect((await group('א')).pluginIds, isEmpty);
    },
  );

  test(
    'rejects blank, overlong and duplicate names without partial changes',
    () async {
      expect(() => db.createPluginGroup('   ', ['a']), throwsArgumentError);
      expect(
        () =>
            db.createPluginGroup('א' * (PluginGroup.maxNameLength + 1), ['a']),
        throwsArgumentError,
      );
      await db.createPluginGroup('Study', ['a']);
      await db.createPluginGroup('Other', ['b']);
      final other = await group('Other');
      final before = await db.getPluginGroups();
      await expectLater(
        db.updatePluginGroup(
          PluginGroup(id: other.id, name: ' study ', pluginIds: ['a', 'b']),
        ),
        throwsA(isA<PluginGroupNameInUse>()),
      );
      expect(await db.getPluginGroups(), before);
    },
  );

  test(
    'rejects a stale editor snapshot and an update after deletion',
    () async {
      await db.createPluginGroup('א', ['a']);
      final original = await group('א');
      await db.movePluginToGroup('b', original.id);
      final changed = await group('א');
      final proposed = PluginGroup(
        id: original.id,
        name: 'עריכה',
        pluginIds: ['a', 'c'],
      );
      await expectLater(
        db.updatePluginGroup(proposed, expectedGroup: original),
        throwsA(isA<PluginGroupChanged>()),
      );
      expect(await group('א'), changed);

      await db.deletePluginGroup(original.id);
      await expectLater(
        db.updatePluginGroup(proposed),
        throwsA(isA<PluginGroupChanged>()),
      );
      await expectLater(
        db.movePluginToGroup('c', original.id),
        throwsA(isA<PluginGroupChanged>()),
      );
      expect(await db.getPluginGroups(), isEmpty);
    },
  );

  test(
    'member failure rolls back renaming, moves and previous memberships',
    () async {
      await db.createPluginGroup('מקור', ['a', 'b']);
      await db.createPluginGroup('יעד', ['c']);
      final target = await group('יעד');
      final before = await db.getPluginGroups();
      final orderBefore = (await db.getPluginGroupsSnapshot()).userOrders;
      (await db.database).execute("""
      CREATE TRIGGER reject_b BEFORE INSERT ON plugin_group_member
      WHEN NEW.plugin_id = 'b'
      BEGIN SELECT RAISE(ABORT, 'forced failure'); END
    """);
      await expectLater(
        db.updatePluginGroup(
          PluginGroup(id: target.id, name: 'שם אחר', pluginIds: ['a', 'b']),
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(await db.getPluginGroups(), before);
      expect((await db.getPluginGroupsSnapshot()).userOrders, orderBefore);
    },
  );

  test(
    'rapid delta moves are serialized without losing either addition',
    () async {
      await db.createPluginGroup('א', []);
      final target = await group('א');
      final first = db.movePluginToGroup('a', target.id);
      final second = db.movePluginToGroup('b', target.id);
      expect((await group('א')).pluginIds, ['a', 'b']);
      final snapshots = await Future.wait([first, second]);
      expect(snapshots.first.groups.single.pluginIds, ['a']);
      expect(snapshots.first.userOrders, {'b': 0, 'c': 1, 'a': 2});
      expect(snapshots.last.groups.single.pluginIds, ['a', 'b']);
      expect(snapshots.last.userOrders, {'c': 0, 'a': 1, 'b': 2});
      await db.close();
      expect((await group('א')).pluginIds, ['a', 'b']);
    },
  );

  test(
    'group reads use a worker connection and observe external commits',
    () async {
      await db.createPluginGroup('א', ['a']);
      final connection = await db.database;
      connection.execute('BEGIN');
      connection.execute("UPDATE plugin_group SET name = 'uncommitted'");
      connection.execute(
        "UPDATE plugin_installation SET user_order = 9 WHERE plugin_id = 'a'",
      );
      try {
        final snapshot = await db.getPluginGroupsSnapshot();
        expect(snapshot.groups.single.name, 'א');
        expect(snapshot.userOrders['a'], isNull);
      } finally {
        connection.execute('ROLLBACK');
      }
      final external = sqlite3.open(await AppPaths.resolvePluginsDbPath());
      external.execute('BEGIN');
      external.execute("UPDATE plugin_group SET name = 'committed'");
      external.execute(
        "UPDATE plugin_installation SET user_order = 1 WHERE plugin_id = 'a'",
      );
      external.execute('COMMIT');
      external.close();
      final snapshot = await db.getPluginGroupsSnapshot();
      expect(snapshot.groups.single.name, 'committed');
      expect(snapshot.userOrders['a'], 1);
    },
  );

  test(
    'two blocs sharing a repository receive matching groups and order',
    () async {
      await db.createPluginGroup('יעד', ['c']);
      final target = await group('יעד');
      final repository = PluginRegistryRepository(database: db);
      final first = PluginSystemBloc(repository: repository);
      final second = PluginSystemBloc(repository: repository);
      Future<void> load(PluginSystemBloc bloc) async {
        final plugins = bloc.stream.firstWhere((s) => s is PluginSystemLoaded);
        bloc.add(LoadPlugins());
        await plugins;
        final groups = bloc.stream.firstWhere(
          (s) => s is PluginSystemLoaded && s.groupsLoaded,
        );
        bloc.add(const LoadPluginGroups());
        await groups;
      }

      try {
        await Future.wait([load(first), load(second)]);
        final refreshed = second.stream.firstWhere(
          (s) =>
              s is PluginSystemLoaded &&
              s.groups.single.pluginIds.contains('a'),
        );
        final completion = Completer<void>();
        first.add(
          MovePluginToGroupRequested(
            pluginId: 'a',
            groupId: target.id,
            completion: completion,
          ),
        );
        await completion.future;
        final other = await refreshed as PluginSystemLoaded;
        final saved = first.state as PluginSystemLoaded;
        expect(saved.groups, other.groups);
        expect(saved.plugins.map((p) => p.pluginId), ['b', 'c', 'a']);
        expect(other.plugins.map((p) => p.pluginId), ['b', 'c', 'a']);
        expect(other.plugins.map((p) => p.userOrder), [0, 1, 2]);
        final reordered = second.stream.firstWhere(
          (s) => s is PluginSystemLoaded && s.plugins.first.pluginId == 'a',
        );
        first.add(const ReorderPluginsRequested(['a', 'c', 'b']));
        final otherReordered = await reordered as PluginSystemLoaded;
        expect(otherReordered.groups, saved.groups);
        expect(otherReordered.plugins.map((p) => p.pluginId), ['a', 'c', 'b']);
      } finally {
        await first.close();
        await second.close();
      }
    },
  );

  test('a locked group write leaves the UI isolate responsive', () async {
    await db.createPluginGroup('א', []);
    final target = await group('א');
    final locker = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    locker.execute('BEGIN IMMEDIATE');
    final watch = Stopwatch()..start();
    final write = db.movePluginToGroup('a', target.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    watch.stop();
    locker.execute('ROLLBACK');
    locker.close();
    await write;
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    expect((await group('א')).pluginIds, ['a']);
  });

  test('reordering and grouping share their enqueue order', () async {
    await db.createPluginGroup('יעד', ['c']);
    final target = await group('יעד');
    final before = db.updatePluginsUserOrder({'c': 0, 'b': 1, 'a': 2});
    final move = db.movePluginToGroup('b', target.id);
    final after = db.updatePluginsUserOrder({'a': 0, 'c': 1, 'b': 2});
    await before;
    final moved = await move;
    await after;
    expect(moved.groups.single.pluginIds, ['c', 'b']);
    expect(moved.userOrders, {'c': 0, 'a': 1, 'b': 2});
    final finalSnapshot = await db.getPluginGroupsSnapshot();
    expect(finalSnapshot.groups, moved.groups);
    expect(finalSnapshot.userOrders, {'a': 0, 'c': 1, 'b': 2});
  });

  test('a locked reorder leaves the UI isolate responsive', () async {
    final locker = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    locker.execute('BEGIN IMMEDIATE');
    final watch = Stopwatch()..start();
    final write = db.updatePluginsUserOrder({'c': 0, 'b': 1, 'a': 2});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    watch.stop();
    locker.execute('ROLLBACK');
    locker.close();
    await write;
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    expect((await db.getPluginGroupsSnapshot()).userOrders, {
      'c': 0,
      'b': 1,
      'a': 2,
    });
  });

  test(
    'storage move blocks and resumes group mutations without data loss',
    () async {
      await db.createPluginGroup('א', []);
      final target = await group('א');
      await db.lockForStorageMove('groups');
      var done = false;
      final pending = db
          .movePluginToGroup('a', target.id)
          .then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(done, isFalse);
      db.releaseStorageMove('groups');
      await pending;
      expect((await group('א')).pluginIds, ['a']);
    },
  );

  test(
    'restore scopes replacement and preserves groups outside the backup',
    () async {
      await db.createPluginGroup('מקומית', ['a', 'c']);
      final local = await group('מקומית');
      await db.restorePluginGroups(
        [
          PluginGroup(id: 'restored', name: 'גיבוי', pluginIds: ['a', 'b']),
        ],
        pluginScope: {'a', 'b'},
        keepExisting: false,
      );
      expect((await group('מקומית')).id, local.id);
      expect((await group('מקומית')).pluginIds, ['c']);
      expect((await group('גיבוי')).pluginIds, ['a', 'b']);
    },
  );

  test(
    'merge preserves local memberships and resolves duplicate long names',
    () async {
      final longName = 'א' * PluginGroup.maxNameLength;
      await db.createPluginGroup(longName, ['a']);
      final original = await db.getPluginGroups();
      final incoming = [
        PluginGroup(id: 'other', name: longName, pluginIds: ['a', 'b']),
      ];
      await db.restorePluginGroups(
        incoming,
        pluginScope: {'a', 'b'},
        keepExisting: true,
      );
      final merged = await db.getPluginGroups();
      expect(merged.first, original.single);
      expect(merged.last.id, 'other');
      expect(
        merged.last.name.length,
        lessThanOrEqualTo(PluginGroup.maxNameLength),
      );
      expect(merged.last.name, endsWith(' (2)'));
      expect(merged.last.pluginIds, ['b']);
      await db.restorePluginGroups(
        incoming,
        pluginScope: {'a', 'b'},
        keepExisting: true,
      );
      expect(await db.getPluginGroups(), merged);
    },
  );

  test(
    'failed or excluded plugin restores do not rename or create their groups',
    () async {
      await db.createPluginGroup('שם מקומי', ['a']);
      final before = await db.getPluginGroups();
      await db.restorePluginGroups(
        [
          PluginGroup(id: before.single.id, name: 'שם ישן', pluginIds: ['a']),
          PluginGroup(id: 'failed', name: 'לא שוחזר', pluginIds: ['b']),
          PluginGroup(id: 'empty', name: 'ריקה במקור', pluginIds: []),
        ],
        pluginScope: {},
        keepExisting: false,
      );
      final after = await db.getPluginGroups();
      expect(after.first, before.single);
      expect(after.map((g) => g.id), [before.single.id, 'empty']);
    },
  );
}
