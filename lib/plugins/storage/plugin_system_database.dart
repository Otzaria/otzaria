import 'package:flutter/foundation.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';

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
    final cols = db
        .select('PRAGMA table_info(plugin_installation)')
        .toMapList();
    final hasNavRailCol = cols.any((c) => c['name'] == 'pinned_to_nav_rail');
    if (!hasNavRailCol) {
      db.execute(
        'ALTER TABLE plugin_installation ADD COLUMN pinned_to_nav_rail INTEGER NOT NULL DEFAULT 0',
      );
    }
    final hasUserOrderCol = cols.any((c) => c['name'] == 'user_order');
    if (!hasUserOrderCol) {
      db.execute(
        'ALTER TABLE plugin_installation ADD COLUMN user_order INTEGER',
      );
    }
    final hasHiddenCol = cols.any((c) => c['name'] == 'hidden_from_tools');
    if (!hasHiddenCol) {
      db.execute(
        'ALTER TABLE plugin_installation ADD COLUMN hidden_from_tools INTEGER NOT NULL DEFAULT 0',
      );
    }
    final hasLeadingCol = cols.any(
      (c) => c['name'] == 'allow_order_before_built_ins_granted',
    );
    if (!hasLeadingCol) {
      db.execute(
        'ALTER TABLE plugin_installation ADD COLUMN allow_order_before_built_ins_granted INTEGER',
      );
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
        hidden_from_tools INTEGER NOT NULL DEFAULT 0,
        allow_order_before_built_ins_granted INTEGER,
        manifest_json TEXT NOT NULL,
        installed_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        source_type TEXT NOT NULL DEFAULT 'packaged',
        dev_root_path TEXT,
        user_order INTEGER
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
    final maps = db.select('''
      SELECT p.*,
        COALESCE((
          SELECT granted FROM plugin_permission_grant
          WHERE plugin_id = p.plugin_id AND permission = 'network.access'
        ), 0) AS network_access_granted,
        COALESCE((
          SELECT granted FROM plugin_permission_grant
          WHERE plugin_id = p.plugin_id AND permission = 'app.run_on_startup'
        ), 0) AS run_on_startup_granted
      FROM plugin_installation p
    ''').toMapList();
    return maps.map((map) => InstalledPlugin.fromDbMap(map)).toList();
  }

  Future<InstalledPlugin?> getInstalledPlugin(String pluginId) async {
    final db = await database;
    final maps = db.select(
      'SELECT * FROM plugin_installation WHERE plugin_id = ?',
      [pluginId],
    ).toMapList();
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
      db.execute('DELETE FROM plugin_installation WHERE plugin_id = ?', [
        pluginId,
      ]);
      db.execute('DELETE FROM plugin_permission_grant WHERE plugin_id = ?', [
        pluginId,
      ]);
      db.execute('DELETE FROM plugin_kv_store WHERE plugin_id = ?', [pluginId]);
      db.execute('DELETE FROM plugin_published_record WHERE plugin_id = ?', [
        pluginId,
      ]);
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
      [pinned ? 1 : 0, DateTime.now().toIso8601String(), pluginId],
    );
  }

  Future<void> updatePluginShowInTools(
    String pluginId,
    bool showInTools,
  ) async {
    final db = await database;
    db.execute(
      'UPDATE plugin_installation SET hidden_from_tools = ?, updated_at = ? WHERE plugin_id = ?',
      [
        showInTools ? 0 : 1,
        DateTime.now().toIso8601String(),
        pluginId,
      ],
    );
  }

  Future<void> updatePluginNavRailPinState(
    String pluginId,
    bool pinnedToNavRail,
  ) async {
    final db = await database;
    db.execute(
      'UPDATE plugin_installation SET pinned_to_nav_rail = ?, updated_at = ? WHERE plugin_id = ?',
      [
        pinnedToNavRail ? 1 : 0,
        DateTime.now().toIso8601String(),
        pluginId,
      ],
    );
  }

  /// שומר סדר מותאם אישית של תוספים.
  ///
  /// המפתחות הם plugin_id והערכים הם מספרי סדר (קטן יותר = מוקדם יותר).
  /// העדכון מתבצע ב-transaction כדי לשמור על עקביות.
  ///
  /// אין עדכון של `updated_at`: סדר התצוגה אינו מאפיין של ההתקנה, ועדכון כזה
  /// בונה מחדש את דף התוסף עם ה-WebView בזמן dispose ב-Windows.
  Future<void> updatePluginsUserOrder(Map<String, int> ordering) async {
    if (ordering.isEmpty) return;
    final db = await database;
    applyUserOrderUpdates(db, ordering);
  }

  /// הלוגיקה הטהורה של [updatePluginsUserOrder] על Database נתון.
  /// חשוף לבדיקות שלא צריכות לעבור דרך ה-singleton וה-FS.
  ///
  /// משתמש ב-SAVEPOINT ולא ב-`BEGIN TRANSACTION` כדי שהקריאה תעבוד גם
  /// בתוך טרנזקציה חיצונית פתוחה (SQLite לא תומך בטרנזקציות מקוננות
  /// אבל כן ב-savepoints מקוננים).
  @visibleForTesting
  static void applyUserOrderUpdates(Database db, Map<String, int> ordering) {
    if (ordering.isEmpty) return;
    const savepoint = 'sp_plugin_user_order';
    db.execute('SAVEPOINT $savepoint');
    try {
      for (final entry in ordering.entries) {
        db.execute(
          'UPDATE plugin_installation SET user_order = ? WHERE plugin_id = ?',
          [entry.value, entry.key],
        );
      }
      db.execute('RELEASE SAVEPOINT $savepoint');
    } catch (e, stackTrace) {
      // מתעדים לפני ה-rethrow כדי שלא נאבד את הסיבה
      // (database locked, constraint violation, SQL syntax וכו').
      debugPrint('applyUserOrderUpdates failed: $e\n$stackTrace');
      db.execute('ROLLBACK TO SAVEPOINT $savepoint');
      db.execute('RELEASE SAVEPOINT $savepoint');
      rethrow;
    }
  }

  // --- CRUD for Permissions ---

  Future<void> setPermission(
    String pluginId,
    String permission,
    bool granted,
  ) async {
    final db = await database;
    db.execute(
      'INSERT OR REPLACE INTO plugin_permission_grant (plugin_id, permission, granted, granted_at) VALUES (?, ?, ?, ?)',
      [pluginId, permission, granted ? 1 : 0, DateTime.now().toIso8601String()],
    );
  }

  Future<bool?> getPermission(String pluginId, String permission) async {
    final db = await database;
    final results = db.select(
      'SELECT granted FROM plugin_permission_grant WHERE plugin_id = ? AND permission = ?',
      [pluginId, permission],
    );
    if (results.isEmpty) return null;
    return (results.first['granted'] as int) == 1;
  }

  Future<List<PluginPermissionGrant>> getPluginPermissions(
    String pluginId,
  ) async {
    final db = await database;
    final rows = db.select(
      'SELECT * FROM plugin_permission_grant WHERE plugin_id = ? ORDER BY permission',
      [pluginId],
    ).toMapList();
    return rows.map(PluginPermissionGrant.fromDbMap).toList();
  }

  // --- CRUD for KV Store ---

  Future<void> setPluginKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    final db = await database;
    db.execute(
      'INSERT OR REPLACE INTO plugin_kv_store (plugin_id, namespace, key, value_json, updated_at) VALUES (?, ?, ?, ?, ?)',
      [pluginId, namespace, key, valueJson, DateTime.now().toIso8601String()],
    );
  }

  Future<String?> getPluginKV(
    String pluginId,
    String namespace,
    String key,
  ) async {
    final db = await database;
    final results = db.select(
      'SELECT value_json FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? AND key = ?',
      [pluginId, namespace, key],
    );
    if (results.isEmpty) return null;
    return results.first['value_json'] as String?;
  }

  Future<void> removePluginKV(
    String pluginId,
    String namespace,
    String key,
  ) async {
    final db = await database;
    db.execute(
      'DELETE FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? AND key = ?',
      [pluginId, namespace, key],
    );
  }

  Future<List<String>> listPluginKVKeys(
    String pluginId,
    String namespace,
  ) async {
    final db = await database;
    final rows = db.select(
      'SELECT key FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? ORDER BY key',
      [pluginId, namespace],
    );
    return rows.map((row) => row['key'] as String).toList();
  }

  // --- Published Records ---

  Future<void> publishRecord(
    String pluginId,
    String type,
    String scope,
    String recordKey,
    String payloadJson,
    String? expiresAt,
  ) async {
    final db = await database;
    db.execute(
      '''
      INSERT OR REPLACE INTO plugin_published_record 
      (plugin_id, type, scope, record_key, payload_json, version, created_at, updated_at, expires_at) 
      VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?)
      ''',
      [
        pluginId,
        type,
        scope,
        recordKey,
        payloadJson,
        DateTime.now().toIso8601String(),
        DateTime.now().toIso8601String(),
        expiresAt,
      ],
    );
  }

  Future<void> unpublishRecord(
    String pluginId,
    String type,
    String scope,
    String recordKey,
  ) async {
    final db = await database;
    db.execute(
      'DELETE FROM plugin_published_record WHERE plugin_id = ? AND type = ? AND scope = ? AND record_key = ?',
      [pluginId, type, scope, recordKey],
    );
  }

  Future<List<String>> getPublishedRecordsByType(String type) async {
    final db = await database;
    final results = db.select(
      'SELECT payload_json FROM plugin_published_record WHERE type = ?',
      [type],
    );
    return results.map((r) => r['payload_json'] as String).toList();
  }

  Future<List<PluginPublishedRecord>> getPluginPublishedRecords(
    String pluginId,
  ) async {
    final db = await database;
    final rows = db.select(
      'SELECT * FROM plugin_published_record WHERE plugin_id = ? ORDER BY type, scope, record_key',
      [pluginId],
    ).toMapList();
    return rows.map(PluginPublishedRecord.fromDbMap).toList();
  }

  /// מחזיר records מלאים כולל plugin_id, scope, record_key ו-payload_json
  Future<List<Map<String, dynamic>>> getPublishedRecordsFull(
    String type,
  ) async {
    final db = await database;
    final results = db.select(
      'SELECT plugin_id, type, scope, record_key, payload_json FROM plugin_published_record WHERE type = ?',
      [type],
    );
    return results
        .map(
          (r) => {
            'plugin_id': r['plugin_id'] as String,
            'type': r['type'] as String,
            'scope': r['scope'] as String,
            'key': r['record_key'] as String,
            'payload_json': r['payload_json'] as String,
          },
        )
        .toList();
  }

  // --- Runtime Log ---

  Future<void> writeLog(String pluginId, String level, String message) async {
    // לוג ריצה הוא best-effort ונקרא fire-and-forget; אם פתיחת ה-DB נכשלת
    // אסור שהכישלון יבעבע ויפיל את הקורא (או ייהפך לשגיאה אסינכרונית לא-מטופלת).
    try {
      final db = await database;
      db.execute(
        'INSERT INTO plugin_runtime_log (plugin_id, level, message, created_at) VALUES (?, ?, ?, ?)',
        [pluginId, level, message, DateTime.now().toIso8601String()],
      );
    } catch (e) {
      debugPrint('[PluginSystemDatabase] writeLog failed: $e');
    }
  }

  // --- Backup / Restore ---

  /// מייצא את הרשומות הנלוות של תוסף (הרשאות, KV, published records) לגיבוי.
  ///
  /// [pluginId] - מזהה התוסף.
  /// מחזיר מפה עם המפתחות `permissions`, `kvStore`, `publishedRecords`,
  /// שכל אחד הוא רשימת שורות גולמיות מוכנות לסריאליזציה ל-JSON.
  Future<Map<String, List<Map<String, dynamic>>>> exportPluginAuxData(
    String pluginId,
  ) async {
    final db = await database;
    final permissions = db.select(
      'SELECT permission, granted, granted_at FROM plugin_permission_grant WHERE plugin_id = ?',
      [pluginId],
    ).toMapList();
    final kvStore = db.select(
      'SELECT namespace, key, value_json, updated_at FROM plugin_kv_store WHERE plugin_id = ?',
      [pluginId],
    ).toMapList();
    final publishedRecords = db.select(
      'SELECT type, scope, record_key, payload_json, version, created_at, updated_at, expires_at FROM plugin_published_record WHERE plugin_id = ?',
      [pluginId],
    ).toMapList();
    return {
      'permissions': permissions,
      'kvStore': kvStore,
      'publishedRecords': publishedRecords,
    };
  }

  /// מייבא רשומות נלוות של תוסף משחזור גיבוי.
  ///
  /// [pluginId] - מזהה התוסף.
  /// [aux] - מפה במבנה שמחזירה [exportPluginAuxData].
  /// שחזור נאמן לגיבוי: כל הרשומות הנלוות הקיימות של התוסף נמחקות תחילה,
  /// כדי שלא יישארו הרשאות/KV/published records שאינם בגיבוי (merge שקט).
  Future<void> importPluginAuxData(
    String pluginId,
    Map<String, dynamic> aux,
  ) async {
    final db = await database;
    db.execute('BEGIN TRANSACTION');
    try {
      db.execute('DELETE FROM plugin_permission_grant WHERE plugin_id = ?', [
        pluginId,
      ]);
      db.execute('DELETE FROM plugin_kv_store WHERE plugin_id = ?', [pluginId]);
      db.execute('DELETE FROM plugin_published_record WHERE plugin_id = ?', [
        pluginId,
      ]);
      for (final row in (aux['permissions'] as List? ?? const [])) {
        final m = (row as Map).cast<String, dynamic>();
        db.execute(
          'INSERT OR REPLACE INTO plugin_permission_grant (plugin_id, permission, granted, granted_at) VALUES (?, ?, ?, ?)',
          [pluginId, m['permission'], m['granted'], m['granted_at']],
        );
      }
      for (final row in (aux['kvStore'] as List? ?? const [])) {
        final m = (row as Map).cast<String, dynamic>();
        db.execute(
          'INSERT OR REPLACE INTO plugin_kv_store (plugin_id, namespace, key, value_json, updated_at) VALUES (?, ?, ?, ?, ?)',
          [
            pluginId,
            m['namespace'],
            m['key'],
            m['value_json'],
            m['updated_at'],
          ],
        );
      }
      for (final row in (aux['publishedRecords'] as List? ?? const [])) {
        final m = (row as Map).cast<String, dynamic>();
        db.execute(
          'INSERT OR REPLACE INTO plugin_published_record (plugin_id, type, scope, record_key, payload_json, version, created_at, updated_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            pluginId,
            m['type'],
            m['scope'],
            m['record_key'],
            m['payload_json'],
            m['version'] ?? 1,
            m['created_at'],
            m['updated_at'],
            m['expires_at'],
          ],
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// סוגר ומאפס את חיבור ה-DB כדי לאפשר החלפת תיקיית נתונים בזמן ריצה.
  Future<void> close() async {
    _database?.close();
    _database = null;
  }

  /// מאפס סינכרונית את ה-singleton עבור בדיקות קיימות.
  @visibleForTesting
  void resetForTests() {
    _database?.close();
    _database = null;
  }
}
