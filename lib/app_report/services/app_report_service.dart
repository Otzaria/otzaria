import 'dart:async';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

export 'package:otzaria/services/offline_report_script_builder.dart'
    show OfflineSendScript, OfflineSendScriptTarget;

enum AppReportDeliveryStatus { sent, queued, failed }

/// סיבת כשל קבוע במסירה.
enum AppReportFailureReason {
  /// מצב לא-מקוון והתור האוטומטי כבוי בהגדרות.
  offlineQueueDisabled,

  /// השרת דחה את התוכן (400/413/422) — אין טעם לנסות שוב.
  rejected,

  /// השרת החזיק תוכן אחר באותו מזהה גם אחרי החלפת המזהה.
  idConflict,
}

/// תוצאת שליחת דיווח על התוכנה.
class AppReportDeliveryResult {
  const AppReportDeliveryResult({
    required this.status,
    required this.report,
    this.failureReason,
    this.httpStatus,
    this.rejectedField,
  });

  final AppReportDeliveryStatus status;

  /// הרשומה כפי שנשמרה (עם מזהה חדש אחרי 409, ומספר ה-issue אחרי שליחה).
  final AppReport report;
  final AppReportFailureReason? failureReason;
  final int? httpStatus;

  /// שם השדה שהשרת דחה ב-422, אם החזיר.
  final String? rejectedField;

  bool get isSent => status == AppReportDeliveryStatus.sent;
  bool get isQueued => status == AppReportDeliveryStatus.queued;

  int? get issueNumber => report.issueNumber;

  /// נוסף כתגובה ל-issue פתוח עם אותה חתימה.
  bool get merged => report.merged;

  /// נשמר בשרת, ה-issue ייפתח מאוחר יותר.
  bool get issuePending => report.issuePending;
}

/// שליחת דיווחים על התוכנה לאתר, שפותח מהם issue ב-GitHub.
///
/// אותו דפוס כמו דיווחי הספרים והתוספים: כשל זמני (429/5xx/רשת) או מצב
/// לא-מקוון שומרים בתור עם ניסיון חוזר; 400/413/422 הם דחייה קבועה.
class AppReportService {
  AppReportService({
    http.Client? client,
    PendingReportStore? reportStore,
    SentReportsCounter? sentCounter,
    DateTime Function()? clock,
  }) : _client = client ?? _shared,
       _reports = reportStore ?? PendingReportStore.instance,
       _sentCounter =
           sentCounter ??
           SentReportsCounter(
             boxName: queueBoxName,
             database: reportStore?.database,
           ),
       _clock = clock ?? DateTime.now;

  static final Uri endpoint = Uri.parse('https://otzaria.org/api/app-reports');

  static const String queueBoxName = 'app_reports_queue';
  static const String pendingReportsKey = 'pending_reports_v2';
  static const String legacyPendingKind = '$queueBoxName/pending_reports';
  static const String sentReportsKey = 'sent_reports';
  static const String pendingKind = kAppReportsPendingKindV2;
  static const String sentKind = '$queueBoxName/$sentReportsKey';

  /// טיוטה אחת של הטופס הידני; לא בתור, ולכן לא נשלחת אוטומטית.
  static const String draftKind = '$queueBoxName/draft';
  static const int maxSentReportsToKeep = 100;
  static const Duration timeout = Duration(seconds: 10);

  /// צילומי מסך ו-minidump הם מגה-בתים רבים; בחיבור איטי 10 שניות לא מספיקות.
  static const Duration timeoutWithImages = Duration(minutes: 2);
  static const Duration _flushInterval = Duration(minutes: 5);
  static const int _maxQueuedFlushPerRun = 20;

  static Timer? _flushTimer;
  static bool _isFlushing = false;
  static Completer<void>? _flushInFlight;
  static final Map<String, Future<void>> _reportOperationTails = {};

  static final http.Client _shared = _createClient();

  static http.Client _createClient() {
    final client = http.Client();
    HttpClientRegistry.register(client.close);
    return client;
  }

  final http.Client _client;
  final PendingReportStore _reports;
  final SentReportsCounter _sentCounter;
  final DateTime Function() _clock;

  /// עוצר את השליחה האוטומטית וממתין לשליחה שבאמצע (שחזור מגיבוי).
  static Future<void> suspendAutomaticFlush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushInFlight?.future;
  }

  bool get _queueWhenOfflineEnabled =>
      Settings.getValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
      ) ??
      true;

  bool get _isOfflineMode =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  /// שולח דיווח; בכשל זמני או במצב לא-מקוון שומר אותו בתור.
  Future<AppReportDeliveryResult> send(AppReport report) =>
      _withReportLock(report.reportId, () => _send(report));

  Future<AppReportDeliveryResult> _send(AppReport report) async {
    final alreadySent = await _sentReport(report.reportId);
    if (alreadySent != null) {
      await _deletePendingReport(report.reportId);
      return AppReportDeliveryResult(
        status: AppReportDeliveryStatus.sent,
        report: alreadySent,
      );
    }
    final invalidField = report.validate();
    if (invalidField != null) {
      return AppReportDeliveryResult(
        status: AppReportDeliveryStatus.failed,
        report: report,
        failureReason: AppReportFailureReason.rejected,
        rejectedField: invalidField,
      );
    }
    if (_isOfflineMode) {
      if (!_queueWhenOfflineEnabled) {
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.failed,
          report: report,
          failureReason: AppReportFailureReason.offlineQueueDisabled,
        );
      }
      await _enqueueIfNeeded(report);
      return AppReportDeliveryResult(
        status: AppReportDeliveryStatus.queued,
        report: report,
      );
    }

    var (current, attempt) = await _trySendDroppingRejectedMinidump(report);
    // 409: התוכן הזה לא נקלט תחת המזהה — הגשה חדשה במזהה חדש.
    if (attempt.kind == _AttemptKind.idConflict) {
      (current, attempt) = await _trySendDroppingRejectedMinidump(
        current.copyWith(reportId: AppReport.generateReportId()),
      );
    }

    switch (attempt.kind) {
      case _AttemptKind.success:
        final sent = _sentRecord(current, attempt);
        await _saveSentReport(sent);
        unawaited(flushPendingReports());
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.sent,
          report: sent,
          httpStatus: attempt.httpStatus,
        );
      case _AttemptKind.permanent:
      case _AttemptKind.idConflict:
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.failed,
          report: current,
          failureReason: attempt.kind == _AttemptKind.idConflict
              ? AppReportFailureReason.idConflict
              : AppReportFailureReason.rejected,
          httpStatus: attempt.httpStatus,
          rejectedField: attempt.rejectedField,
        );
      case _AttemptKind.transient:
        await _enqueueIfNeeded(current);
        return AppReportDeliveryResult(
          status: AppReportDeliveryStatus.queued,
          report: current,
          httpStatus: attempt.httpStatus,
        );
    }
  }

  /// Keeps the queued copy until delivery or a replacement queue entry succeeds.
  Future<AppReportDeliveryResult> submitPendingReport(AppReport report) =>
      _withReportLock(report.reportId, () async {
        final result = await _send(report);
        if (result.status == AppReportDeliveryStatus.sent ||
            (result.status == AppReportDeliveryStatus.queued &&
                result.report.reportId != report.reportId)) {
          await _deletePendingReport(report.reportId);
        }
        return result;
      });

  /// מעביר דיווח מהתור להיסטוריה בלי לשלוח — כשנשלח בדרך אחרת (סקריפט).
  Future<void> markPendingReportAsSent(AppReport report) =>
      _withReportLock(report.reportId, () async {
        await _saveSentReport(
          report.withoutAttachments().copyWith(sentAt: _clock()),
        );
        await _deletePendingReport(report.reportId);
      });

  /// שומר דיווח בתור בלי לנסות לשלוח.
  Future<void> queueReport(AppReport report) =>
      _withReportLock(report.reportId, () => _enqueueIfNeeded(report));

  // Older collectors whitelist the legacy kind. Moving rows preserves their
  // content/schema while keeping v2 edits out of an old collector's reach.
  /// Upgrades only the queue kind, preserving every payload and schema.
  /// Backup uses this before reading the outgoing queues.
  Future<void> prepareQueueStorage() => _ensureQueueFormat();

  Future<void> _ensureQueueFormat() => _reports.database.enqueueWrite([
    (
      'UPDATE pending_reports SET kind = ? WHERE kind = ?',
      [pendingKind, legacyPendingKind],
    ),
  ]);

  Future<int> getPendingReportsCount() async {
    await _ensureQueueFormat();
    return _reports.countByKind(pendingKind);
  }

  Future<List<AppReport>> getPendingReports() async {
    await _ensureQueueFormat();
    return (await _reports.listByKind(pendingKind)).map(_decode).toList();
  }

  /// היסטוריית הנשלחים, מהחדש לישן.
  Future<List<AppReport>> getSentReports() async =>
      (await _reports.listByKind(sentKind)).reversed.map(_decode).toList();

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() async {
    final total = await _sentCounter.read();
    final kept = await _reports.countByKind(sentKind);
    return total > kept ? total : kept;
  }

  ReportDraftSession? _draftSession;
  AppReportDraft? _lastDraft;
  ReportDraftStore get draftStore =>
      ReportDraftStore.forDatabase(_reports.database);

  /// Moves the old manual draft out of the outgoing-queue storage once. The
  /// deterministic ID makes migration safe if interrupted before legacy delete.
  Future<void> migrateLegacyDraft() async {
    for (final legacy in await _reports.listByKind(draftKind)) {
      final draft = AppReportDraft.fromJson(legacy.payload);
      if (draft == null) continue;
      final id = 'legacy-app-${legacy.id}';
      if (await draftStore.read(id) == null) {
        try {
          await draftStore.write(
            id: id,
            kind: ReportDraftStore.appKind,
            title: draft.title,
            payload: draft.toJson(includeAttachments: false),
            attachments: draft.attachmentsJson(),
            revision: 0,
          );
        } on ReportDraftConflict {
          // Another window completed the same deterministic migration.
        }
      }
      await _reports.deleteIds([legacy.id]);
    }
  }

  Future<AppReportDraft?> loadDraft({String? draftId}) async {
    await migrateLegacyDraft();
    final id =
        draftId ??
        (await draftStore.list(kind: ReportDraftStore.appKind)).firstOrNull?.id;
    final row = id == null ? null : await draftStore.read(id);
    if (draftId != null && row == null) throw const ReportDraftConflict();
    _draftSession = ReportDraftSession(
      store: draftStore,
      id: row?.id ?? AppReport.generateReportId(),
      revision: row?.revision ?? 0,
    );
    _lastDraft = row == null
        ? null
        : AppReportDraft.fromJson({...row.payload, ...row.attachments});
    if (row != null && _lastDraft == null) {
      throw const FormatException('The saved report draft could not be decoded.');
    }
    return _lastDraft;
  }

  Future<void> saveDraft(AppReportDraft draft) async {
    final session = _draftSession ??= ReportDraftSession(
      store: draftStore,
      id: AppReport.generateReportId(),
    );
    final previous = _lastDraft;
    final attachmentsChanged =
        previous == null ||
        !identical(previous.images, draft.images) ||
        !identical(previous.diagnostics, draft.diagnostics) ||
        previous.errorLog != draft.errorLog ||
        !identical(previous.minidump, draft.minidump);
    await session.save(
      kind: ReportDraftStore.appKind,
      title: draft.title,
      payload: draft.toJson(includeAttachments: false),
      attachments: attachmentsChanged ? draft.attachmentsJson() : null,
    );
    _lastDraft = draft;
  }

  Future<void> deleteDraft() async {
    await _draftSession?.finish(preserveNewerRevision: true);
    _lastDraft = null;
    // A new edit after an explicit discard gets a new identity.
    _draftSession = null;
  }

  Future<void> deletePendingReport(String reportId) =>
      _withReportLock(reportId, () => _deletePendingReport(reportId));

  Future<void> _deletePendingReport(String reportId) async =>
      _reports.deleteIds(await _rowIdsOf(pendingKind, reportId));

  Future<void> deleteSentReport(String reportId) => _withReportLock(
    reportId,
    () async => _reports.deleteIds(await _rowIdsOf(sentKind, reportId)),
  );

  Future<void> clearPendingReports() async {
    await _ensureQueueFormat();
    await _reports.deleteAllOfKind(pendingKind);
  }

  Future<void> clearSentReports() async {
    await _reports.deleteAllOfKind(sentKind);
    await _sentCounter.reset();
  }

  /// מעדכן דיווח בתור לפי [AppReport.reportId]. תוכן ששונה מקבל מזהה חדש,
  /// כי ייתכן שהגרסה הקודמת כבר נקלטה והשרת היה דוחה אותה ב-409.
  Future<AppReport?> updatePendingReport(AppReport report) =>
      _withReportLock(report.reportId, () => _updatePendingReport(report));

  Future<AppReport?> _updatePendingReport(AppReport report) async {
    await _ensureQueueFormat();
    final row = await _reports.findByPayloadId(
      pendingKind,
      report.reportId,
      idField: 'reportId',
    );
    if (row == null) return null;
    // This API is an explicit edit/save action. Retrying and restoring old
    // reports keep their schema; an intentional edit adopts the current limits.
    final edited = report.copyWith(schema: AppReport.schemaVersion);
    final invalidField = edited.validate();
    if (invalidField != null) {
      throw FormatException('Report is not ready for transport: $invalidField');
    }
    final previous = _decode(row);
    final changed =
        jsonEncode(_contentOf(previous)) != jsonEncode(_contentOf(edited));
    final updated = changed
        ? edited.copyWith(reportId: AppReport.generateReportId())
        : edited;
    await _reports.updatePayload(row.id, updated.toJson());
    return updated;
  }

  /// שולח מנה מהתור בסבב מתמשך; עוצר בכשל זמני ושומר דחיות לעריכה.
  /// מחזיר את מספר הדיווחים שנשלחו, בלי להיתקע על הדחויים הראשונים.
  Future<int> flushPendingReports() async {
    if (_isOfflineMode || _isFlushing) return 0;

    _isFlushing = true;
    final inFlight = _flushInFlight = Completer<void>();
    try {
      await _ensureQueueFormat();
      final cursor = await _reports.readFlushCursor(pendingKind);
      var rowIds = await _reports.listRowIds(
        pendingKind,
        afterId: cursor,
        limit: _maxQueuedFlushPerRun,
      );
      if (rowIds.isEmpty && cursor > 0) {
        rowIds = await _reports.listRowIds(
          pendingKind,
          afterId: 0,
          limit: _maxQueuedFlushPerRun,
        );
      }
      var sentCount = 0;
      for (final rowId in rowIds) {
        final reportId = await _reports.stringFieldForRow(
          pendingKind,
          rowId,
          'reportId',
        );
        if (reportId == null) {
          // A deleted or unidentifiable row cannot block the rest of the queue.
          // Unidentifiable data stays stored for inspection or explicit removal.
          await _reports.writeFlushCursor(pendingKind, rowId);
          continue;
        }
        final shouldStop = await _withReportLock(reportId, () async {
          final currentRow = await _reports.findByRowId(pendingKind, rowId);
          if (currentRow == null) return false;
          final queued = _decode(currentRow);
          // An edit may have replaced its identity while this lock was pending.
          // Leave that new report for a later page under its own identity lock.
          if (queued.reportId != reportId) return false;
          if (await _sentReport(queued.reportId) != null) {
            await _reports.deleteIds([currentRow.id]);
            return false;
          }
          final (report, attempt) = await _trySendDroppingRejectedMinidump(
            queued,
          );
          switch (attempt.kind) {
            case _AttemptKind.success:
              await _saveSentReport(_sentRecord(report, attempt));
              await _reports.deleteIds([currentRow.id]);
              sentCount++;
              return false;
            case _AttemptKind.idConflict:
              await _reports.updatePayload(
                currentRow.id,
                report
                    .copyWith(reportId: AppReport.generateReportId())
                    .toJson(),
              );
              return false;
            case _AttemptKind.permanent:
              debugPrint(
                'App report rejected, kept for editing: ${report.reportId}',
              );
              return false;
            case _AttemptKind.transient:
              if (queued.minidump != null && report.minidump == null) {
                await _reports.updatePayload(currentRow.id, report.toJson());
              }
              return true;
          }
        });
        if (shouldStop) return sentCount;
        await _reports.writeFlushCursor(pendingKind, rowId);
      }
      return sentCount;
    } finally {
      _isFlushing = false;
      _flushInFlight = null;
      inFlight.complete();
    }
  }

  /// מפעיל שליחה מיידית ואחת לחמש דקות. קריאה חוזרת אינה יוצרת טיימר נוסף.
  Future<void> startAutomaticFlush() async {
    if (_flushTimer != null) return;
    unawaited(flushPendingReports());
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      unawaited(flushPendingReports());
    });
  }

  /// סקריפט שליחה של הדיווחים השמורים למחשב מחובר.
  OfflineSendScript buildOfflineSendScript(
    List<AppReport> reports, {
    required OfflineSendScriptTarget target,
  }) {
    return buildOfflineReportScript(
      target: target,
      endpoint: endpoint.toString(),
      // Preserve all v2 attachments; old reports retain their legacy export format.
      payloads: reports
          .map(
            (r) =>
                (r.schema >= 2 ? r : r.copyWith(minidump: null)).toApiPayload(),
          )
          .toList(),
      ids: reports.map((r) => r.reportId).toList(),
      idField: 'reportId',
      baseFileName: 'otzaria_send_app_reports',
    );
  }

  static AppReport _decode(PendingReport row) =>
      AppReport.fromJson(row.payload);

  static Map<String, dynamic> _contentOf(AppReport report) {
    final payload = report.toApiPayload()
      ..remove('reportId')
      ..remove('createdAt');
    return payload;
  }

  Future<List<int>> _rowIdsOf(String kind, String reportId) async {
    if (kind == pendingKind) await _ensureQueueFormat();
    return _reports.idsWhere(kind, 'reportId', reportId);
  }

  Future<void> _enqueueIfNeeded(AppReport report) async {
    final invalidField = report.validate();
    if (invalidField != null) {
      throw FormatException('Report is not ready for transport: $invalidField');
    }
    if ((await _rowIdsOf(sentKind, report.reportId)).isNotEmpty) return;
    if ((await _rowIdsOf(pendingKind, report.reportId)).isNotEmpty) return;
    await _reports.add(pendingKind, report.toJson());
  }

  Future<AppReport?> _sentReport(String reportId) async {
    final row = await _reports.findByPayloadId(
      sentKind,
      reportId,
      idField: 'reportId',
    );
    return row == null ? null : _decode(row);
  }

  static Future<T> _withReportLock<T>(
    String reportId,
    Future<T> Function() action,
  ) async {
    final previous = _reportOperationTails[reportId];
    final release = Completer<void>();
    final tail = release.future;
    _reportOperationTails[reportId] = tail;
    await previous;
    try {
      return await action();
    } finally {
      if (identical(_reportOperationTails[reportId], tail)) {
        _reportOperationTails.remove(reportId);
      }
      release.complete();
    }
  }

  AppReport _sentRecord(AppReport report, _Attempt attempt) {
    return report.withoutAttachments().copyWith(
      issueNumber: attempt.issueNumber,
      issueUrl: attempt.issueUrl,
      merged: attempt.merged,
      duplicate: attempt.duplicate,
      issuePending: attempt.issuePending,
      sentAt: _clock(),
    );
  }

  Future<void> _saveSentReport(AppReport report) async {
    final previousCount = await _reports.countByKind(sentKind);
    final existing = await _rowIdsOf(sentKind, report.reportId);
    await _reports.deleteIds(existing);
    await _reports.add(sentKind, report.toJson());
    await _reports.trimKind(sentKind, maxSentReportsToKeep);
    if (existing.isEmpty) {
      await _sentCounter.increment(floor: previousCount);
    }
  }

  /// תאימות לדיווחי schema 1 ישנים בלבד. schema 2 נשמר בשלמותו גם בדחייה.
  Future<(AppReport, _Attempt)> _trySendDroppingRejectedMinidump(
    AppReport report,
  ) async {
    final attempt = await _trySend(report);
    final dumpRejected =
        attempt.kind == _AttemptKind.permanent &&
        (attempt.rejectedField == 'attachments.minidump' ||
            attempt.httpStatus == HttpStatus.requestEntityTooLarge);
    if (report.schema >= 2 || report.minidump == null || !dumpRejected) {
      return (report, attempt);
    }
    final withoutDump = report.copyWith(minidump: null);
    return (withoutDump, await _trySend(withoutDump));
  }

  Future<_Attempt> _trySend(AppReport report) async {
    final invalidField = report.validate();
    if (invalidField != null) {
      return _Attempt(_AttemptKind.permanent, rejectedField: invalidField);
    }
    final Uint8List body;
    try {
      body = await _encodeBody(report);
    } catch (e) {
      debugPrint('App report payload invalid: $e');
      return const _Attempt(_AttemptKind.permanent);
    }
    if (body.length > AppReport.maxRequestBytes) {
      return const _Attempt(
        _AttemptKind.permanent,
        httpStatus: HttpStatus.requestEntityTooLarge,
      );
    }

    try {
      // לא דרך post(): הוא עוטף רשימה ב-cast ומעתיק את הגוף בית-בית.
      final request = http.Request('POST', endpoint)
        ..headers.addAll(const {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
        })
        ..bodyBytes = body;
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            report.images.isEmpty &&
                    report.minidump == null &&
                    report.otherAttachmentBytes <= AppReport.maxBodyBytes
                ? timeout
                : timeoutWithImages,
          );
      final status = response.statusCode;
      final reply = ReportServerResponse(
        status,
        ReportServerResponse.decodeBody(response.bodyBytes),
      );
      final decoded = reply.body;

      switch (reply.kind) {
        case ReportResponseKind.accepted:
          final issueNumber = decoded?['issueNumber'];
          final issueUrl = decoded?['issueUrl'];
          return _Attempt(
            _AttemptKind.success,
            httpStatus: status,
            issueNumber: issueNumber is int ? issueNumber : null,
            issueUrl: issueUrl is String ? issueUrl : null,
            merged: decoded?['merged'] == true,
            duplicate: reply.duplicate,
            issuePending: decoded?['issuePending'] == true,
          );
        case ReportResponseKind.idConflict:
          return _Attempt(_AttemptKind.idConflict, httpStatus: status);
        case ReportResponseKind.rejected:
          return _Attempt(
            _AttemptKind.permanent,
            httpStatus: status,
            rejectedField: reply.rejectedField,
          );
        case ReportResponseKind.closedForShabbat:
        case ReportResponseKind.transient:
          break;
      }
      return _Attempt(_AttemptKind.transient, httpStatus: status);
    } on TimeoutException {
      return const _Attempt(_AttemptKind.transient);
    } catch (e) {
      // SocketException / ClientException ודומיהם — כשל רשת זמני.
      debugPrint('App report send error: $e');
      return const _Attempt(_AttemptKind.transient);
    }
  }

  // צילומי מסך מקפיאים את החלון בקידוד; סטטית כדי שהסגירה לא תלכוד את `this`.
  static Future<Uint8List> _encodeBody(AppReport report) =>
      Isolate.run(() => utf8.encode(jsonEncode(report.toApiPayload())));
}

enum _AttemptKind { success, transient, permanent, idConflict }

class _Attempt {
  const _Attempt(
    this.kind, {
    this.httpStatus,
    this.rejectedField,
    this.issueNumber,
    this.issueUrl,
    this.merged = false,
    this.duplicate = false,
    this.issuePending = false,
  });

  final _AttemptKind kind;
  final int? httpStatus;
  final String? rejectedField;
  final int? issueNumber;
  final String? issueUrl;
  final bool merged;
  final bool duplicate;
  final bool issuePending;
}
