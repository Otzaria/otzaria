import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';

const _pluginTable = '''
  CREATE TABLE plugin_installation (
    plugin_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    install_path TEXT NOT NULL,
    entrypoint_path TEXT NOT NULL,
    icon_path TEXT,
    enabled INTEGER NOT NULL,
    pinned INTEGER NOT NULL DEFAULT 1,
    pinned_to_nav_rail INTEGER NOT NULL DEFAULT 0,
    hidden_from_tools INTEGER NOT NULL DEFAULT 0,
    allow_order_before_built_ins_granted INTEGER,
    manifest_json TEXT NOT NULL,
    installed_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    source_type TEXT NOT NULL DEFAULT 'packaged',
    dev_root_path TEXT,
    user_order INTEGER
  )
''';

const _permissionTable = '''
  CREATE TABLE plugin_permission_grant (
    plugin_id TEXT NOT NULL,
    permission TEXT NOT NULL,
    granted INTEGER NOT NULL,
    granted_at TEXT NOT NULL,
    PRIMARY KEY (plugin_id, permission)
  )
''';

void _createPluginDataTables(Database db) {
  db.execute(
    'CREATE TABLE plugin_kv_store (plugin_id TEXT, namespace TEXT, key TEXT, value_json TEXT)',
  );
  db.execute('CREATE TABLE plugin_published_record (plugin_id TEXT)');
}

void main() {
  group('PluginSystemDatabase.applyPluginInstall', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      db.execute(_pluginTable);
      db.execute(_permissionTable);
    });

    tearDown(() => db.close());

    test('התקנה לחנות יוצרת מזהה פנוי ואינה דורסת אותו לאחר מכן', () {
      _createPluginDataTables(db);
      final first = _plugin(version: '1.0.0', permissions: ['reader.open']);
      final second = _plugin(version: '2.0.0', permissions: ['reader.open']);
      PluginSystemDatabase.applyPluginInstall(
        db,
        first,
        {'reader.open': false},
        requireNewInstallation: true,
      );
      expect(
        () => PluginSystemDatabase.applyPluginInstall(
          db,
          second,
          {'reader.open': true},
          requireNewInstallation: true,
        ),
        throwsA(isA<PluginInstallIdentityInUse>()),
      );
      expect(_version(db), '1.0.0');
      expect(_grants(db), {'reader.open': false});
    });

    test('הענקת תיקייה שמורה ללא התקנה קודמת אינה עוברת לתוסף חדש', () {
      _createPluginDataTables(db);
      final plugin = _plugin(version: '1.0.0', permissions: []);
      db.execute('INSERT INTO plugin_kv_store VALUES (?, ?, ?, ?)', [
        plugin.pluginId,
        '_internal',
        'user_folder_grants',
        '[]',
      ]);
      expect(
        () => PluginSystemDatabase.applyPluginInstall(
          db,
          plugin,
          const {},
          requireNewInstallation: true,
        ),
        throwsA(isA<PluginInstallIdentityInUse>()),
      );
      expect(db.select('SELECT * FROM plugin_installation'), isEmpty);
      expect(db.select('SELECT * FROM plugin_kv_store'), hasLength(1));
    });

    test('שדרוג מותנה של רשומה ללא שינוי שומר הרשאות', () {
      final previous = _plugin(version: '1.0.0', permissions: ['reader.open']);
      PluginSystemDatabase.applyPluginInstall(db, previous, {
        'reader.open': false,
      });
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(
          version: '2.0.0',
          permissions: ['reader.open', 'network.access'],
        ),
        {'reader.open': false, 'network.access': true},
        expectedPlugin: previous,
        expectedPermissions: {'reader.open': false},
      );
      expect(_version(db), '2.0.0');
      expect(_grants(db), {'reader.open': false, 'network.access': true});
    });

    for (final mutation in [
      'remove',
      'reinstall',
      'development',
      'order',
      'permission',
    ]) {
      test('שדרוג מותנה מבוטל אחרי שינוי $mutation מחיבור SQLite אחר', () {
        final root = Directory.systemTemp.createTempSync('otzaria_upgrade_db_');
        final path = '${root.path}/plugins.db';
        final first = sqlite3.open(path);
        final second = sqlite3.open(path);
        addTearDown(() {
          second.close();
          first.close();
          root.deleteSync(recursive: true);
        });
        first.execute(_pluginTable);
        first.execute(_permissionTable);
        final previous = _plugin(
          version: '1.0.0',
          permissions: ['network.access'],
        );
        PluginSystemDatabase.applyPluginInstall(first, previous, {
          'network.access': true,
        });
        switch (mutation) {
          case 'remove':
            second.execute('DELETE FROM plugin_installation');
            second.execute('DELETE FROM plugin_permission_grant');
          case 'reinstall':
            second.execute(
              "UPDATE plugin_installation SET install_path = '/plugins/reinstalled'",
            );
          case 'development':
            second.execute(
              "UPDATE plugin_installation SET source_type = 'development', dev_root_path = '/dev'",
            );
          case 'order':
            second.execute('UPDATE plugin_installation SET user_order = 7');
          case 'permission':
            second.execute('UPDATE plugin_permission_grant SET granted = 0');
        }
        final rows = second
            .select('SELECT * FROM plugin_installation')
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        final grants = _grants(second);
        expect(
          () => PluginSystemDatabase.applyPluginInstall(
            first,
            _plugin(version: '2.0.0', permissions: ['network.access']),
            {'network.access': true},
            expectedPlugin: previous,
            expectedPermissions: {'network.access': true},
          ),
          throwsStateError,
        );
        expect(
          first
              .select('SELECT * FROM plugin_installation')
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
          rows,
        );
        expect(_grants(first), grants);
        second.execute(
          'INSERT INTO plugin_permission_grant VALUES (?, ?, 0, ?)',
          ['other', 'network.access', '2026'],
        );
      });
    }

    test('snapshot SQLite ישן אינו יכול לדרוס החלטה מחיבור אחר', () {
      final root = Directory.systemTemp.createTempSync(
        'otzaria_upgrade_snapshot_',
      );
      final first = sqlite3.open('${root.path}/plugins.db');
      final second = sqlite3.open('${root.path}/plugins.db');
      addTearDown(() {
        second.close();
        first.close();
        root.deleteSync(recursive: true);
      });
      first.execute('PRAGMA journal_mode = WAL');
      first.execute(_pluginTable);
      first.execute(_permissionTable);
      final previous = _plugin(
        version: '1.0.0',
        permissions: ['network.access'],
      );
      PluginSystemDatabase.applyPluginInstall(first, previous, {
        'network.access': true,
      });
      first.execute('BEGIN');
      first.select('SELECT * FROM plugin_installation');
      second.execute('UPDATE plugin_permission_grant SET granted = 0');
      expect(
        () => PluginSystemDatabase.applyPluginInstall(
          first,
          _plugin(version: '2.0.0', permissions: ['network.access']),
          {'network.access': true},
          expectedPlugin: previous,
          expectedPermissions: {'network.access': true},
        ),
        throwsA(isA<SqliteException>()),
      );
      first.execute('ROLLBACK');
      expect(_version(first), '1.0.0');
      expect(_grants(first), {'network.access': false});
    });

    test('החלטת כפתור מארח נשמרת בעדכון ואינה נדרסת ממניפסט', () {
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(version: '1.0.0', permissions: const ['navigation.write']),
        const {'navigation.write': true},
      );
      db.execute('INSERT INTO plugin_permission_grant VALUES (?, ?, 0, ?)', [
        'test.atomic.install',
        pluginNewTabPagePermission,
        '2026-01-01',
      ]);
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(version: '2.0.0', permissions: const ['navigation.write']),
        const {'navigation.write': true, pluginNewTabPagePermission: true},
      );
      expect(_grants(db)[pluginNewTabPagePermission], isFalse);
    });

    test('עדכון שמסיר ניווט מסיר גם intent ישן לכפתור', () {
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(version: '1.0.0', permissions: const ['navigation.write']),
        const {'navigation.write': true},
      );
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, 'test.atomic.install'),
        isTrue,
      );
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(version: '2.0.0', permissions: const []),
        const {},
      );
      expect(_grants(db), isEmpty);
    });

    test('עדכון ששולל ניווט שומר intent אך שולל גם את הכפתור', () {
      final plugin = _plugin(
        version: '1.0.0',
        permissions: const ['navigation.write'],
      );
      PluginSystemDatabase.applyPluginInstall(db, plugin, const {
        'navigation.write': true,
      });
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, plugin.pluginId),
        isTrue,
      );
      PluginSystemDatabase.applyPluginInstall(
        db,
        plugin.copyWith(version: '2.0.0'),
        const {'navigation.write': false},
      );
      expect(_grants(db), {
        'navigation.write': false,
        pluginNewTabPagePermission: false,
      });
      expect(PluginSystemDatabase.readNewTabPageOwner(db), isNull);
    });

    test('שלילת ניווט מנקה את grant הכפתור ואינה יוצרת intent חדש', () {
      for (final id in ['owner', 'navigationOnly']) {
        PluginSystemDatabase.applyPluginInstall(
          db,
          _plugin(
            version: '1.0.0',
            permissions: const ['navigation.write'],
          ).copyWith(pluginId: id),
          const {'navigation.write': true},
        );
      }
      expect(PluginSystemDatabase.applyNewTabPageGrant(db, 'owner'), isTrue);
      for (final id in ['owner', 'navigationOnly']) {
        PluginSystemDatabase.applyPermission(db, id, 'navigation.write', false);
      }
      final buttons = db.select(
        'SELECT plugin_id, granted FROM plugin_permission_grant WHERE permission = ?',
        [pluginNewTabPagePermission],
      );
      expect(buttons, hasLength(1));
      expect(buttons.single['plugin_id'], 'owner');
      expect(buttons.single['granted'], 0);
      expect(PluginSystemDatabase.readNewTabPageOwner(db), isNull);
    });

    test('בחירת בעלים מחליפה רק את הרשאת הכפתור באותה טרנזקציה', () {
      for (final id in ['a', 'b']) {
        final plugin = _plugin(
          version: '1.0.0',
          permissions: const ['navigation.write'],
        );
        PluginSystemDatabase.applyPluginInstall(
          db,
          plugin.copyWith(pluginId: id),
          const {'navigation.write': true},
        );
      }
      expect(PluginSystemDatabase.applyNewTabPageGrant(db, 'a'), isTrue);
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, 'b', expectedOwner: 'a'),
        isTrue,
      );
      final grants = db.select(
        'SELECT plugin_id, granted FROM plugin_permission_grant WHERE permission = ?',
        [pluginNewTabPagePermission],
      );
      expect(
        {for (final row in grants) row['plugin_id']: row['granted']},
        {'a': 0, 'b': 1},
      );
      expect(
        db.select(
          "SELECT 1 FROM plugin_permission_grant WHERE permission = 'navigation.write' AND granted = 1",
        ),
        hasLength(2),
      );
    });

    test('הסכמה לבעלים ישן אינה דורסת בחירה חדשה', () {
      for (final id in ['a', 'b']) {
        PluginSystemDatabase.applyPluginInstall(
          db,
          _plugin(
            version: '1.0.0',
            permissions: const ['navigation.write'],
          ).copyWith(pluginId: id),
          const {'navigation.write': true},
        );
      }
      expect(PluginSystemDatabase.applyNewTabPageGrant(db, 'a'), isTrue);
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, 'b', expectedOwner: null),
        isFalse,
      );
      expect(
        db.select(
          'SELECT plugin_id FROM plugin_permission_grant WHERE permission = ? AND granted = 1',
          [pluginNewTabPagePermission],
        ).single['plugin_id'],
        'a',
      );
    });

    test('תוסף שנחסם או הושבת בזמן ההענקה אינו מקבל בעלות', () {
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(version: '1.0.0', permissions: const ['navigation.write']),
        const {'navigation.write': true},
      );
      db.execute('INSERT INTO plugin_permission_grant VALUES (?, ?, 0, ?)', [
        'test.atomic.install',
        pluginNewTabPagePermission,
        '2026-01-01',
      ]);
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(
          db,
          'test.atomic.install',
          allowPreviouslyDenied: false,
        ),
        isFalse,
      );
      db.execute('UPDATE plugin_installation SET enabled = 0');
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, 'test.atomic.install'),
        isFalse,
      );
      db.execute('UPDATE plugin_installation SET enabled = 1');
      db.execute(
        "UPDATE plugin_permission_grant SET granted = 0 WHERE permission = 'navigation.write'",
      );
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, 'test.atomic.install'),
        isFalse,
      );
    });

    test('כשל הענקה מחזיר גם את הרשאת הבעלים הקודם', () {
      for (final id in ['a', 'b']) {
        final plugin = _plugin(
          version: '1.0.0',
          permissions: const ['navigation.write'],
        );
        PluginSystemDatabase.applyPluginInstall(
          db,
          plugin.copyWith(pluginId: id),
          const {'navigation.write': true},
        );
      }
      PluginSystemDatabase.applyNewTabPageGrant(db, 'a');
      db.execute(
        "CREATE TRIGGER reject_new_tab BEFORE INSERT ON plugin_permission_grant WHEN NEW.plugin_id = 'b' AND NEW.permission = 'plugin.new_tab_page' BEGIN SELECT RAISE(ABORT, 'fail'); END",
      );
      expect(
        () => PluginSystemDatabase.applyNewTabPageGrant(
          db,
          'b',
          expectedOwner: 'a',
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        db.select(
          'SELECT granted FROM plugin_permission_grant WHERE plugin_id = ? AND permission = ?',
          ['a', pluginNewTabPagePermission],
        ).single['granted'],
        1,
      );
    });

    test('שחזור גיבוי אינו מחליף בעלים שנבחר מאז', () {
      for (final id in ['a', 'b']) {
        PluginSystemDatabase.applyPluginInstall(
          db,
          _plugin(
            version: '1.0.0',
            permissions: const ['navigation.write'],
          ).copyWith(pluginId: id),
          const {'navigation.write': true},
        );
      }
      PluginSystemDatabase.applyNewTabPageGrant(db, 'b');
      db.execute('CREATE TABLE plugin_kv_store (plugin_id TEXT)');
      db.execute('CREATE TABLE plugin_published_record (plugin_id TEXT)');
      PluginSystemDatabase.applyPluginAuxData(db, 'a', {
        'permissions': [
          {
            'permission': 'navigation.write',
            'granted': 1,
            'granted_at': '2026-01-01',
          },
          {
            'permission': pluginNewTabPagePermission,
            'granted': 1,
            'granted_at': '2026-01-01',
          },
        ],
      });
      expect(PluginSystemDatabase.readNewTabPageOwner(db), 'b');
      expect(
        db.select(
          'SELECT granted FROM plugin_permission_grant WHERE plugin_id = ? AND permission = ?',
          ['a', pluginNewTabPagePermission],
        ).single['granted'],
        0,
      );
    });

    test('גיבוי ישן אינו מחזיר כפתור אחרי שהמניפסט הסיר ניווט', () {
      final disabledOwner = _plugin(
        version: '1.0.0',
        permissions: const ['navigation.write'],
      ).copyWith(pluginId: 'disabledOwner');
      PluginSystemDatabase.applyPluginInstall(db, disabledOwner, const {
        'navigation.write': true,
      });
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, disabledOwner.pluginId),
        isTrue,
      );
      db.execute('UPDATE plugin_installation SET enabled = 0');
      final plugin = _plugin(version: '2.0.0', permissions: const []);
      PluginSystemDatabase.applyPluginInstall(db, plugin, const {});
      db.execute('CREATE TABLE plugin_kv_store (plugin_id TEXT)');
      db.execute('CREATE TABLE plugin_published_record (plugin_id TEXT)');
      final backup = {
        'permissions': [
          for (final permission in [
            'navigation.write',
            pluginNewTabPagePermission,
          ])
            {
              'permission': permission,
              'granted': 1,
              'granted_at': '2026-01-01',
            },
        ],
      };
      PluginSystemDatabase.applyPluginAuxData(db, plugin.pluginId, backup);
      expect(
        db.select(
          'SELECT granted FROM plugin_permission_grant WHERE plugin_id = ? AND permission = ?',
          [disabledOwner.pluginId, pluginNewTabPagePermission],
        ).single['granted'],
        1,
      );
      expect(_grants(db)[pluginNewTabPagePermission], isFalse);
      expect(PluginSystemDatabase.readNewTabPageOwner(db), isNull);
      expect(
        PluginSystemDatabase.applyNewTabPageGrant(db, plugin.pluginId),
        isFalse,
      );
      db.execute('UPDATE plugin_permission_grant SET granted = 1');
      expect(PluginSystemDatabase.readNewTabPageOwner(db), isNull);
    });

    test('שני חלונות רואים בעלות DB ואינם פותחים תוסף שהרשאתו נשללה', () async {
      for (final id in ['a', 'b']) {
        PluginSystemDatabase.applyPluginInstall(
          db,
          _plugin(
            version: '1.0.0',
            permissions: const ['navigation.write'],
          ).copyWith(pluginId: id),
          const {'navigation.write': true},
        );
      }
      final repo = _SqlRepository(db);
      final first = PluginNewTabPageRegistry.forTesting(repo);
      final second = PluginNewTabPageRegistry.forTesting(repo);
      final firstService = PluginNewTabPageService(registry: first);
      final secondService = PluginNewTabPageService(registry: second);
      final opened = <String>[];
      final launcher = PluginPageLauncher.instance;
      final originalNavigator = launcher.navigator;
      launcher.navigator = opened.add;
      addTearDown(() {
        launcher.navigator = originalNavigator;
        launcher.markPageClosed('b');
        first.dispose();
        second.dispose();
      });
      expect(
        await firstService.request(
          'a',
          repo,
          onConflict: (_) => fail('unexpected conflict'),
        ),
        isTrue,
      );
      await secondService.syncOwner(repo);
      expect(second.activePluginId, 'a');
      expect(
        await secondService.request('b', repo, onConflict: (_) {}),
        isFalse,
      );
      expect(await secondService.grant('b', repo, expectedOwner: 'a'), isTrue);
      expect(first.activePluginId, 'a');
      expect(await firstService.ownerId(repo), 'b');
      await first.open();
      expect(opened, ['b']);
      expect(first.activePluginId, 'b');
      await repo.setPermission('b', pluginNewTabPagePermission, false);
      await first.open();
      await secondService.syncOwner(repo);
      expect(opened, ['b']);
      expect(first.activePluginId, isNull);
      expect(second.activePluginId, isNull);
    });

    test('שומר תוסף והרשאות true/false באותה פעולה', () {
      final plugin = _plugin(
        version: '1.0.0',
        permissions: const ['app.startup_contributions', 'reader.open'],
      );

      PluginSystemDatabase.applyPluginInstall(db, plugin, const {
        'app.startup_contributions': false,
        'reader.open': true,
      });

      expect(_version(db), '1.0.0');
      expect(_grants(db), {
        'app.startup_contributions': false,
        'reader.open': true,
      });
    });

    test('כשל בכתיבת הרשאה מחזיר גם את התוסף וגם את ההרשאות', () {
      PluginSystemDatabase.applyPluginInstall(
        db,
        _plugin(version: '1.0.0', permissions: const ['app.info.read']),
        const {'app.info.read': true},
      );
      db.execute('''
        CREATE TRIGGER reject_reader_open
        BEFORE INSERT ON plugin_permission_grant
        WHEN NEW.permission = 'reader.open'
        BEGIN
          SELECT RAISE(ABORT, 'forced-fail');
        END
      ''');

      expect(
        () => PluginSystemDatabase.applyPluginInstall(
          db,
          _plugin(
            version: '2.0.0',
            permissions: const ['app.startup_contributions', 'reader.open'],
          ),
          const {
            'app.startup_contributions': false,
            'reader.open': true,
          },
        ),
        throwsA(anything),
      );

      expect(_version(db), '1.0.0');
      expect(_grants(db), {'app.info.read': true});
    });
  });
}

InstalledPlugin _plugin({
  required String version,
  required List<String> permissions,
}) {
  final manifest = PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': 'test.atomic.install',
    'name': 'Atomic Install',
    'version': version,
    'entrypoint': 'index.html',
    'permissions': permissions,
  });
  return InstalledPlugin(
    pluginId: manifest.id,
    name: manifest.name,
    version: manifest.version,
    installPath: '/plugins/${manifest.id}',
    entrypointPath: manifest.entrypoint,
    enabled: true,
    pinned: false,
    manifest: manifest,
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

String _version(Database db) =>
    db.select('SELECT version FROM plugin_installation').first['version']
        as String;

Map<String, bool> _grants(Database db) => {
  for (final row in db.select(
    'SELECT permission, granted FROM plugin_permission_grant',
  ))
    row['permission'] as String: row['granted'] == 1,
};

class _SqlRepository extends Fake implements PluginRegistryRepository {
  final Database db;
  _SqlRepository(this.db);
  @override
  Future<InstalledPlugin?> getPlugin(String id) async {
    final rows = db.select(
      'SELECT * FROM plugin_installation WHERE plugin_id = ?',
      [id],
    );
    return rows.isEmpty ? null : InstalledPlugin.fromDbMap(rows.single);
  }

  @override
  Future<bool?> getPermission(String id, String permission) async {
    final rows = db.select(
      'SELECT granted FROM plugin_permission_grant WHERE plugin_id = ? AND permission = ?',
      [id, permission],
    );
    return rows.isEmpty ? null : rows.single['granted'] == 1;
  }

  @override
  Future<void> setPermission(String id, String permission, bool granted) async {
    db.execute(
      'INSERT OR REPLACE INTO plugin_permission_grant VALUES (?, ?, ?, ?)',
      [id, permission, granted ? 1 : 0, '2026-01-01'],
    );
  }

  @override
  Future<String?> getNewTabPageOwner() async =>
      PluginSystemDatabase.readNewTabPageOwner(db);
  @override
  Future<bool> grantNewTabPage(
    String id, {
    required bool allowPreviouslyDenied,
    required String? expectedOwner,
    required void Function() onGranted,
  }) async {
    final granted = PluginSystemDatabase.applyNewTabPageGrant(
      db,
      id,
      allowPreviouslyDenied: allowPreviouslyDenied,
      expectedOwner: expectedOwner,
    );
    if (granted) onGranted();
    return granted;
  }
}
