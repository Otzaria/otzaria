import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';

/// מסד מצב המשתמש המשותף לכל החלונות: היסטוריה, סימניות, שולחנות, סשני
/// חלונות ותורי דיווח.
///
/// חיבור אחד ב-isolate לכל החלונות (WAL); הנעילה של SQLite חשובה רק מול
/// תהליך אחר (גיבוי, checkpoint) ומול [enqueueWrite], שכותב מחיבור משני.
class UserStateDatabase {
  UserStateDatabase._();

  static final UserStateDatabase instance = UserStateDatabase._();

  /// טבלאות הטיוטה נפרדות ואינן משנות את החוזה שקוראי התור מכירים.
  static const int _schemaVersion = 1;

  /// כתיבה ב-isolate הנוכחי: FakeAsync של `testWidgets` אינו מקבל את התשובה
  /// מ-`Isolate.run`, ובדיקות שמריצות את האפליקציה כולה היו נתקעות.
  static bool debugWriteInline = false;

  Database? _database;
  String? _pathOverride;
  String? _path;
  List<(String, List<Object?>)>? _openWriteBatch;
  Future<void>? _writeTail;

  /// הפתיחה האחרונה יצרה את הקובץ — אין בו עדיין גרסת סכמה.
  bool get createdOnOpen => _createdOnOpen;
  bool _createdOnOpen = false;

  /// פותח את המסד בנתיב הזה במקום בתיקיית המסדים; לבדיקות בלבד.
  @visibleForTesting
  static UserStateDatabase openAt(String path) =>
      UserStateDatabase._().._pathOverride = path;

  @visibleForTesting
  void overridePath(String path) {
    close();
    _pathOverride = path;
  }

  /// המסד הפתוח, אחרי הכתיבות שכבר בתור: כתיבה על החיבור הזה בזמן שאצווה
  /// נכתבת ב-isolate הייתה נחסמת על הנעילה שלה, על ה-UI.
  Future<Database> get database async {
    // בלי כתיבה ממתינה אין await: מתחת ל-FakeAsync הוא לא היה מתקדם.
    if (_writeTail case final tail?) await _settled(tail);
    return _connection();
  }

  /// הפתיחה עצלה וסינכרונית — כמו `PersonalNotesDatabase`.
  Future<Database> _connection() async {
    final open = _database;
    if (open != null) return open;
    final path =
        _pathOverride ?? await AppPaths.resolveNotesDbPath('user_state.db');
    return _database ??= _open(path);
  }

  /// המסד הפתוח, כשכבר נפתח; לקוראים סינכרוניים שרצים אחרי האתחול.
  Database? get openDatabase => _database;

  Database _open(String path) {
    _path = path;
    // ההמתנה חוסמת את ה-thread המשותף לכל החלונות, ולכן קצרה: היא עוזרת
    // רק מול תהליך אחר (גיבוי, checkpoint).
    final db = openWritableDatabase(
      path,
      'UserStateDatabase',
      busyTimeoutMs: 1000,
    );
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
    // Drafts deliberately have no row in pending_reports. The offline updater
    // and report exporters only read the explicit outgoing queues.
    db.execute('''
      CREATE TABLE IF NOT EXISTS report_drafts (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        revision INTEGER NOT NULL
      )
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS report_draft_attachments (
        draft_id TEXT PRIMARY KEY REFERENCES report_drafts(id) ON DELETE CASCADE,
        payload_json TEXT NOT NULL
      )
    ''');
  }

  void _migrateSchema(Database db) {
    final current = firstIntValue(db.select('PRAGMA user_version')) ?? 0;
    _createdOnOpen = current == 0;
    if (current >= _schemaVersion) return;
    db.execute('PRAGMA user_version = $_schemaVersion');
  }

  /// מריץ את [statements] בטרנזקציה ב-isolate, אחרי הכתיבות שקדמו; מה
  /// שמצטבר בינתיים — באצווה אחת.
  Future<void> enqueueWrite(List<(String, List<Object?>)> statements) {
    if (_openWriteBatch case final open?) {
      open.addAll(statements);
      return _writeTail!;
    }
    final batch = _openWriteBatch = [...statements];
    final tail = _writeTail = _runWriteBatch(_writeTail, batch);
    _settled(tail).then((_) {
      if (identical(_writeTail, tail)) _writeTail = null;
    });
    return tail;
  }

  /// מנקז את כל הכתיבות, גם אלה שנכנסו בזמן הניקוז.
  Future<void> flushWrites() async {
    for (var tail = _writeTail; tail != null; tail = _writeTail) {
      await _settled(tail);
    }
  }

  /// מריץ את [body] בתור הכתיבות: אחרי מה שקדם, ו-[database] ממתין לו.
  /// [body] מקבל את החיבור הראשי, לקריאה בלבד.
  Future<R> runInWriteQueue<R>(Future<R> Function(Database db) body) {
    _openWriteBatch = null;
    final result = _runAfter(_writeTail, body);
    final tail = _writeTail = _settled(result);
    tail.then((_) {
      if (identical(_writeTail, tail)) _writeTail = null;
    });
    return result;
  }

  Future<R> _runAfter<R>(
    Future<void>? previous,
    Future<R> Function(Database db) body,
  ) async {
    if (previous != null) await _settled(previous);
    return body(await _connection());
  }

  /// מריץ את [body] על חיבור משני ב-isolate. כתיבה — רק מתוך [runInWriteQueue];
  /// קריאה בלבד מותרת גם מחוצה לו. [body] נשלח ל-isolate, ולכן נוצר בפונקציה סטטית.
  Future<R> runOnWriteConnection<R>(FutureOr<R> Function(Database db) body) =>
      _onWriteConnection(_path!, body, inline: debugWriteInline);

  Future<void> _runWriteBatch(
    Future<void>? previous,
    List<(String, List<Object?>)> batch,
  ) async {
    if (previous != null) await _settled(previous);
    _openWriteBatch = null;
    await _connection();
    await runOnWriteConnection(_batchWriter(batch));
  }

  // static: closure בתוך מתודת מופע הייתה לוכדת את this ונכשלת בשליחה.
  static void Function(Database db) _batchWriter(
    List<(String, List<Object?>)> batch,
  ) =>
      (db) => withTransaction(db, () {
        for (final (sql, args) in batch) {
          db.execute(sql, args);
        }
      });

  static Future<R> _onWriteConnection<R>(
    String path,
    FutureOr<R> Function(Database db) write, {
    required bool inline,
  }) {
    if (inline) return Future.sync(() => _withWriteConnection(path, write));
    return Isolate.run(
      () => _withWriteConnection(path, write),
      debugName: 'UserStateWrite',
    );
  }

  static Future<R> _withWriteConnection<R>(
    String path,
    FutureOr<R> Function(Database db) write,
  ) async {
    final db = openSecondaryWritableConnection(path, 'UserStateWrite');
    try {
      return await write(db);
    } finally {
      db.close();
    }
  }

  static Future<void> _settled(Future<Object?> future) =>
      future.then((_) {}, onError: (_) {});

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
    await flushWrites();
    close();
    await database;
  }
}
