import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';

/// A local, possibly incomplete form. Never a transport report.
class ReportDraftRecord {
  const ReportDraftRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.attachments = const {},
  });

  final String id;
  final String kind;
  final String title;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
}

class ReportDraftConflict implements Exception {
  const ReportDraftConflict();
}

/// Draft text and large attachments have different write lifetimes. Text saves
/// only replace the small form record; unchanged attachment bytes stay on disk.
class ReportDraftStore {
  ReportDraftStore({UserStateDatabase? database, DateTime Function()? clock})
    : _database = database ?? UserStateDatabase.instance,
      _clock = clock ?? DateTime.now;

  static final ReportDraftStore instance = ReportDraftStore();
  static final Expando<ReportDraftStore> _stores = Expando();

  static ReportDraftStore forDatabase(UserStateDatabase database) {
    if (identical(database, UserStateDatabase.instance)) return instance;
    return _stores[database] ??= ReportDraftStore(database: database);
  }

  static const appKind = 'app';
  static const bookKind = 'book';
  final UserStateDatabase _database;
  final DateTime Function() _clock;
  final ValueNotifier<int> changes = ValueNotifier(0);

  /// Summaries exclude attachment bytes, including when opening Settings.
  Future<List<ReportDraftRecord>> list({String? kind}) async {
    final db = await _database.database;
    return db
        .select(
          'SELECT * FROM report_drafts '
          '${kind == null ? '' : 'WHERE kind = ? '}ORDER BY updated_at DESC, id',
          [?kind],
        )
        .map(_decode)
        .toList();
  }

  Future<ReportDraftRecord?> read(String id) async {
    final db = await _database.database;
    final rows = db.select(
      'SELECT d.*, a.payload_json AS attachments_json FROM report_drafts d '
      'LEFT JOIN report_draft_attachments a ON a.draft_id = d.id WHERE d.id = ?',
      [id],
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  /// revision zero creates once; all later writes require the existing row and
  /// observed revision. A deleted draft can never be recreated by a stale form.
  Future<int> write({
    required String id,
    required String kind,
    required String title,
    required Map<String, dynamic> payload,
    required int revision,
    Map<String, dynamic>? attachments,
  }) async {
    final encoded = jsonEncode(payload);
    final encodedAttachments = attachments == null
        ? null
        : jsonEncode(attachments);
    final now = _clock().millisecondsSinceEpoch;
    final saved = await _database.runInWriteQueue(
      (_) => _database.runOnWriteConnection(
        _writer(id, kind, title, encoded, encodedAttachments, revision, now),
      ),
    );
    if (!saved) throw const ReportDraftConflict();
    changes.value++;
    return revision + 1;
  }

  static bool Function(Database) _writer(
    String id,
    String kind,
    String title,
    String payload,
    String? attachments,
    int revision,
    int now,
  ) => (db) {
    var saved = false;
    withTransaction(db, () {
      if (revision == 0) {
        db.execute(
          'INSERT OR IGNORE INTO report_drafts '
          '(id,kind,title,payload_json,created_at,updated_at,revision) '
          'VALUES (?,?,?,?,?,?,1)',
          [id, kind, title, payload, now, now],
        );
      } else {
        db.execute(
          'UPDATE report_drafts SET title=?, payload_json=?, updated_at=?, '
          'revision=revision+1 WHERE id=? AND revision=?',
          [title, payload, now, id, revision],
        );
      }
      if (db.updatedRows == 0) return;
      if (attachments != null) {
        db.execute(
          'INSERT INTO report_draft_attachments (draft_id,payload_json) VALUES (?,?) '
          'ON CONFLICT(draft_id) DO UPDATE SET payload_json=excluded.payload_json',
          [id, attachments],
        );
      }
      saved = true;
    });
    return saved;
  };

  /// An explicit Settings discard can delete any revision. A form session must
  /// provide its revision so completing an older form cannot delete newer work.
  /// Missing rows are already complete and can be finalized repeatedly.
  Future<void> delete(String id, {int? revision}) async {
    final deleted = await _database.runInWriteQueue(
      (_) => _database.runOnWriteConnection(_deleter(id, revision)),
    );
    if (!deleted) throw const ReportDraftConflict();
    changes.value++;
  }

  static bool Function(Database) _deleter(String id, int? revision) => (db) {
    var deleted = false;
    withTransaction(db, () {
      final rows = db.select('SELECT revision FROM report_drafts WHERE id=?', [
        id,
      ]);
      if (rows.isNotEmpty &&
          revision != null &&
          rows.single['revision'] != revision) {
        return;
      }
      db.execute('DELETE FROM report_draft_attachments WHERE draft_id=?', [id]);
      db.execute('DELETE FROM report_drafts WHERE id=?', [id]);
      deleted = true;
    });
    return deleted;
  };

  static ReportDraftRecord _decode(
    Map<String, Object?> row,
  ) => ReportDraftRecord(
    id: row['id'] as String,
    kind: row['kind'] as String,
    title: row['title'] as String,
    payload: Map<String, dynamic>.from(
      jsonDecode(row['payload_json'] as String),
    ),
    attachments: row['attachments_json'] == null
        ? const {}
        : Map<String, dynamic>.from(
            jsonDecode(row['attachments_json'] as String),
          ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    revision: row['revision'] as int,
  );
}

/// Serializes saves and termination. Setting _finished synchronously prevents
/// a late autosave from overtaking send/queue/discard, even while disk is busy.
class ReportDraftSession {
  ReportDraftSession({
    required this.store,
    required this.id,
    this.revision = 0,
  });
  final ReportDraftStore store;
  final String id;
  int revision;
  bool _finished = false;
  Future<void> _tail = Future.value();
  Future<void> _lastOperation = Future.value();
  bool get isFinished => _finished;

  Future<void> flush() => _lastOperation;

  Future<void> save({
    required String kind,
    required String title,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? attachments,
  }) {
    if (_finished) return Future.value();
    final result = _tail.then((_) async {
      if (_finished) return;
      revision = await store.write(
        id: id,
        kind: kind,
        title: title,
        payload: payload,
        revision: revision,
        attachments: attachments,
      );
    });
    _lastOperation = result;
    _tail = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// A completed form may close while a newer revision stays with its owner.
  /// Storage failures still allow retry; a stale form never deletes newer work.
  Future<void> finish({bool preserveNewerRevision = false}) {
    _finished = true;
    final result = _tail.then((_) async {
      try {
        await store.delete(id, revision: revision);
      } on ReportDraftConflict {
        if (preserveNewerRevision) return;
        _finished = false;
        rethrow;
      } catch (_) {
        _finished = false;
        rethrow;
      }
    });
    _lastOperation = result;
    _tail = result.then((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
