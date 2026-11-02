import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';

/// שינוי ברשימה של [UserStateListStore]: שם המאגר ההיסטורי ומפתח בתוכו.
/// `origin` — מי שכתב; `null` בכתיבה שאינה של חלון מסוים.
typedef UserStateListChange = ({String box, String key, Object? origin});

/// רשימות מצב המשתמש (היסטוריה, סימניות, שולחנות) — רשימה שלמה לכל מפתח.
///
/// הפריטים אין להם מזהה יציב, ולכן היחידה היא הרשימה, ו-[mutate] מבטיח
/// read-modify-write אטומי: הכתיבה מחושבת מהמסד ולא מהעותק שבזיכרון של
/// חלון, ואף עדכון אינו נדרס. הכתיבות רצות ב-isolate, בתור של המסד.
class UserStateListStore {
  UserStateListStore({UserStateDatabase? database})
    : _database = database ?? UserStateDatabase.instance;

  static final UserStateListStore instance = UserStateListStore();

  final UserStateDatabase _database;
  final StreamController<UserStateListChange> _changes =
      StreamController<UserStateListChange>.broadcast();

  /// כל כתיבה משודרת עם ה-[origin] שלה, כדי שהכותב יוכל לסנן את עצמו.
  Stream<UserStateListChange> get changes => _changes.stream;

  Future<List<dynamic>> read(String box, String key) async =>
      decodePayload(await readPayload(box, key));

  /// ה-JSON הגולמי של הרשימה, לפענוח מחוץ ל-isolate של ה-UI.
  Future<String?> readPayload(String box, String key) async {
    final db = await _database.database;
    return _payloadIn(db, box, key);
  }

  static List<dynamic> decodePayload(String? payload) {
    if (payload == null) return const [];
    final decoded = jsonDecode(payload);
    return decoded is List ? decoded : const [];
  }

  Future<void> write(
    String box,
    String key,
    List<dynamic> value, {
    Object? origin,
  }) async {
    await _database.enqueueWrite([_upsert(box, key, jsonEncode(value))]);
    _notifyPeers(box, key, origin);
  }

  /// קורא, מחיל את [apply] וכותב — אטומי מול כל כותב אחר. מחזיר את הרשימה
  /// שנכתבה.
  ///
  /// [apply] לוכד אובייקטים שאינם נשלחים ל-isolate, ולכן רץ כאן; הכתיבה
  /// מותנית בכך שהרשימה לא השתנתה מאז הקריאה, ואחרת [apply] מוחל שוב.
  Future<List<dynamic>> mutate(
    String box,
    String key,
    List<dynamic> Function(List<dynamic> current) apply, {
    Object? origin,
  }) async {
    final result = await _database.runInWriteQueue((db) async {
      while (true) {
        final expected = _payloadIn(db, box, key);
        final next = apply(decodePayload(expected));
        final written = await _database.runOnWriteConnection(
          _replaceIfUnchanged(box, key, expected, jsonEncode(next)),
        );
        if (written) return next;
      }
    });
    _notifyPeers(box, key, origin);
    return result;
  }

  Future<void> clear(String box, String key, {Object? origin}) async {
    await _database.enqueueWrite([
      ('DELETE FROM lists WHERE box = ? AND key = ?', [box, key]),
    ]);
    _notifyPeers(box, key, origin);
  }

  static String? _payloadIn(Database db, String box, String key) {
    final rows = db.select(
      'SELECT payload_json FROM lists WHERE box = ? AND key = ?',
      [box, key],
    );
    return rows.isEmpty ? null : rows.first['payload_json'] as String;
  }

  static (String, List<Object?>) _upsert(
    String box,
    String key,
    String payload,
  ) => (
    '''
    INSERT INTO lists (box, key, payload_json, updated_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(box, key) DO UPDATE SET
      payload_json = excluded.payload_json,
      updated_at = excluded.updated_at
    ''',
    [box, key, payload, DateTime.now().millisecondsSinceEpoch],
  );

  /// `BEGIN IMMEDIATE` תופס את נעילת הכתיבה כבר בפתיחה, ולכן ההשוואה
  /// ל-[expected] תקפה עד ה-COMMIT. רץ ב-isolate, ולכן static.
  static bool Function(Database db) _replaceIfUnchanged(
    String box,
    String key,
    String? expected,
    String payload,
  ) => (db) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final unchanged = _payloadIn(db, box, key) == expected;
      if (unchanged) {
        final (sql, args) = _upsert(box, key, payload);
        db.execute(sql, args);
      }
      db.execute('COMMIT');
      return unchanged;
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {
        // הכשל המקורי הוא שמעניין.
      }
      rethrow;
    }
  };

  void _notifyPeers(String box, String key, Object? origin) =>
      _changes.add((box: box, key: key, origin: origin));

  @visibleForTesting
  void dispose() => _changes.close();
}
