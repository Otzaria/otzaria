import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

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

  /// מעל האורך הזה (בתווים) הרשימה נקראת ומפוענחת ב-isolate. בבדיקת widget
  /// טעינה כזו מסתיימת רק בתוך tester.runAsync.
  static const int inlineDecodeMaxLength = 64 * 1024;

  Future<List<dynamic>> read(String box, String key) =>
      readDecoded(box, key, decodePayload);

  /// מחיל את [decode] על ה-JSON הגולמי של הרשימה. ברשימה ארוכה גם ה-SELECT
  /// וגם [decode] רצים ב-isolate, ולכן [decode] חייב להיווצר בפונקציה סטטית.
  Future<R> readDecoded<R>(
    String box,
    String key,
    R Function(String? payload) decode,
  ) async {
    final db = await _database.database;
    final length = _payloadLengthIn(db, box, key);
    if (length == null || length < inlineDecodeMaxLength) {
      return decode(_payloadIn(db, box, key));
    }
    return _database.runOnWriteConnection(_reader(box, key, decode));
  }

  static R Function(Database db) _reader<R>(
    String box,
    String key,
    R Function(String? payload) decode,
  ) =>
      (db) => decode(_payloadIn(db, box, key));

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
  /// [apply] רץ פעם אחת ב-isolate הקורא, בזמן שה-worker מחזיק נעילת כתיבה;
  /// פענוח ה-JSON וקידודו רצים ב-worker.
  Future<List<dynamic>> mutate(
    String box,
    String key,
    List<dynamic> Function(List<dynamic> current) apply, {
    Object? origin,
  }) async {
    final result = await _database.runInWriteQueue((db) async {
      late List<dynamic> next;
      List<dynamic> replace(List<dynamic> current) => next = apply(current);

      if (UserStateDatabase.debugWriteInline) {
        await _mutateLocked(db, box, key, replace);
      } else {
        final requests = ReceivePort();
        final written = _database.runOnWriteConnection(
          _mutateWriter(box, key, requests.sendPort),
        );
        SendPort? response;
        try {
          final (port, current) =
              await Future.any([
                    requests.first,
                    written.then(
                      (_) => throw StateError('Missing mutation request'),
                    ),
                  ])
                  as (SendPort, List<dynamic>);
          response = port;
          response.send(replace(current));
          await written;
        } catch (_) {
          response?.send(null);
          await written;
          rethrow;
        } finally {
          requests.close();
        }
      }
      return next;
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

  static int? _payloadLengthIn(Database db, String box, String key) {
    final rows = db.select(
      'SELECT length(payload_json) AS n FROM lists WHERE box = ? AND key = ?',
      [box, key],
    );
    return rows.isEmpty ? null : rows.first['n'] as int;
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

  static Future<void> Function(Database db) _mutateWriter(
    String box,
    String key,
    SendPort requests,
  ) =>
      (db) => _mutateLocked(db, box, key, (current) async {
        final responses = ReceivePort();
        try {
          requests.send((responses.sendPort, current));
          return await responses.first as List<dynamic>?;
        } finally {
          responses.close();
        }
      });

  static Future<void> _mutateLocked(
    Database db,
    String box,
    String key,
    FutureOr<List<dynamic>?> Function(List<dynamic> current) replace,
  ) async {
    db.execute('BEGIN IMMEDIATE');
    try {
      final next = await replace(decodePayload(_payloadIn(db, box, key)));
      if (next == null) {
        db.execute('ROLLBACK');
      } else {
        final (sql, args) = _upsert(box, key, jsonEncode(next));
        db.execute(sql, args);
        db.execute('COMMIT');
      }
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {
        // הכשל המקורי הוא שמעניין.
      }
      rethrow;
    }
  }

  void _notifyPeers(String box, String key, Object? origin) =>
      _changes.add((box: box, key: key, origin: origin));

  @visibleForTesting
  void dispose() => _changes.close();
}
