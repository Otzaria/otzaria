import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';

class PluginSystemDatabase {
  PluginSystemDatabase._();
  static final PluginSystemDatabase instance = PluginSystemDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await AppPaths.resolvePluginsDbPath();
    final db = sqlite3.open(dbPath);
    db.execute('PRAGMA journal_mode=WAL');
    _createSchema(db);
    ensureSchemaUpgrades(db);
    return db;
  }

  /// מבצע מיגרציות סכמה אידמפוטנטיות ל-DB קיים. חשוף לבדיקות.
  @visibleForTesting
  static void ensureSchemaUpgrades(Database db) {
    final cols =
        db.select('PRAGMA table_info(plugin_installation)').toMapList();
    final hasNavRailCol = cols.any((c) => c['name'] == 'pinned_to_nav_rail');
    if (!hasNavRailCol) {
      db.execute(
          'ALTER TABLE plugin_installation ADD COLUMN pinned_to_nav_rail INTEGER NOT NULL DEFAULT 0');
    }
  }

  void _createSchema(Database db) {
    // 1. plugin_installation
    db.execute('''
      CREATE TABLE IF NOT EXISTS plugin_installation (
        plugin_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        version TEXT NOT NULL,
        install_path TEXT NOT NULL,
        entrypoint_path TEXT NOT NULL,
        icon_path TEXT,
        enabled INTEGER NOT NULL,
        pinned INTEGER NOT NULL DEFAULT 1,
        pinned_to_nav_rail INTEGER NOT NULL DEFAULT 0,
        manifest_json TEXT NOT NULL,
        installed_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'packaged',
        dev_root_path TEXT
      )
    ''');

    // 2. plugin_permission_grant
    db.execute('''
      CREATE TABLE IF NOT EXISTS plugin_permission_grant (
        plugin_id TEXT NOT NULL,
        permission TEXT NOT NULL,
        granted INTEGER NOT NULL,
        granted_at TEXT NOT NULL,
        PRIMARY KEY (plugin_id, permission)
      )
    ''');

    // 3. plugin_kv_store
    db.execute('''
      CREATE TABLE IF NOT EXISTS plugin_kv_store (
        plugin_id TEXT NOT NULL,
        namespace TEXT NOT NULL,
        key TEXT NOT NULL,
        value_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (plugin_id, namespace, key)
      )
    ''');

    // 4. plugin_published_record
    db.execute('''
      CREATE TABLE IF NOT EXISTS plugin_published_record (
        plugin_id TEXT NOT NULL,
        type TEXT NOT NULL,
        scope TEXT NOT NULL,
        record_key TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        expires_at TEXT,
        PRIMARY KEY (plugin_id, type, scope, record_key)
      )
    ''');

    // 5. plugin_runtime_log (optional, leaving empty table for now)
    db.execute('''
      CREATE TABLE IF NOT EXISTS plugin_runtime_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plugin_id TEXT NOT NULL,
        level TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  // --- CRUD for Installed Plugins ---

  Future<List<InstalledPlugin>> getAllInstalledPlugins() async {
    final db = await database;
    final maps = db.select('SELECT * FROM plugin_installation').toMapList();
    return maps.map((map) => InstalledPlugin.fromDbMap(map)).toList();
  }

  Future<InstalledPlugin?> getInstalledPlugin(String pluginId) async {
    final db = await database;
    final maps = db.select(
        'SELECT * FROM plugin_installation WHERE plugin_id = ?',
        [pluginId]).toMapList();
    if (maps.isEmpty) return null;
    return InstalledPlugin.fromDbMap(maps.first);
  }

  Future<void> insertOrUpdatePlugin(InstalledPlugin plugin) async {
    final db = await database;
    final m = plugin.toDbMap();
    final cols = m.keys.join(', ');
    final placeholders = List.filled(m.length, '?').join(', ');
    db.execute(
      'INSERT OR REPLACE INTO plugin_installation ($cols) VALUES ($placeholders)',
      m.values.toList(),
    );
  }

  Future<void> deletePlugin(String pluginId) async {
    final db = await database;
    db.execute('BEGIN TRANSACTION');
    try {
      db.execute(
          'DELETE FROM plugin_installation WHERE plugin_id = ?', [pluginId]);
      db.execute('DELETE FROM plugin_permission_grant WHERE plugin_id = ?',
          [pluginId]);
      db.execute('DELETE FROM plugin_kv_store WHERE plugin_id = ?', [pluginId]);
      db.execute('DELETE FROM plugin_published_record WHERE plugin_id = ?',
          [pluginId]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> updatePluginPinState(String pluginId, bool pinned) async {
    final db = await database;
    db.execute(
        'UPDATE plugin_installation SET pinned = ?, updated_at = ? WHERE plugin_id = ?',
        [pinned ? 1 : 0, DateTime.now().toIso8601String(), pluginId]);
  }

  Future<void> updatePluginNavRailPinState(
      String pluginId, bool pinnedToNavRail) async {
    final db = await database;
    db.execute(
        'UPDATE plugin_installation SET pinned_to_nav_rail = ?, updated_at = ? WHERE plugin_id = ?',
        [
          pinnedToNavRail ? 1 : 0,
          DateTime.now().toIso8601String(),
          pluginId,
        ]);
  }

  // --- CRUD for Permissions ---

  Future<void> setPermission(
      String pluginId, String permission, bool granted) async {
    final db = await database;
    db.execute(
        'INSERT OR REPLACE INTO plugin_permission_grant (plugin_id, permission, granted, granted_at) VALUES (?, ?, ?, ?)',
        [
          pluginId,
          permission,
          granted ? 1 : 0,
          DateTime.now().toIso8601String()
        ]);
  }

  Future<bool?> getPermission(String pluginId, String permission) async {
    final db = await database;
    final results = db.select(
        'SELECT granted FROM plugin_permission_grant WHERE plugin_id = ? AND permission = ?',
        [pluginId, permission]);
    if (results.isEmpty) return null;
    return (results.first['granted'] as int) == 1;
  }

  Future<List<PluginPermissionGrant>> getPluginPermissions(
      String pluginId) async {
    final db = await database;
    final rows = db.select(
      'SELECT * FROM plugin_permission_grant WHERE plugin_id = ? ORDER BY permission',
      [pluginId],
    ).toMapList();
    return rows.map(PluginPermissionGrant.fromDbMap).toList();
  }

  // --- CRUD for KV Store ---

  Future<void> setPluginKV(
      String pluginId, String namespace, String key, String valueJson) async {
    final db = await database;
    db.execute(
        'INSERT OR REPLACE INTO plugin_kv_store (plugin_id, namespace, key, value_json, updated_at) VALUES (?, ?, ?, ?, ?)',
        [
          pluginId,
          namespace,
          key,
          valueJson,
          DateTime.now().toIso8601String()
        ]);
  }

  Future<String?> getPluginKV(
      String pluginId, String namespace, String key) async {
    final db = await database;
    final results = db.select(
        'SELECT value_json FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? AND key = ?',
        [pluginId, namespace, key]);
    if (results.isEmpty) return null;
    return results.first['value_json'] as String?;
  }

  Future<void> removePluginKV(
      String pluginId, String namespace, String key) async {
    final db = await database;
    db.execute(
      'DELETE FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? AND key = ?',
      [pluginId, namespace, key],
    );
  }

  Future<List<String>> listPluginKVKeys(
      String pluginId, String namespace) async {
    final db = await database;
    final rows = db.select(
      'SELECT key FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? ORDER BY key',
      [pluginId, namespace],
    );
    return rows.map((row) => row['key'] as String).toList();
  }

  // --- Published Records ---

  Future<void> publishRecord(String pluginId, String type, String scope,
      String recordKey, String payloadJson, String? expiresAt) async {
    final db = await database;
    db.execute('''
      INSERT OR REPLACE INTO plugin_published_record 
      (plugin_id, type, scope, record_key, payload_json, version, created_at, updated_at, expires_at) 
      VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
      ''', [
      pluginId,
      type,
      scope,
      recordKey,
      payloadJson,
      DateTime.now().toIso8601String(),
      DateTime.now().toIso8601String(),
      expiresAt
    ]);
  }

  Future<void> unpublishRecord(
      String pluginId, String type, String scope, String recordKey) async {
    final db = await database;
    db.execute(
        'DELETE FROM plugin_published_record WHERE plugin_id = ? AND type = ? AND scope = ? AND record_key = ?',
        [pluginId, type, scope, recordKey]);
  }

  Future<List<String>> getPublishedRecordsByType(String type) async {
    final db = await database;
    final results = db.select(
        'SELECT payload_json FROM plugin_published_record WHERE type = ?',
        [type]);
    return results.map((r) => r['payload_json'] as String).toList();
  }

  Future<List<PluginPublishedRecord>> getPluginPublishedRecords(
      String pluginId) async {
    final db = await database;
    final rows = db.select(
      'SELECT * FROM plugin_published_record WHERE plugin_id = ? ORDER BY type, scope, record_key',
      [pluginId],
    ).toMapList();
    return rows.map(PluginPublishedRecord.fromDbMap).toList();
  }

  /// מחזיר records מלאים כולל plugin_id, scope, record_key ו-payload_json
  Future<List<Map<String, dynamic>>> getPublishedRecordsFull(
      String type) async {
    final db = await database;
    final results = db.select(
      'SELECT plugin_id, type, scope, record_key, payload_json FROM plugin_published_record WHERE type = ?',
      [type],
    );
    return results
        .map((r) => {
              'plugin_id': r['plugin_id'] as String,
              'type': r['type'] as String,
              'scope': r['scope'] as String,
              'key': r['record_key'] as String,
              'payload_json': r['payload_json'] as String,
            })
        .toList();
  }

  // --- Runtime Log ---

  Future<void> writeLog(String pluginId, String level, String message) async {
    final db = await database;
    db.execute(
        'INSERT INTO plugin_runtime_log (plugin_id, level, message, created_at) VALUES (?, ?, ?, ?)',
        [pluginId, level, message, DateTime.now().toIso8601String()]);
  }
}
