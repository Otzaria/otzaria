import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// סכמת ה-DB *לפני* מיגרציית `pinned_to_nav_rail` — מדמה DB ישן בשטח.
const String _legacyCreateTable = '''
  CREATE TABLE plugin_installation (
    plugin_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    install_path TEXT NOT NULL,
    entrypoint_path TEXT NOT NULL,
    icon_path TEXT,
    enabled INTEGER NOT NULL,
    pinned INTEGER NOT NULL DEFAULT 1,
    manifest_json TEXT NOT NULL,
    installed_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    source_type TEXT NOT NULL DEFAULT 'packaged',
    dev_root_path TEXT
  )
''';

bool _hasColumn(Database db, String column) {
  final cols = db.select('PRAGMA table_info(plugin_installation)').toMapList();
  return cols.any((c) => c['name'] == column);
}

int _readNavRailValue(Database db, String pluginId) {
  final rows = db.select(
    'SELECT pinned_to_nav_rail FROM plugin_installation WHERE plugin_id = ?',
    [pluginId],
  );
  return rows.first['pinned_to_nav_rail'] as int;
}

void _seedLegacyRow(Database db, String pluginId) {
  db.execute(
    'INSERT INTO plugin_installation (plugin_id, name, version, install_path, '
    'entrypoint_path, enabled, pinned, manifest_json, installed_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      pluginId,
      'name-$pluginId',
      '1.0.0',
      '/x/$pluginId',
      'index.html',
      1,
      1,
      '{}',
      '2026-01-01T00:00:00.000Z',
      '2026-01-01T00:00:00.000Z',
    ],
  );
}

void main() {
  group('PluginSystemDatabase.ensureSchemaUpgrades', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
    });

    tearDown(() {
      db.close();
    });

    test('adds pinned_to_nav_rail column when missing on legacy schema', () {
      db.execute(_legacyCreateTable);
      expect(_hasColumn(db, 'pinned_to_nav_rail'), isFalse);

      PluginSystemDatabase.ensureSchemaUpgrades(db);

      expect(_hasColumn(db, 'pinned_to_nav_rail'), isTrue);
    });

    test('existing rows get default value 0 (off) for new column', () {
      db.execute(_legacyCreateTable);
      _seedLegacyRow(db, 'legacy.a');
      _seedLegacyRow(db, 'legacy.b');

      PluginSystemDatabase.ensureSchemaUpgrades(db);

      expect(_readNavRailValue(db, 'legacy.a'), 0);
      expect(
        _readNavRailValue(db, 'legacy.b'),
        0,
        reason: 'pinnedToNavRail must default to OFF for pre-existing rows',
      );
    });

    test(
      'is idempotent — running twice does not throw or duplicate column',
      () {
        db.execute(_legacyCreateTable);

        PluginSystemDatabase.ensureSchemaUpgrades(db);
        // קריאה שנייה לא צריכה לזרוק על ALTER כפול:
        expect(
          () => PluginSystemDatabase.ensureSchemaUpgrades(db),
          returnsNormally,
        );

        final cols = db
            .select('PRAGMA table_info(plugin_installation)')
            .toMapList();
        final navRailCols = cols
            .where((c) => c['name'] == 'pinned_to_nav_rail')
            .toList();
        expect(navRailCols, hasLength(1));
      },
    );

    test('does not modify existing pinned values', () {
      db.execute(_legacyCreateTable);
      _seedLegacyRow(db, 'p');
      // נכריח pinned=0 כדי לוודא שהמיגרציה לא דורסת ערכים קיימים
      db.execute(
        'UPDATE plugin_installation SET pinned = 0 WHERE plugin_id = ?',
        ['p'],
      );

      PluginSystemDatabase.ensureSchemaUpgrades(db);

      final rows = db.select(
        'SELECT pinned, pinned_to_nav_rail FROM plugin_installation WHERE plugin_id = ?',
        ['p'],
      );
      expect(rows.first['pinned'], 0);
      expect(rows.first['pinned_to_nav_rail'], 0);
    });

    test('adds user_order column when missing on legacy schema', () {
      db.execute(_legacyCreateTable);
      expect(_hasColumn(db, 'user_order'), isFalse);

      PluginSystemDatabase.ensureSchemaUpgrades(db);

      expect(_hasColumn(db, 'user_order'), isTrue);
    });

    test(
      'existing rows get NULL for user_order column (no forced default)',
      () {
        db.execute(_legacyCreateTable);
        _seedLegacyRow(db, 'legacy.a');

        PluginSystemDatabase.ensureSchemaUpgrades(db);

        final rows = db.select(
          'SELECT user_order FROM plugin_installation WHERE plugin_id = ?',
          ['legacy.a'],
        );
        expect(
          rows.first['user_order'],
          isNull,
          reason:
              'legacy rows must default to NULL so manifest.toolTabOrder '
              'is used until the user explicitly reorders',
        );
      },
    );

    test('user_order migration is idempotent', () {
      db.execute(_legacyCreateTable);

      PluginSystemDatabase.ensureSchemaUpgrades(db);
      expect(
        () => PluginSystemDatabase.ensureSchemaUpgrades(db),
        returnsNormally,
      );

      final cols = db
          .select('PRAGMA table_info(plugin_installation)')
          .toMapList();
      final userOrderCols = cols
          .where((c) => c['name'] == 'user_order')
          .toList();
      expect(userOrderCols, hasLength(1));
    });

    test('both pinned_to_nav_rail and user_order added together when both '
        'are missing', () {
      db.execute(_legacyCreateTable);
      expect(_hasColumn(db, 'pinned_to_nav_rail'), isFalse);
      expect(_hasColumn(db, 'user_order'), isFalse);

      PluginSystemDatabase.ensureSchemaUpgrades(db);

      expect(_hasColumn(db, 'pinned_to_nav_rail'), isTrue);
      expect(_hasColumn(db, 'user_order'), isTrue);
    });

    test('adds hidden_from_tools column with default 0 on legacy schema', () {
      db.execute(_legacyCreateTable);
      _seedLegacyRow(db, 'legacy.a');
      expect(_hasColumn(db, 'hidden_from_tools'), isFalse);

      PluginSystemDatabase.ensureSchemaUpgrades(db);

      expect(_hasColumn(db, 'hidden_from_tools'), isTrue);
      final rows = db.select(
        'SELECT hidden_from_tools FROM plugin_installation WHERE plugin_id = ?',
        ['legacy.a'],
      );
      expect(
        rows.first['hidden_from_tools'],
        0,
        reason:
            'existing plugins must default to visible (hidden_from_tools=0)',
      );
    });

    test('hidden_from_tools migration is idempotent', () {
      db.execute(_legacyCreateTable);

      PluginSystemDatabase.ensureSchemaUpgrades(db);
      expect(
        () => PluginSystemDatabase.ensureSchemaUpgrades(db),
        returnsNormally,
      );

      final cols = db
          .select('PRAGMA table_info(plugin_installation)')
          .toMapList();
      final hiddenCols = cols
          .where((c) => c['name'] == 'hidden_from_tools')
          .toList();
      expect(hiddenCols, hasLength(1));
    });

    test(
      'adds allow_order_before_built_ins_granted column without forcing old rows to false',
      () {
        db.execute(_legacyCreateTable);
        _seedLegacyRow(db, 'legacy.a');
        expect(_hasColumn(db, 'allow_order_before_built_ins_granted'), isFalse);

        PluginSystemDatabase.ensureSchemaUpgrades(db);

        expect(_hasColumn(db, 'allow_order_before_built_ins_granted'), isTrue);
        final rows = db.select(
          'SELECT allow_order_before_built_ins_granted FROM plugin_installation WHERE plugin_id = ?',
          ['legacy.a'],
        );
        expect(
          rows.first['allow_order_before_built_ins_granted'],
          isNull,
          reason:
              'legacy rows should stay undecided so runtime fallback can '
              'preserve pre-existing behavior',
        );
      },
    );
  });
}
