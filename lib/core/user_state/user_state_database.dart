import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';

/// מסד מצב המשתמש המשותף לכל החלונות: היסטוריה, סימניות, שולחנות, סשני
/// חלונות ותורי דיווח.
///
/// קובץ אחד שכל חלון פותח ישירות (WAL, כמה כותבים מאותו תהליך). אין "חלון
/// בעלים": הסדר בין כותבים מוכרע בנעילת SQLite, לא בניתוב באפיק.
class UserStateDatabase {
  UserStateDatabase._();

  static final UserStateDatabase instance = UserStateDatabase._();

  /// גרסת הסכמה — מקודמים ב-[_migrateSchema] בכל שינוי.
  static const int _schemaVersion = 1;

  Database? _database;
  String? _pathOverride;

  /// פותח את המסד בנתיב הזה במקום בתיקיית המסדים; לבדיקות בלבד.
  @visibleForTesting
  static UserStateDatabase openAt(String path) =>
      UserStateDatabase._().._pathOverride = path;

  @visibleForTesting
  void overridePath(String path) {
    close();
    _pathOverride = path;
  }

  /// המסד הפתוח. הפתיחה עצלה וסינכרונית — כמו `PersonalNotesDatabase`.
  Future<Database> get database async {
    final open = _database;
    if (open != null) return open;
    final path =
        _pathOverride ?? await AppPaths.resolveNotesDbPath('user_state.db');
    return _database ??= _open(path);
  }

  /// המסד הפתוח, כשכבר נפתח; לקוראים סינכרוניים שרצים אחרי האתחול.
  Database? get openDatabase => _database;

  Database _open(String path) {
    final db = sqlite3.open(path);
    // ההמתנה חוסמת את ה-thread המשותף לכל החלונות, ולכן קצרה: היא עוזרת
    // רק מול תהליך אחר (גיבוי, checkpoint).
    db.execute('PRAGMA busy_timeout=1000');
    enableWalBestEffort(db, 'UserStateDatabase');
    _createSchema(db);
    _migrateSchema(db);
    return db;
  }

  void _createSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS lists (
        box TEXT NOT NULL,
        key TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (box, key)
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS window_sessions (
        slot INTEGER PRIMARY KEY,
        tabs_json TEXT NOT NULL,
        current_index INTEGER NOT NULL,
        active_workspace_id TEXT,
        bounds_json TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS pending_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS pending_reports_kind ON pending_reports(kind)',
    );
  }

  void _migrateSchema(Database db) {
    final current = firstIntValue(db.select('PRAGMA user_version')) ?? 0;
    if (current >= _schemaVersion) return;
    db.execute('PRAGMA user_version = $_schemaVersion');
  }

  /// סוגר את החיבור; הפתיחה הבאה דרך [database] תפתח מחדש.
  void close() {
    final db = _database;
    if (db != null) closeWithCheckpoint(db);
    _database = null;
  }

  /// סוגר ופותח מחדש — אחרי שינוי נתיב הספרייה, שמזיז את תיקיית המסדים.
  ///
  /// ⚠️ פותח מיד ולא בעצלות: `TabsRepository.loadTabs` קורא סינכרונית
  /// מהמסד הפתוח, ואחרי `RestartWidget` הוא רץ לפני כל `await` אחר.
  Future<void> reopen() async {
    close();
    await database;
  }
}
