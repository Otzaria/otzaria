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

  static String _kindPredicate(String? additionalKind) =>
      additionalKind == null ? 'kind = ?' : 'kind IN (?, ?)';

  Future<int> add(String kind, Map<String, dynamic> payload) async {
    final db = await _database.database;
    db.execute(
      'INSERT INTO pending_reports (kind, payload_json, created_at) '
      'VALUES (?, ?, ?)',
      [kind, jsonEncode(payload), DateTime.now().millisecondsSinceEpoch],
    );
    return db.lastInsertRowId;
  }

  Future<Map<String, dynamic>> addIfAbsent(
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final db = await _database.database;
    final encoded = jsonEncode(payload);
    db.execute('BEGIN IMMEDIATE');
    try {
      final rows = db.select(
        "SELECT payload_json FROM pending_reports "
        r"WHERE kind = ? AND json_extract(payload_json, '$.id') = ? LIMIT 1",
        [kind, payload['id']],
      );
      if (rows.isNotEmpty) {
        final stored =
            jsonDecode(rows.single['payload_json'] as String)
                as Map<String, dynamic>;
        db.execute('COMMIT');
        return stored;
      }
      db.execute(
        'INSERT INTO pending_reports (kind, payload_json, created_at) '
        'VALUES (?, ?, ?)',
        [kind, encoded, DateTime.now().millisecondsSinceEpoch],
      );
      db.execute('COMMIT');
      return payload;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// [whereField] מסנן ב-SQL לפי שדה בתוכן ששווה ל-[equals], כך ששורות
  /// שאינן מתאימות (או מעבר ל-[limit]) אינן מפוענחות כלל.
  Future<List<PendingReport>> listByKind(
    String kind, {
    String? additionalKind,
    String? whereField,
    Object? equals,
    int? limit,
  }) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT id, kind, payload_json, created_at FROM pending_reports '
      'WHERE ${_kindPredicate(additionalKind)}'
      '${whereField == null ? '' : ' AND json_extract(payload_json, ?) = ?'}'
      ' ORDER BY id LIMIT ?',
      [
        kind,
        ?additionalKind,
        if (whereField != null) ...['\$.$whereField', equals],
        limit ?? -1,
      ],
    );
    return rows.map(_decodeRow).toList();
  }

  /// Selects only row IDs. A bounded sender can load one attachment payload at
  /// a time instead of decoding a whole page of large reports into memory.
  Future<List<int>> listRowIds(
    String kind, {
    String? additionalKind,
    required int afterId,
    required int limit,
  }) async {
    if (afterId < 0 || limit < 1) throw ArgumentError('Invalid queue page');
    final db = await _database.database;
    return [
      for (final row in db.select(
        'SELECT id FROM pending_reports WHERE ${_kindPredicate(additionalKind)} AND id>? '
        'ORDER BY id LIMIT ?',
        [kind, ?additionalKind, afterId, limit],
      ))
        row['id'] as int,
    ];
  }

  /// Reads the report identity before acquiring its application-level lock,
  /// without bringing the report's attachments into the Dart heap.
  Future<String?> stringFieldForRow(
    String kind,
    int rowId,
    String field, {
    String? additionalKind,
  }) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT json_extract(payload_json, ?) AS value FROM pending_reports '
      'WHERE ${_kindPredicate(additionalKind)} AND id=?',
      ['\$.$field', kind, ?additionalKind, rowId],
    );
    final value = rows.isEmpty ? null : rows.single['value'];
    return value is String ? value : null;
  }

  Future<PendingReport?> findByRowId(
    String kind,
    int rowId, {
    String? additionalKind,
  }) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT id,kind,payload_json,created_at FROM pending_reports '
      'WHERE ${_kindPredicate(additionalKind)} AND id=?',
      [kind, ?additionalKind, rowId],
    );
    return rows.isEmpty ? null : _decodeRow(rows.single);
  }

  static const _flushCursorBox = 'report_queue_flush_progress';

  /// Local scheduling metadata, separate from every exported report payload.
  Future<int> readFlushCursor(String kind) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT payload_json FROM lists WHERE box=? AND key=?',
      [_flushCursorBox, kind],
    );
    if (rows.isEmpty) return 0;
    try {
      final value = jsonDecode(rows.single['payload_json'] as String);
      return value is int && value >= 0 ? value : 0;
    } on FormatException {
      // A bad scheduling marker may repeat a page, never discard reports.
      return 0;
    }
  }

  Future<void> writeFlushCursor(
    String kind,
    int rowId,
  ) => _database.enqueueWrite([
    (
      'INSERT INTO lists (box,key,payload_json,updated_at) VALUES (?,?,?,?) '
          'ON CONFLICT(box,key) DO UPDATE SET '
          'payload_json=excluded.payload_json,updated_at=excluded.updated_at',
      [
        _flushCursorBox,
        kind,
        jsonEncode(rowId),
        DateTime.now().millisecondsSinceEpoch,
      ],
    ),
  ]);

  /// מזהי השורות מסוג [kind] שהשדה [field] בתוכן שלהן שווה ל-[value].
  Future<List<int>> idsWhere(
    String kind,
    String field,
    Object? value, {
    String? additionalKind,
  }) async {
    final path = '\$.$field';
    // JSON booleans and numbers both extract as SQLite numbers; keep Dart's
    // equality rules, including absent fields comparing equal to null.
    final (predicate, arguments) = switch (value) {
      null => ('json_extract(payload_json, ?) IS NULL', [path]),
      String() => (
        "json_type(payload_json, ?) = 'text' AND "
            'json_extract(payload_json, ?) = ?',
        [path, path, value],
      ),
      bool() => (
        'json_type(payload_json, ?) = ?',
        [path, value ? 'true' : 'false'],
      ),
      num() => (
        "json_type(payload_json, ?) IN ('integer', 'real') AND "
            'json_extract(payload_json, ?) = ?',
        [path, path, value],
      ),
      _ => (null, const <Object?>[]),
    };
    if (predicate == null) return [];
    final db = await _database.database;
    return [
      for (final row in db.select(
        'SELECT id FROM pending_reports WHERE ${_kindPredicate(additionalKind)} AND ($predicate) '
        'ORDER BY id',
        [kind, ?additionalKind, ...arguments],
      ))
        row['id'] as int,
    ];
  }

  /// מחפש את הרשומה הראשונה מסוג [kind] שמזהה התוכן שלה הוא [reportId].
  Future<PendingReport?> findByPayloadId(
    String kind,
    String reportId, {
    String idField = 'id',
    String? additionalKind,
  }) async {
    final db = await _database.database;
    final path = '\$.$idField';
    final rows = db.select(
      'SELECT id, kind, payload_json, created_at FROM pending_reports '
      "WHERE ${_kindPredicate(additionalKind)} AND json_type(payload_json, ?) = 'text' "
      'AND json_extract(payload_json, ?) = ? ORDER BY id LIMIT 1',
      [kind, ?additionalKind, path, path, reportId],
    );
    return rows.isEmpty ? null : _decodeRow(rows.single);
  }

  static PendingReport _decodeRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['payload_json'] as String);
    return PendingReport(
      id: row['id'] as int,
      kind: row['kind'] as String,
      payload: decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{},
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  /// מעדכן את התוכן של שורה קיימת, בלי לשנות את מקומה בתור.
  Future<void> updatePayload(
    int id,
    Map<String, dynamic> payload, {
    String? kind,
  }) async {
    final db = await _database.database;
    db.execute(
      'UPDATE pending_reports SET payload_json = ?'
      '${kind == null ? '' : ', kind = ?'} WHERE id = ?',
      [jsonEncode(payload), ?kind, id],
    );
  }

  Future<int> countByKind(String kind, {String? additionalKind}) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT COUNT(*) FROM pending_reports WHERE ${_kindPredicate(additionalKind)}',
      [kind, ?additionalKind],
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

  Future<void> deleteAllOfKind(String kind, {String? additionalKind}) async {
    final db = await _database.database;
    db.execute(
      'DELETE FROM pending_reports WHERE ${_kindPredicate(additionalKind)}',
      [kind, ?additionalKind],
    );
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
