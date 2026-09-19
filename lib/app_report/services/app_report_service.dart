import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

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
  bool get isFailed => status == AppReportDeliveryStatus.failed;

  int? get issueNumber => report.issueNumber;
  String? get issueUrl => report.issueUrl;

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
  static const String pendingReportsKey = 'pending_reports';
  static const String sentReportsKey = 'sent_reports';
  static const String pendingKind = '$queueBoxName/$pendingReportsKey';
  static const String sentKind = '$queueBoxName/$sentReportsKey';
  static const int maxSentReportsToKeep = 100;
  static const Duration timeout = Duration(seconds: 10);

  /// צילומי מסך הם עד מגה-בתים רבים; בחיבור איטי 10 שניות לא מספיקות להעלאה.
  static const Duration timeoutWithImages = Duration(minutes: 2);
  static const Duration _flushInterval = Duration(minutes: 5);
  static const int _maxQueuedFlushPerRun = 20;

  static Timer? _flushTimer;
  static bool _isFlushing = false;
  static Completer<void>? _flushInFlight;

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
  Future<AppReportDeliveryResult> send(AppReport report) async {
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

    var current = report;
    var attempt = await _trySend(current);
    // 409: התוכן הזה לא נקלט תחת המזהה — הגשה חדשה במזהה חדש.
    if (attempt.kind == _AttemptKind.idConflict) {
      current = current.copyWith(reportId: AppReport.generateReportId());
      attempt = await _trySend(current);
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

  /// שולח דיווח מהתור. הרשומה מוסרת לפני השליחה, וכשל זמני מחזיר אותה.
  Future<AppReportDeliveryResult> submitPendingReport(AppReport report) async {
    await deletePendingReport(report.reportId);
    return send(report);
  }

  /// שומר דיווח בתור בלי לנסות לשלוח.
  Future<void> queueReport(AppReport report) => _enqueueIfNeeded(report);

  Future<int> getPendingReportsCount() => _reports.countByKind(pendingKind);

  Future<List<AppReport>> getPendingReports() async =>
      (await _reports.listByKind(pendingKind)).map(_decode).toList();

  /// היסטוריית הנשלחים, מהחדש לישן.
  Future<List<AppReport>> getSentReports() async =>
      (await _reports.listByKind(sentKind)).reversed.map(_decode).toList();

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() async {
    final total = await _sentCounter.read();
    final kept = await _reports.countByKind(sentKind);
    return total > kept ? total : kept;
  }

  Future<void> deletePendingReport(String reportId) async =>
      _reports.deleteIds(await _rowIdsOf(pendingKind, reportId));

  Future<void> deleteSentReport(String reportId) async =>
      _reports.deleteIds(await _rowIdsOf(sentKind, reportId));

  Future<void> clearPendingReports() => _reports.deleteAllOfKind(pendingKind);

  Future<void> clearSentReports() async {
    await _reports.deleteAllOfKind(sentKind);
    await _sentCounter.reset();
  }

  /// מעדכן דיווח בתור לפי [AppReport.reportId]. תוכן ששונה מקבל מזהה חדש,
  /// כי ייתכן שהגרסה הקודמת כבר נקלטה והשרת היה דוחה אותה ב-409.
  Future<AppReport?> updatePendingReport(AppReport report) async {
    final row = (await _reports.listByKind(
      pendingKind,
    )).where((r) => r.payload['reportId'] == report.reportId).firstOrNull;
    if (row == null) return null;
    final previous = _decode(row);
    final changed =
        jsonEncode(_contentOf(previous)) != jsonEncode(_contentOf(report));
    final updated = changed
        ? report.copyWith(reportId: AppReport.generateReportId())
        : report;
    await _reports.updatePayload(row.id, updated.toJson());
    return updated;
  }

  /// שולח את התור; עוצר בכשל זמני ראשון ומסיר דיווחים שנדחו סופית.
  /// מחזיר את מספר הדיווחים שנשלחו.
  Future<int> flushPendingReports() async {
    if (_isOfflineMode || _isFlushing) return 0;

    _isFlushing = true;
    final inFlight = _flushInFlight = Completer<void>();
    try {
      final rows = await _reports.listByKind(pendingKind);
      var sentCount = 0;
      for (final row in rows.take(_maxQueuedFlushPerRun)) {
        final report = _decode(row);
        final attempt = await _trySend(report);
        switch (attempt.kind) {
          case _AttemptKind.success:
            await _reports.deleteIds([row.id]);
            await _saveSentReport(_sentRecord(report, attempt));
            sentCount++;
          case _AttemptKind.idConflict:
            await _reports.updatePayload(
              row.id,
              report.copyWith(reportId: AppReport.generateReportId()).toJson(),
            );
          case _AttemptKind.permanent:
            debugPrint('App report rejected, removed: ${report.reportId}');
            await _reports.deleteIds([row.id]);
          case _AttemptKind.transient:
            return sentCount;
        }
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
      payloads: reports.map((r) => r.toApiPayload()).toList(),
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
    final rows = await _reports.listByKind(kind);
    return rows
        .where((row) => row.payload['reportId'] == reportId)
        .map((row) => row.id)
        .toList();
  }

  Future<void> _enqueueIfNeeded(AppReport report) async {
    if ((await _rowIdsOf(pendingKind, report.reportId)).isNotEmpty) return;
    await _reports.add(pendingKind, report.toJson());
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
    final sentRows = await _reports.listByKind(sentKind);
    final existing = sentRows
        .where((row) => row.payload['reportId'] == report.reportId)
        .map((row) => row.id)
        .toList();
    await _reports.deleteIds(existing);
    await _reports.add(sentKind, report.toJson());
    await _reports.trimKind(sentKind, maxSentReportsToKeep);
    if (existing.isEmpty) {
      await _sentCounter.increment(floor: sentRows.length);
    }
  }

  Future<_Attempt> _trySend(AppReport report) async {
    final String body;
    try {
      body = jsonEncode(report.toApiPayload());
    } catch (e) {
      debugPrint('App report payload invalid: $e');
      return const _Attempt(_AttemptKind.permanent);
    }
    if (utf8.encode(body).length > AppReport.maxRequestBytes) {
      return const _Attempt(
        _AttemptKind.permanent,
        httpStatus: HttpStatus.requestEntityTooLarge,
      );
    }

    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: utf8.encode(body),
          )
          .timeout(report.images.isEmpty ? timeout : timeoutWithImages);
      final status = response.statusCode;
      final decoded = _decodeBody(response.bodyBytes);

      if (status >= 200 && status < 300) {
        final issueNumber = decoded?['issueNumber'];
        final issueUrl = decoded?['issueUrl'];
        return _Attempt(
          _AttemptKind.success,
          httpStatus: status,
          issueNumber: issueNumber is int ? issueNumber : null,
          issueUrl: issueUrl is String ? issueUrl : null,
          merged: decoded?['merged'] == true,
          duplicate: decoded?['duplicate'] == true,
          issuePending: decoded?['issuePending'] == true,
        );
      }
      if (status == HttpStatus.conflict) {
        return _Attempt(_AttemptKind.idConflict, httpStatus: status);
      }
      if (status == HttpStatus.badRequest ||
          status == HttpStatus.requestEntityTooLarge ||
          status == 422) {
        final field = decoded?['field'];
        return _Attempt(
          _AttemptKind.permanent,
          httpStatus: status,
          rejectedField: field is String ? field : null,
        );
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

  static Map<String, dynamic>? _decodeBody(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
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
