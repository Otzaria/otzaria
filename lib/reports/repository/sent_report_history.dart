import 'dart:math';

import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/services/sent_reports_counter.dart';

/// היסטוריה מוגבלת בגודל ומונה מצטבר של דיווחים שנשלחו.
class SentReportHistory<T> {
  SentReportHistory({
    PendingReportStore? store,
    SentReportsCounter? counter,
    required String boxName,
    required this._kind,
    required this._idField,
    required this._limit,
    required this._fromJson,
    this._rejectionField,
  }) : _store = store ?? PendingReportStore.instance,
       _counter =
           counter ??
           SentReportsCounter(boxName: boxName, database: store?.database);

  final PendingReportStore _store;
  final SentReportsCounter _counter;
  final String _kind;
  final String _idField;
  final int _limit;
  final T Function(Map<String, dynamic>) _fromJson;
  final String? _rejectionField;

  /// הרשומות מהחדשה לישנה.
  Future<List<T>> list() async => (await _store.listByKind(
    _kind,
  )).reversed.map((row) => _fromJson(row.payload)).toList();

  Future<int> total() async {
    final total = await _counter.read();
    final summary = await _store.readHistorySummary(
      _kind,
      rejectionField: _rejectionField,
    );
    return max(total, summary.keptCount);
  }

  Future<T?> find(String reportId) async {
    final row = await _store.findByPayloadId(
      _kind,
      reportId,
      idField: _idField,
    );
    return row == null ? null : _fromJson(row.payload);
  }

  Future<bool> contains(String reportId) async =>
      (await _idsOf(reportId)).isNotEmpty;

  Future<void> delete(String reportId) async =>
      _store.deleteIds(await _idsOf(reportId));

  Future<void> clear() async {
    await _store.deleteAllOfKind(_kind);
    await _counter.reset();
  }

  /// מחליף רשומה באותו מזהה בלי לספור אותה פעמיים.
  Future<void> save(
    String reportId,
    Map<String, dynamic> payload, {
    bool countAsSent = true,
  }) async {
    final summary = await _store.readHistorySummary(
      _kind,
      matchId: (field: _idField, value: reportId),
      rejectionField: _rejectionField,
    );
    await _store.deleteIds(summary.matchingIds);
    await _store.add(_kind, payload);
    await _store.trimKind(_kind, _limit);
    if (countAsSent && summary.matchingIds.isEmpty) {
      await _counter.increment(floor: summary.keptCount);
    }
  }

  Future<List<int>> _idsOf(String reportId) =>
      _store.idsWhere(_kind, _idField, reportId);
}
