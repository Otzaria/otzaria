import 'dart:convert';

import 'package:otzaria/core/user_state/user_state_database.dart';

/// רשומה אחת בתור דיווחים.
class PendingReport {
  const PendingReport({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
  });

  final int id;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

/// תורי הדיווחים (שגיאות, תוספים) — שורה לכל דיווח.
///
/// הוספה היא `INSERT` ומחיקה היא לפי מזהה, ולכן שני חלונות שמדווחים
/// באותו רגע אינם דורסים זה את זה — בשונה מ"כתוב את כל הרשימה".
class PendingReportStore {
  PendingReportStore({UserStateDatabase? database})
    : _database = database ?? UserStateDatabase.instance;

  static final PendingReportStore instance = PendingReportStore();

  final UserStateDatabase _database;

  UserStateDatabase get database => _database;

  Future<int> add(String kind, Map<String, dynamic> payload) async {
    final db = await _database.database;
    db.execute(
      'INSERT INTO pending_reports (kind, payload_json, created_at) '
      'VALUES (?, ?, ?)',
      [kind, jsonEncode(payload), DateTime.now().millisecondsSinceEpoch],
    );
    return db.lastInsertRowId;
  }

  Future<List<PendingReport>> listByKind(String kind) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT id, kind, payload_json, created_at FROM pending_reports '
      'WHERE kind = ? ORDER BY id',
      [kind],
    );
    return rows.map((row) {
      final decoded = jsonDecode(row['payload_json'] as String);
      return PendingReport(
        id: row['id'] as int,
        kind: row['kind'] as String,
        payload: decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{},
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
        ),
      );
    }).toList();
  }

  /// מעדכן את התוכן של שורה קיימת, בלי לשנות את מקומה בתור.
  Future<void> updatePayload(int id, Map<String, dynamic> payload) async {
    final db = await _database.database;
    db.execute(
      'UPDATE pending_reports SET payload_json = ? WHERE id = ?',
      [jsonEncode(payload), id],
    );
  }

  Future<int> countByKind(String kind) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT COUNT(*) FROM pending_reports WHERE kind = ?',
      [kind],
    );
    return rows.first.values.first as int;
  }

  Future<void> deleteIds(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _database.database;
    final placeholders = List.filled(list.length, '?').join(',');
    db.execute(
      'DELETE FROM pending_reports WHERE id IN ($placeholders)',
      list,
    );
  }

  Future<void> deleteAllOfKind(String kind) async {
    final db = await _database.database;
    db.execute('DELETE FROM pending_reports WHERE kind = ?', [kind]);
  }

  /// משאיר רק את [keep] הרשומות האחרונות מסוג [kind].
  Future<void> trimKind(String kind, int keep) async {
    final db = await _database.database;
    db.execute(
      '''
      DELETE FROM pending_reports WHERE kind = ? AND id NOT IN (
        SELECT id FROM pending_reports WHERE kind = ?
        ORDER BY id DESC LIMIT ?
      )
      ''',
      [kind, kind, keep],
    );
  }
}
