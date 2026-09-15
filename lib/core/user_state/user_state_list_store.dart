import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';

/// מפתח של רשימה ב-[UserStateListStore]: שם המאגר ההיסטורי ומפתח בתוכו.
typedef UserStateListKey = ({String box, String key});

/// רשימות מצב המשתמש (היסטוריה, סימניות, שולחנות) — רשימה שלמה לכל מפתח.
///
/// הפריטים אין להם מזהה יציב, ולכן היחידה היא הרשימה, ו-[mutate] מבטיח
/// read-modify-write אטומי בטרנזקציה `BEGIN IMMEDIATE`: שני חלונות שכותבים
/// באותו רגע מסתדרים בנעילה, ואף עדכון אינו נדרס.
class UserStateListStore {
  UserStateListStore({UserStateDatabase? database, WindowBus? bus})
    : _database = database ?? UserStateDatabase.instance,
      _bus = bus ?? WindowBus.instance;

  static final UserStateListStore instance = UserStateListStore();

  /// הודעת האפיק "רשימה השתנתה בחלון אחר".
  static const String requestChanged = 'userStateChanged';

  final UserStateDatabase _database;
  final WindowBus _bus;
  final StreamController<UserStateListKey> _changes =
      StreamController<UserStateListKey>.broadcast();

  /// רשימות ששונו **בחלון אחר**. כתיבה מקומית אינה משודרת לעצמה.
  Stream<UserStateListKey> get changes => _changes.stream;

  Future<List<dynamic>> read(String box, String key) async {
    final db = await _database.database;
    return _readIn(db, box, key);
  }

  Future<void> write(String box, String key, List<dynamic> value) async {
    final db = await _database.database;
    _withImmediateTransaction(db, () => _writeIn(db, box, key, value));
    _notifyPeers(box, key);
  }

  /// קורא, מחיל את [apply] וכותב — הכול בטרנזקציה אחת. מחזיר את הרשימה
  /// שנכתבה.
  Future<List<dynamic>> mutate(
    String box,
    String key,
    List<dynamic> Function(List<dynamic> current) apply,
  ) async {
    final db = await _database.database;
    late List<dynamic> result;
    _withImmediateTransaction(db, () {
      result = apply(_readIn(db, box, key));
      _writeIn(db, box, key, result);
    });
    _notifyPeers(box, key);
    return result;
  }

  Future<void> clear(String box, String key) async {
    final db = await _database.database;
    db.execute('DELETE FROM lists WHERE box = ? AND key = ?', [box, key]);
    _notifyPeers(box, key);
  }

  /// מטפל בהודעת [requestChanged] שהגיעה באפיק. מחזיר null כשאינה שלנו.
  Object? handleRequest(Map<String, dynamic> request) {
    if (request['type'] != requestChanged) return null;
    final box = request['box'];
    final key = request['key'];
    if (box is! String || key is! String) return null;
    if (request['origin'] != _bus.slot) _changes.add((box: box, key: key));
    return true;
  }

  List<dynamic> _readIn(Database db, String box, String key) {
    final rows = db.select(
      'SELECT payload_json FROM lists WHERE box = ? AND key = ?',
      [box, key],
    );
    if (rows.isEmpty) return const [];
    final decoded = jsonDecode(rows.first['payload_json'] as String);
    return decoded is List ? decoded : const [];
  }

  void _writeIn(Database db, String box, String key, List<dynamic> value) {
    db.execute(
      '''
      INSERT INTO lists (box, key, payload_json, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(box, key) DO UPDATE SET
        payload_json = excluded.payload_json,
        updated_at = excluded.updated_at
      ''',
      [box, key, jsonEncode(value), DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// `BEGIN IMMEDIATE` תופס את נעילת הכתיבה כבר בפתיחה, ולכן הקריאה שבתוך
  /// הטרנזקציה רואה את המצב שאף חלון אחר לא ישנה עד ה-COMMIT.
  /// ⚠️ בלי ניסיון חוזר: כל החלונות חולקים thread אחד, ולכן נעילה של
  /// חלון אחר בתהליך אינה יכולה להשתחרר בזמן שאנחנו ממתינים לה.
  void _withImmediateTransaction(Database db, void Function() body) {
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

  /// fire-and-forget: חלון שלא קיבל את ההודעה יקרא את הערך הנכון בפעם
  /// הבאה שיטען את הרשימה.
  void _notifyPeers(String box, String key) {
    final slot = _bus.slot;
    if (slot == null) return;
    try {
      _bus.broadcast({
        'type': requestChanged,
        'box': box,
        'key': key,
        'origin': slot,
      });
    } catch (e) {
      debugPrint('UserStateListStore broadcast failed: $e');
    }
  }

  @visibleForTesting
  void dispose() => _changes.close();
}
