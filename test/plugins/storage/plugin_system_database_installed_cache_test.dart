import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers/memory_cache_provider.dart';

InstalledPlugin _plugin(String id, {String version = '1.0.0'}) {
  final manifest = PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': 'name-$id',
    'version': version,
    'entrypoint': 'index.html',
    'permissions': [pluginNetworkAccessPermission],
    'contributes': {
      'startup': {
        'toolbarItems': [
          {
            'id': 'menu',
            'children': [
              {'id': 'item'},
            ],
          },
        ],
      },
    },
  });
  return InstalledPlugin(
    pluginId: id,
    name: manifest.name,
    version: version,
    installPath: '/plugins/$id',
    entrypointPath: manifest.entrypoint,
    enabled: true,
    pinned: true,
    manifest: manifest,
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

void main() {
  late Directory tempDir;
  final db = PluginSystemDatabase.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_installed_cache_');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(tempDir.path);
    db.resetForTests();
    for (var i = 0; i < 3; i++) {
      await db.insertOrUpdatePlugin(_plugin('p$i'));
    }
  });

  tearDown(() async {
    db.resetForTests();
    AppPaths.debugOverrideDataRootPath(null);
    await tempDir.delete(recursive: true);
  });

  Future<InstalledPlugin> read(String id) async =>
      (await db.getAllInstalledPlugins()).singleWhere((p) => p.pluginId == id);

  test('קריאה חוזרת בלי כתיבה אינה מפענחת שוב את כל התוספים (#4722)', () async {
    final first = await db.getAllInstalledPlugins();
    final second = await db.getAllInstalledPlugins();

    expect(second, hasLength(3));
    for (var i = 0; i < first.length; i++) {
      expect(second[i], isNot(same(first[i])));
      expect(second[i].installedAt, same(first[i].installedAt));
      expect(second[i].updatedAt, same(first[i].updatedAt));
    }
  });

  test('שינוי הרשימה שהוחזרה אינו משפיע על הקריאה הבאה', () async {
    (await db.getAllInstalledPlugins()).clear();
    expect(await db.getAllInstalledPlugins(), hasLength(3));
  });

  test('שינוי במניפסט המוחזר אינו משנה את התוספים במטמון', () async {
    final first = await read('p1');
    first.manifest.permissions.clear();
    final children =
        first.manifest.startup!.toolbarItems.single['children'] as List;
    (children.single as Map)['id'] = 'changed';

    final second = await read('p1');
    expect(second.manifest.permissions, [pluginNetworkAccessPermission]);
    expect(second.manifest.startup!.toolbarItems.single['children'], [
      {'id': 'item'},
    ]);
  });

  test('קריאה בטרנזקציה שבוטלה אינה נשמרת במטמון', () async {
    final connection = await db.database;
    connection.execute('BEGIN');
    try {
      connection.execute(
        "UPDATE plugin_installation SET version = '9.9.9' WHERE plugin_id = 'p1'",
      );
      expect((await read('p1')).version, '9.9.9');
    } finally {
      connection.execute('ROLLBACK');
    }
    expect((await read('p1')).version, '1.0.0');
  });

  test('כל כתיבה לתוספים או להרשאות נראית בקריאה הבאה', () async {
    await db.getAllInstalledPlugins();

    await db.insertOrUpdatePlugin(_plugin('p0', version: '2.0.0'));
    expect((await read('p0')).version, '2.0.0');

    await db.setPermission('p1', pluginNetworkAccessPermission, true);
    expect((await read('p1')).networkAccessGranted, isTrue);

    await db.updatePluginsUserOrder({'p2': 7});
    expect((await read('p2')).userOrder, 7);

    await db.updatePluginShowInTools('p2', false);
    expect((await read('p2')).showInTools, isFalse);

    await db.deletePlugin('p0');
    expect(
      (await db.getAllInstalledPlugins()).map((p) => p.pluginId),
      isNot(contains('p0')),
    );
  });

  test('כתיבה מחיבור אחר לאותו קובץ נראית בקריאה הבאה', () async {
    await db.getAllInstalledPlugins();
    final other = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    try {
      other.execute(
        "UPDATE plugin_installation SET version = '9.9.9' WHERE plugin_id = 'p1'",
      );
    } finally {
      other.close();
    }
    expect((await read('p1')).version, '9.9.9');
  });

  test('אחרי סגירת המסד נקרא הקובץ מחדש', () async {
    await db.getAllInstalledPlugins();
    await db.close();
    final other = sqlite3.open(await AppPaths.resolvePluginsDbPath());
    try {
      other.execute("DELETE FROM plugin_installation WHERE plugin_id = 'p2'");
    } finally {
      other.close();
    }
    expect(await db.getAllInstalledPlugins(), hasLength(2));
  });
}
