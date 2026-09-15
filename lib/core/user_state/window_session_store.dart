import 'dart:convert';

import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';

/// סשן של חלון אחד כפי שנשמר בטבלת `window_sessions`.
class WindowSession {
  const WindowSession({
    required this.slot,
    required this.tabsJson,
    required this.currentIndex,
    this.activeWorkspaceId,
    this.boundsJson,
  });

  /// המשבצת באפיק (ראה `UserStateSlot`).
  final int slot;
  final String tabsJson;
  final int currentIndex;
  final String? activeWorkspaceId;
  final String? boundsJson;
}

/// סשני החלונות: לכל משבצת שורה אחת עם הכרטיסיות, הכרטיסיה הנוכחית,
/// השולחן הפעיל וגבולות החלון.
///
/// שורה שנשארת אחרי סגירה פירושה שהתהליך מת בלי סגירה מסודרת, וההפעלה
/// הבאה משחזרת אותה.
class WindowSessionStore {
  WindowSessionStore({UserStateDatabase? database})
    : _database = database ?? UserStateDatabase.instance;

  static final WindowSessionStore instance = WindowSessionStore();

  final UserStateDatabase _database;

  Future<void> save(
    int slot, {
    required String tabsJson,
    required int currentIndex,
  }) async {
    final db = await _database.database;
    db.execute(
      '''
      INSERT INTO window_sessions
        (slot, tabs_json, current_index, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(slot) DO UPDATE SET
        tabs_json = excluded.tabs_json,
        current_index = excluded.current_index,
        updated_at = excluded.updated_at
      ''',
      [slot, tabsJson, currentIndex, _now()],
    );
  }

  /// מעדכן רק את הכרטיסיה הנוכחית; אין שורה — אין מה לעדכן.
  Future<void> saveCurrentIndex(int slot, int currentIndex) async {
    final db = await _database.database;
    db.execute(
      'UPDATE window_sessions SET current_index = ?, updated_at = ? '
      'WHERE slot = ?',
      [currentIndex, _now(), slot],
    );
  }

  Future<void> saveActiveWorkspace(int slot, String? workspaceId) async {
    final db = await _database.database;
    _ensureRow(db, slot);
    db.execute(
      'UPDATE window_sessions SET active_workspace_id = ?, updated_at = ? '
      'WHERE slot = ?',
      [workspaceId, _now(), slot],
    );
  }

  Future<void> saveBounds(int slot, String? boundsJson) async {
    final db = await _database.database;
    _ensureRow(db, slot);
    db.execute(
      'UPDATE window_sessions SET bounds_json = ?, updated_at = ? '
      'WHERE slot = ?',
      [boundsJson, _now(), slot],
    );
  }

  Future<WindowSession?> load(int slot) async {
    final db = await _database.database;
    return _loadIn(db, slot);
  }

  /// הסשן מהמסד **שכבר פתוח**, בלי await, ו-null כשטרם נפתח.
  ///
  /// ⚠️ קיים בשביל `TabsRepository.loadTabs`, שנקרא מבנאי של bloc ואינו
  /// יכול להיות אסינכרוני. מחייב שהאתחול פתח את המסד לפני בניית ה-blocs.
  WindowSession? loadOpened(int slot) {
    final db = _database.openDatabase;
    return db == null ? null : _loadIn(db, slot);
  }

  static WindowSession? _loadIn(Database db, int slot) {
    final rows = db.select('SELECT * FROM window_sessions WHERE slot = ?', [
      slot,
    ]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<WindowSession>> loadAll() async {
    final db = await _database.database;
    return db
        .select('SELECT * FROM window_sessions WHERE slot > 0 ORDER BY slot')
        .map(_fromRow)
        .toList();
  }

  /// מצרף ל-[host] את הכרטיסיות של כל שאר הסשנים ומוחק אותם, בטרנזקציה
  /// אחת. הגבולות של סשן שנצרף עוברים למארח כשאין לו משלו. מחזיר את
  /// מספר הכרטיסיות שצורפו.
  Future<int> adoptInto(int host) async {
    final db = await _database.database;
    var adopted = 0;
    _inTransaction(db, () {
      final sessions = db
          .select('SELECT * FROM window_sessions WHERE slot > 0 ORDER BY slot')
          .map(_fromRow)
          .toList();
      final own = sessions.where((s) => s.slot == host).firstOrNull;
      final others = sessions.where((s) => s.slot != host).toList();
      final ownTabs = own == null ? const <dynamic>[] : _tabsOf(own);
      final adoptedTabs = [for (final s in others) ..._tabsOf(s)];
      adopted = adoptedTabs.length;
      if (adopted == 0) return;
      db.execute('DELETE FROM window_sessions WHERE slot != ?', [host]);
      db.execute(
        '''
        INSERT INTO window_sessions
          (slot, tabs_json, current_index, active_workspace_id, bounds_json,
           updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(slot) DO UPDATE SET
          tabs_json = excluded.tabs_json,
          bounds_json = COALESCE(window_sessions.bounds_json,
                                 excluded.bounds_json),
          updated_at = excluded.updated_at
        ''',
        [
          host,
          jsonEncode([...ownTabs, ...adoptedTabs]),
          own?.currentIndex ?? 0,
          own?.activeWorkspaceId,
          own?.boundsJson ??
              others.map((s) => s.boundsJson).whereType<String>().firstOrNull,
          _now(),
        ],
      );
    });
    return adopted;
  }

  /// מסדר את הסשנים של שאר החלונות במשבצות רצופות אחרי [host] (עד
  /// [maxSlot]), בטרנזקציה אחת. כשלמארח אין סשן, הראשון שבתור הופך לשלו.
  /// מחזיר את המשבצות שקיבלו סשן, לפי הסדר.
  Future<List<int>> compactAround(int host, int maxSlot) async {
    final db = await _database.database;
    final targets = <int>[];
    _inTransaction(db, () {
      final slots = db
          .select(
            'SELECT slot FROM window_sessions WHERE slot > 0 ORDER BY slot',
          )
          .map((row) => row['slot'] as int)
          .toList();
      final queue = slots.where((slot) => slot != host).toList();
      if (queue.isEmpty) return;
      // מעבר דרך משבצות שליליות, כדי שהעברה לא תדרוס סשן שטרם זז.
      for (final slot in queue) {
        db.execute('UPDATE window_sessions SET slot = ? WHERE slot = ?', [
          -slot,
          slot,
        ]);
      }
      final pending = queue.map((slot) => -slot).toList();
      if (!slots.contains(host)) {
        db.execute('UPDATE window_sessions SET slot = ? WHERE slot = ?', [
          host,
          pending.removeAt(0),
        ]);
      }
      var next = 1;
      for (final tmp in pending) {
        if (next == host) next++;
        if (next > maxSlot) {
          db.execute('DELETE FROM window_sessions WHERE slot = ?', [tmp]);
          continue;
        }
        db.execute('UPDATE window_sessions SET slot = ? WHERE slot = ?', [
          next,
          tmp,
        ]);
        targets.add(next++);
      }
    });
    return targets;
  }

  static List<dynamic> _tabsOf(WindowSession session) {
    final decoded = jsonDecode(session.tabsJson);
    return decoded is List ? decoded : const [];
  }

  static void _inTransaction(Database db, void Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {
        // הכשל המקורי הוא שמעניין.
      }
      rethrow;
    }
  }

  Future<void> delete(int slot) async {
    final db = await _database.database;
    db.execute('DELETE FROM window_sessions WHERE slot = ?', [slot]);
  }

  /// שורה ריקה, כדי ששולחן/גבולות יישמרו גם לפני שנשמרו כרטיסיות.
  void _ensureRow(Database db, int slot) {
    db.execute(
      'INSERT OR IGNORE INTO window_sessions '
      '(slot, tabs_json, current_index, updated_at) VALUES (?, ?, ?, ?)',
      [slot, '[]', 0, _now()],
    );
  }

  static WindowSession _fromRow(Row row) => WindowSession(
    slot: row['slot'] as int,
    tabsJson: row['tabs_json'] as String,
    currentIndex: row['current_index'] as int,
    activeWorkspaceId: row['active_workspace_id'] as String?,
    boundsJson: row['bounds_json'] as String?,
  );

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}
