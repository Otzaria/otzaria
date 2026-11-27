import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_group.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
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
      await db.movePluginToGroup('a', saved.id);
      expect(await group('א'), saved);
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
      await Future.wait([first, second]);
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
      try {
        expect((await db.getPluginGroups()).single.name, 'א');
      } finally {
        connection.execute('ROLLBACK');
      }
      final external = sqlite3.open(await AppPaths.resolvePluginsDbPath());
      external.execute("UPDATE plugin_group SET name = 'committed'");
      external.close();
      expect((await db.getPluginGroups()).single.name, 'committed');
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
