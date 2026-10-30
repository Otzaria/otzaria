import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';

class PluginSystemDatabase {
  PluginSystemDatabase._();
  static final PluginSystemDatabase instance = PluginSystemDatabase._();

  /// גודל אצווה לשאילתה בודדת ב-`getPluginKVMany` — לא תקרה על סך המפתחות.
  static const int maxKVBulkKeys = 200;

  Database? _database;
  Future<Database>? _opening;
  String? _storageMoveRequestId;
  Completer<void>? _storageMoveReleased;
  Completer<void>? _storageMoveWritesReleased;

  String? _dbPath;
  List<(String, List<Object?>)>? _openWriteBatch;
  Future<void>? _writeTail;
  final Set<Future<void>> _pendingReads = {};

  Future<Database> get database async {
    // בלי כתיבה ממתינה אין await: מתחת ל-FakeAsync הוא לא היה מתקדם.
    if (_writeTail case final tail?) await _settled(tail);
    return _connection();
  }

  Future<Database> _connection() async {
    while (true) {
      final released = _storageMoveReleased;
      if (released != null) await released.future;
      if (_database != null) return _database!;

      final opening = _opening ??= _initDatabase();
      late final Database opened;
      try {
        opened = await opening;
      } catch (_) {
        if (identical(_opening, opening)) _opening = null;
        rethrow;
      }
      if (_storageMoveReleased != null) {
        if (identical(_opening, opening)) {
          _opening = null;
          opened.close();
        }
        continue;
      }
      _database = opened;
      if (identical(_opening, opening)) _opening = null;
      return opened;
    }
  }

  /// המסד, רק אם כבר נפתח.
  Database? get openDatabase => _database;

  Future<Database> _initDatabase() async {
    final dbPath = _dbPath = await AppPaths.resolvePluginsDbPath();
    final db = openWritableDatabase(dbPath, 'PluginSystemDatabase');
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

    // 6. טיוטות תיקון מקומיות — נכתבות דרך PluginCorrectionDraftRepository.
    PluginCorrectionDraftStore.createSchema(db);
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

  Future<bool> hasEnabledPlugin() async => readHasEnabledPlugin(await database);

  static bool readHasEnabledPlugin(Database db) => db
      .select('SELECT 1 FROM plugin_installation WHERE enabled = 1 LIMIT 1')
      .isNotEmpty;

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
    _insertOrUpdatePlugin(db, plugin);
  }

  Future<void> insertOrUpdatePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions, {
    InstalledPlugin? expectedPlugin,
    Map<String, bool> expectedPermissions = const {},
  }) async {
    final db = await database;
    applyPluginInstall(
      db,
      plugin,
      permissions,
      expectedPlugin: expectedPlugin,
      expectedPermissions: expectedPermissions,
    );
  }

  @visibleForTesting
  static void applyPluginInstall(
    Database db,
    InstalledPlugin plugin,
    Map<String, bool> permissions, {
    InstalledPlugin? expectedPlugin,
    Map<String, bool> expectedPermissions = const {},
  }) {
    _inSavepoint(db, 'sp_plugin_install', () {
      // הבדיקה והכתיבה באותה טרנזקציה: הסרה או החלטת משתמש מבטלות שדרוג אוטומטי.
      if (expectedPlugin != null) {
        final rows = db.select(
          'SELECT * FROM plugin_installation WHERE plugin_id = ?',
          [plugin.pluginId],
        );
        final grants = {
          for (final row in db.select(
            'SELECT permission, granted FROM plugin_permission_grant WHERE plugin_id = ?',
            [plugin.pluginId],
          ))
            if (expectedPlugin.manifest.permissions.contains(row['permission']))
              row['permission'] as String: row['granted'] == 1,
        };
        if (rows.isEmpty ||
            !mapEquals(
              InstalledPlugin.fromDbMap(rows.single).toDbMap(),
              expectedPlugin.toDbMap(),
            ) ||
            !mapEquals(grants, expectedPermissions)) {
          throw StateError('Plugin changed during bundled upgrade');
        }
      }
      _insertOrUpdatePlugin(db, plugin);
      db.execute(
        'DELETE FROM plugin_permission_grant WHERE plugin_id = ? '
        'AND (permission != ? OR ? = 0)',
        [
          plugin.pluginId,
          pluginNewTabPagePermission,
          plugin.manifest.permissions.contains('navigation.write') ? 1 : 0,
        ],
      );
      final grantedAt = DateTime.now().toIso8601String();
      for (final entry in permissions.entries) {
        if (entry.key == pluginNewTabPagePermission) continue;
        db.execute(
          'INSERT INTO plugin_permission_grant '
          '(plugin_id, permission, granted, granted_at) VALUES (?, ?, ?, ?)',
          [plugin.pluginId, entry.key, entry.value ? 1 : 0, grantedAt],
        );
      }
      if (permissions['navigation.write'] != true) {
        db.execute(
          'UPDATE plugin_permission_grant SET granted = 0 '
          'WHERE plugin_id = ? AND permission = ?',
          [plugin.pluginId, pluginNewTabPagePermission],
        );
      }
    });
  }

  /// SAVEPOINT ולא BEGIN, כדי שהקריאה תעבוד גם בתוך טרנזקציה חיצונית פתוחה.
  static T _inSavepoint<T>(Database db, String name, T Function() body) {
    db.execute('SAVEPOINT $name');
    try {
      final result = body();
      db.execute('RELEASE SAVEPOINT $name');
      return result;
    } catch (_) {
      db.execute('ROLLBACK TO SAVEPOINT $name');
      db.execute('RELEASE SAVEPOINT $name');
      rethrow;
    }
  }

  static void _insertOrUpdatePlugin(Database db, InstalledPlugin plugin) {
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
    withTransaction(db, () {
      db.execute('DELETE FROM plugin_installation WHERE plugin_id = ?', [
        pluginId,
      ]);
      db.execute('DELETE FROM plugin_permission_grant WHERE plugin_id = ?', [
        pluginId,
      ]);
      deletePluginDataRows(db, pluginId);
    });
  }

  /// מוחק את כל הנתונים שהתוסף אגר (KV, רשומות שפורסמו כגון אירועי לוח, לוג),
  /// בלי לגעת ברישום ההתקנה ובהרשאות שהמשתמש אישר.
  Future<void> clearPluginData(String pluginId) async {
    final db = await database;
    withTransaction(db, () => deletePluginDataRows(db, pluginId));
  }

  /// שורות הנתונים של [pluginId] בלבד — משותף למחיקת תוסף ולאיפוס נתוניו.
  @visibleForTesting
  static void deletePluginDataRows(Database db, String pluginId) {
    db.execute('DELETE FROM plugin_kv_store WHERE plugin_id = ?', [pluginId]);
    db.execute('DELETE FROM plugin_published_record WHERE plugin_id = ?', [
      pluginId,
    ]);
    db.execute('DELETE FROM plugin_runtime_log WHERE plugin_id = ?', [
      pluginId,
    ]);
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
      // מתעדים לפני ה-ROLLBACK, שעלול להיכשל בעצמו, כדי שלא נאבד את הסיבה
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
    applyPermission(db, pluginId, permission, granted);
  }

  @visibleForTesting
  static void applyPermission(
    Database db,
    String pluginId,
    String permission,
    bool granted,
  ) {
    _inSavepoint(db, 'sp_plugin_permission', () {
      db.execute(
        'INSERT OR REPLACE INTO plugin_permission_grant (plugin_id, permission, granted, granted_at) VALUES (?, ?, ?, ?)',
        [
          pluginId,
          permission,
          granted ? 1 : 0,
          DateTime.now().toIso8601String(),
        ],
      );
      if (permission == 'navigation.write' && !granted) {
        db.execute(
          'UPDATE plugin_permission_grant SET granted = 0 '
          'WHERE plugin_id = ? AND permission = ?',
          [pluginId, pluginNewTabPagePermission],
        );
      }
    });
  }

  Future<void> clearNewTabPageRegistration(String pluginId) async {
    final db = await database;
    db.execute(
      'DELETE FROM plugin_permission_grant WHERE plugin_id = ? '
      'AND permission = ? AND granted = 1',
      [pluginId, pluginNewTabPagePermission],
    );
  }

  Future<String?> getNewTabPageOwner() async =>
      readNewTabPageOwner(await database);

  @visibleForTesting
  static String? readNewTabPageOwner(Database db) {
    final rows = db.select(
      'SELECT p.* FROM plugin_installation p '
      'JOIN plugin_permission_grant button ON button.plugin_id = p.plugin_id '
      'JOIN plugin_permission_grant nav ON nav.plugin_id = p.plugin_id '
      'WHERE p.enabled = 1 AND button.permission = ? AND button.granted = 1 '
      "AND nav.permission = 'navigation.write' AND nav.granted = 1",
      [pluginNewTabPagePermission],
    );
    for (final row in rows) {
      final plugin = InstalledPlugin.fromDbMap(row);
      if (plugin.manifest.permissions.contains('navigation.write')) {
        return plugin.pluginId;
      }
    }
    return null;
  }

  Future<bool> grantNewTabPage(
    String pluginId, {
    required bool allowPreviouslyDenied,
    required String? expectedOwner,
    required void Function() onGranted,
  }) async {
    final db = await database;
    final granted = applyNewTabPageGrant(
      db,
      pluginId,
      allowPreviouslyDenied: allowPreviouslyDenied,
      expectedOwner: expectedOwner,
    );
    // אין await בין החלטת ההרשאה לבעלות הפעילה: שלילה מקבילה תנקה את שתיהן.
    if (granted) onGranted();
    return granted;
  }

  @visibleForTesting
  static bool applyNewTabPageGrant(
    Database db,
    String pluginId, {
    bool allowPreviouslyDenied = true,
    String? expectedOwner,
  }) {
    return _inSavepoint(db, 'sp_plugin_new_tab', () {
      final eligible = db.select(
        'SELECT p.* FROM plugin_installation p '
        'JOIN plugin_permission_grant g ON g.plugin_id = p.plugin_id '
        "WHERE p.plugin_id = ? AND p.enabled = 1 "
        "AND g.permission = 'navigation.write' AND g.granted = 1",
        [pluginId],
      );
      final denied =
          !allowPreviouslyDenied &&
          db.select(
            'SELECT 1 FROM plugin_permission_grant WHERE plugin_id = ? '
            'AND permission = ? AND granted = 0',
            [pluginId, pluginNewTabPagePermission],
          ).isNotEmpty;
      if (eligible.isEmpty ||
          !InstalledPlugin.fromDbMap(
            eligible.first,
          ).manifest.permissions.contains('navigation.write') ||
          denied ||
          readNewTabPageOwner(db) != expectedOwner) {
        return false;
      }
      db.execute(
        'UPDATE plugin_permission_grant SET granted = 0 WHERE permission = ?',
        [pluginNewTabPagePermission],
      );
      db.execute(
        'INSERT OR REPLACE INTO plugin_permission_grant '
        '(plugin_id, permission, granted, granted_at) VALUES (?, ?, 1, ?)',
        [
          pluginId,
          pluginNewTabPagePermission,
          DateTime.now().toIso8601String(),
        ],
      );
      return true;
    });
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
    return _enqueueWrite(
      'INSERT OR REPLACE INTO plugin_kv_store (plugin_id, namespace, key, value_json, updated_at) VALUES (?, ?, ?, ?, ?)',
      [pluginId, namespace, key, valueJson, DateTime.now().toIso8601String()],
    );
  }

  /// מעליו הקריאה רצה ב-isolate: ערך גדול נקרא מהדיסק דף אחר דף ותוקע את ה-UI (#3644).
  static const int maxInlineKVReadBytes = 64 * 1024;

  Future<String?> getPluginKV(
    String pluginId,
    String namespace,
    String key,
  ) async => (await getPluginKVMany(pluginId, namespace, [key]))[key];

  /// קריאה מרוכזת של מפתחות KV בשאילתה אחת. מפתח שאינו קיים חסר מהמפה.
  /// [keys] נחתך ל-[maxKVBulkKeys] כדי לא לבנות משפט SQL ענק.
  Future<Map<String, String>> getPluginKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async {
    if (keys.isEmpty) return const {};
    final db = await database;
    // octet_length אינו טוען את דפי ה-overflow של הערך.
    final bytes = _selectKV(
      db,
      'octet_length(value_json)',
      pluginId,
      namespace,
      keys,
    ).fold(0, (sum, row) => sum + (row['v'] as int));
    if (bytes <= maxInlineKVReadBytes) {
      return selectKVMany(db, pluginId, namespace, keys);
    }
    return _readKVInIsolate(pluginId, namespace, keys.toList());
  }

  Future<Map<String, String>> _readKVInIsolate(
    String pluginId,
    String namespace,
    List<String> keys,
  ) async {
    // קריאה שמתחילה אחרי בקשת העברה רצה על הנתיב החדש; הניקוז מחכה רק לרצות.
    for (
      var released = _storageMoveWritesReleased;
      released != null;
      released = _storageMoveWritesReleased
    ) {
      await released.future;
      await database;
    }
    final read = _selectKVInIsolate(_dbPath!, pluginId, namespace, keys);
    final settled = _settled(read);
    _pendingReads.add(settled);
    settled.then((_) => _pendingReads.remove(settled));
    return read;
  }

  static Future<Map<String, String>> _selectKVInIsolate(
    String path,
    String pluginId,
    String namespace,
    List<String> keys,
  ) => Isolate.run(() {
    final db = openSecondaryWritableConnection(path, 'PluginDbRead');
    try {
      return selectKVMany(db, pluginId, namespace, keys);
    } finally {
      db.close();
    }
  }, debugName: 'PluginDbRead');

  /// הלוגיקה הטהורה של [getPluginKVMany] על Database נתון — חשוף לבדיקות.
  @visibleForTesting
  static Map<String, String> selectKVMany(
    Database db,
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) => {
    for (final row in _selectKV(db, 'value_json', pluginId, namespace, keys))
      if (row['v'] case final String value) row['key'] as String: value,
  };

  static Iterable<Row> _selectKV(
    Database db,
    String value,
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) sync* {
    final unique = keys.toSet().toList();
    // אצווה חוסמת את גודל משפט ה-SQL, אבל אף מפתח אינו נזרק: תנאי שנשען על
    // מפתח שנחתך היה מוערך false בשקט.
    for (var start = 0; start < unique.length; start += maxKVBulkKeys) {
      final batch = unique.sublist(
        start,
        (start + maxKVBulkKeys).clamp(0, unique.length),
      );
      final placeholders = List.filled(batch.length, '?').join(', ');
      yield* db.select(
        'SELECT key, $value AS v FROM plugin_kv_store '
        'WHERE plugin_id = ? AND namespace = ? AND key IN ($placeholders)',
        [pluginId, namespace, ...batch],
      );
    }
  }

  Future<void> removePluginKV(
    String pluginId,
    String namespace,
    String key,
  ) async {
    return _enqueueWrite(
      'DELETE FROM plugin_kv_store WHERE plugin_id = ? AND namespace = ? AND key = ?',
      [pluginId, namespace, key],
    );
  }

  /// כתיבות תוספים רצות ב-isolate; מה שמצטבר בזמן אצווה נכנס לאצווה הבאה.
  Future<void> _enqueueWrite(String sql, List<Object?> args) {
    if (_storageMoveWritesReleased case final released?) {
      return released.future.then((_) => _enqueueWrite(sql, args));
    }
    if (_openWriteBatch case final open?) {
      open.add((sql, args));
      return _writeTail!;
    }
    final batch = _openWriteBatch = [(sql, args)];
    final tail = _writeTail = _runWriteBatch(_writeTail, batch);
    _settled(tail).then((_) {
      if (identical(_writeTail, tail)) _writeTail = null;
    });
    return tail;
  }

  Future<void> _runWriteBatch(
    Future<void>? previous,
    List<(String, List<Object?>)> batch,
  ) async {
    if (previous != null) await _settled(previous);
    _openWriteBatch = null;
    await _connection();
    await _writeInIsolate(_dbPath!, batch);
  }

  // static: closure בתוך מתודת מופע הייתה לוכדת את this ונכשלת בשליחה.
  static Future<void> _writeInIsolate(
    String path,
    List<(String, List<Object?>)> batch,
  ) => Isolate.run(() => _runWrites(path, batch), debugName: 'PluginDbWrite');

  static void _runWrites(String path, List<(String, List<Object?>)> batch) {
    final db = openSecondaryWritableConnection(path, 'PluginDbWrite');
    try {
      withTransaction(db, () {
        for (final (sql, args) in batch) {
          db.execute(sql, args);
        }
      });
    } finally {
      db.close();
    }
  }

  static Future<void> _settled(Future<void> future) =>
      future.then((_) {}, onError: (_) {});

  /// גם קריאות שרצות ב-isolate, כדי שלא יישאר חיבור לקובץ הישן בזמן העברה.
  Future<void> _drainWrites() async {
    while (true) {
      final pending = [
        if (_writeTail case final tail?) _settled(tail),
        ..._pendingReads,
      ];
      if (pending.isEmpty) return;
      await Future.wait(pending);
    }
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
    return _enqueueWrite(
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
    return _enqueueWrite(
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
      await _enqueueWrite(
        'INSERT INTO plugin_runtime_log (plugin_id, level, message, created_at) VALUES (?, ?, ?, ?)',
        [pluginId, level, message, DateTime.now().toIso8601String()],
      );
    } catch (e) {
      debugPrint('[PluginSystemDatabase] writeLog failed: $e');
    }
  }

  // --- Backup / Restore ---

  /// האם נשמרו KV או רשומות שפורסמו, בלי לטעון את התוכן.
  Future<bool> hasPluginUserData(String pluginId) async {
    final db = await database;
    return db.select(
          'SELECT EXISTS(SELECT 1 FROM plugin_kv_store WHERE plugin_id = ?) '
          'OR EXISTS(SELECT 1 FROM plugin_published_record WHERE plugin_id = ?) AS has_data',
          [pluginId, pluginId],
        ).first['has_data'] ==
        1;
  }

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
    applyPluginAuxData(db, pluginId, aux);
  }

  @visibleForTesting
  static void applyPluginAuxData(
    Database db,
    String pluginId,
    Map<String, dynamic> aux,
  ) {
    withTransaction(db, () {
      final previousOwner = readNewTabPageOwner(db);
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
          [
            pluginId,
            m['permission'],
            m['permission'] == pluginNewTabPagePermission &&
                    previousOwner != null &&
                    previousOwner != pluginId
                ? 0
                : m['granted'],
            m['granted_at'],
          ],
        );
      }
      final eligible = db.select(
        'SELECT p.* FROM plugin_installation p '
        'JOIN plugin_permission_grant nav ON nav.plugin_id = p.plugin_id '
        "WHERE p.plugin_id = ? AND nav.permission = 'navigation.write' "
        'AND nav.granted = 1',
        [pluginId],
      );
      if (eligible.isEmpty ||
          !InstalledPlugin.fromDbMap(
            eligible.first,
          ).manifest.permissions.contains('navigation.write')) {
        db.execute(
          'UPDATE plugin_permission_grant SET granted = 0 '
          'WHERE plugin_id = ? AND permission = ?',
          [pluginId, pluginNewTabPagePermission],
        );
      }
      if (db.select(
        'SELECT 1 FROM plugin_permission_grant WHERE plugin_id = ? '
        'AND permission = ? AND granted = 1',
        [pluginId, pluginNewTabPagePermission],
      ).isNotEmpty) {
        db.execute(
          'UPDATE plugin_permission_grant SET granted = 0 '
          'WHERE permission = ? AND plugin_id != ?',
          [pluginNewTabPagePermission, pluginId],
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
    });
  }

  /// סוגר ומאפס את חיבור ה-DB כדי לאפשר החלפת תיקיית נתונים בזמן ריצה.
  Future<void> close() async {
    // נעילת החיבור מוקמת רק אחרי שהכתיבות שקדמו לבקשת ההעברה נוקזו.
    if (_storageMoveReleased == null) await _drainWrites();
    final db = _database;
    if (db != null) closeWithCheckpoint(db);
    _database = null;
  }

  Future<void> lockForStorageMove(String requestId) async {
    if (_storageMoveRequestId != null && _storageMoveRequestId != requestId) {
      throw StateError('Plugin database is already locked for a storage move.');
    }
    _storageMoveRequestId = requestId;
    // חוסמים קבלה לפני ה-await; החיבור נשאר זמין לאצוות שכבר בתור.
    _storageMoveWritesReleased ??= Completer<void>();
    await _drainWrites();
    _storageMoveReleased ??= Completer<void>();
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (error, stackTrace) {
        debugPrint(
          'Plugin database open failed during storage move: $error\n$stackTrace',
        );
      }
    }
    await Future<void>.delayed(Duration.zero);
    await close();
  }

  void releaseStorageMove(String requestId) {
    if (_storageMoveRequestId != requestId) return;
    _storageMoveRequestId = null;
    final writesReleased = _storageMoveWritesReleased;
    _storageMoveWritesReleased = null;
    writesReleased?.complete();
    final released = _storageMoveReleased;
    _storageMoveReleased = null;
    if (released != null && !released.isCompleted) released.complete();
  }

  /// מאפס סינכרונית את ה-singleton עבור בדיקות קיימות.
  @visibleForTesting
  void resetForTests() {
    _openWriteBatch = null;
    _writeTail = null;
    _pendingReads.clear();
    _database?.close();
    _database = null;
    _opening = null;
    _storageMoveRequestId = null;
    _storageMoveReleased = null;
    _storageMoveWritesReleased = null;
  }
}
