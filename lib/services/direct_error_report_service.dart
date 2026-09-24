import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

export 'package:otzaria/services/offline_report_script_builder.dart'
    show OfflineSendScript, OfflineSendScriptTarget;

enum DirectReportDeliveryStatus {
  sent,
  queued,
  failed,
}

class DirectReportDeliveryResult {
  final DirectReportDeliveryStatus status;
  final String message;

  /// השרת קלט את הדיווח אך לא שלח מייל, כי תוכן זהה כבר נשלח בעבר.
  final bool isDuplicate;

  /// אתר ישן קלט הצעת תיקון כטקסט חופשי בלבד (חסר `correction_supported`).
  final bool correctionNotSupported;

  /// 409: השרת מחזיק תוכן אחר תחת אותו `report_id`.
  final bool isIdConflict;

  const DirectReportDeliveryResult._({
    required this.status,
    required this.message,
    this.isDuplicate = false,
    this.correctionNotSupported = false,
    this.isIdConflict = false,
  });

  factory DirectReportDeliveryResult.sent(
    String message, {
    bool isDuplicate = false,
    bool correctionNotSupported = false,
  }) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.sent,
      message: message,
      isDuplicate: isDuplicate,
      correctionNotSupported: correctionNotSupported,
    );
  }

  factory DirectReportDeliveryResult.queued(String message) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.queued,
      message: message,
    );
  }

  factory DirectReportDeliveryResult.failed(
    String message, {
    bool isIdConflict = false,
  }) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.failed,
      message: message,
      isIdConflict: isIdConflict,
    );
  }

  bool get isSent => status == DirectReportDeliveryStatus.sent;

  bool get isQueued => status == DirectReportDeliveryStatus.queued;
}

/// תוצאת [DirectErrorReportService.handOffPendingReports].
class ReportHandoffResult {
  /// נכתבו והועברו להיסטוריה.
  final int handedOff;

  /// נכתבו, אבל אוצריא הפתוחה ערכה או שלחה אותם בינתיים — ולא הועברו.
  final int changedMeanwhile;

  /// דיווחים פסולים שדולגו ונשארו בתור, כמו בייצוא סקריפט השליחה.
  final List<String> invalidIds;

  /// כשלי כתיבה לפי מזהה דיווח; הדיווחים נשארו בתור.
  final Map<String, Object> failures;

  const ReportHandoffResult({
    required this.handedOff,
    required this.changedMeanwhile,
    required this.invalidIds,
    required this.failures,
  });
}

class DirectErrorReportService {
  static const String _endpoint = 'https://otzaria.org/api/reportingerrors';
  static const String queueBoxName = 'error_reports_queue';
  static const String pendingReportsKey = 'pending_reports';
  static const String sentReportsKey = 'sent_reports';
  static const int maxSentReportsToKeep = 100;
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _flushInterval = Duration(minutes: 5);
  static const int _maxQueuedFlushPerRun = 20;
  static const String _otzariaDirectReportTarget = 'אוצריא';
  static const String _sefariaDirectReportTarget = 'ספריא';

  static Timer? _flushTimer;
  static bool _isFlushing = false;
  static Completer<void>? _flushInFlight;

  /// עוצר את השליחה האוטומטית וממתין לשליחה שבאמצע, כדי שכתיבה חיצונית לתור
  /// (שחזור מגיבוי) לא תדרוס אותה. `startAutomaticFlush` מפעיל מחדש בעלייה.
  static Future<void> suspendAutomaticFlush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flushInFlight?.future;
  }

  /// סוגי התור במסד המשותף — זהים למפתחות שהמיגרציה מ-Hive יצרה.
  static const String pendingKind = '$queueBoxName/$pendingReportsKey';
  static const String sentKind = '$queueBoxName/$sentReportsKey';

  final http.Client _client;
  final PendingReportStore _reports;
  final SentReportsCounter _sentCounter;

  DirectErrorReportService({
    http.Client? client,
    PendingReportStore? reportStore,
    SentReportsCounter? sentCounter,
  }) : _client = client ?? http.Client(),
       _reports = reportStore ?? PendingReportStore.instance,
       _sentCounter =
           sentCounter ??
           SentReportsCounter(
             boxName: queueBoxName,
             database: reportStore?.database,
           );

  /// לקריאה לפני onWindowClose במופע הארוך-טווח (של `startAutomaticFlush`):
  /// ב-Windows admin install ניקוי socket handles ביציאה תוקע לכמה שניות.
  Future<void> closeHttpClient() async {
    _client.close();
  }

  String get senderEmail =>
      (Settings.getValue<String>(
                SettingsRepository.keyErrorReportSenderEmail,
              ) ??
              '')
          .trim();

  bool get queueWhenOfflineEnabled =>
      Settings.getValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
      ) ??
      true;

  bool get _isOfflineMode =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  Future<void> saveSenderEmail(String email) async {
    await Settings.setValue(
      SettingsRepository.keyErrorReportSenderEmail,
      email.trim(),
    );
  }

  Future<void> clearSenderEmail() async {
    await Settings.setValue(SettingsRepository.keyErrorReportSenderEmail, '');
  }

  Future<void> setQueueWhenOfflineEnabled(bool value) async {
    await Settings.setValue(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      value,
    );
  }

  Future<int> getPendingReportsCount() => _reports.countByKind(pendingKind);

  Future<List<DirectErrorReport>> getPendingReports() async {
    return (await _reports.listByKind(pendingKind)).map(_decode).toList();
  }

  /// היסטוריית הנשלחים מוצגת מהחדש לישן, ולכן הפוכה לסדר ההוספה.
  Future<List<DirectErrorReport>> getSentReports() async {
    return (await _reports.listByKind(sentKind)).reversed.map(_decode).toList();
  }

  Future<void> deleteSentReport(String reportId) async {
    await _reports.deleteIds(await _rowIdsOf(sentKind, reportId));
  }

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() async {
    final total = await _sentCounter.read();
    final kept = _sentReportsCount(await _reports.listByKind(sentKind));
    return total > kept ? total : kept;
  }

  Future<void> clearSentReports() async {
    await _reports.deleteAllOfKind(sentKind);
    await _sentCounter.reset();
  }

  /// מעדכן דיווח בתור. תוכן ששונה מקבל `report_id` חדש: ייתכן שהגרסה הקודמת
  /// כבר נקלטה בשרת, ואותו מזהה עם תוכן אחר נדחה שם ב-409.
  Future<void> updatePendingReport(DirectErrorReport report) async {
    final row = await _rowOf(pendingKind, report.id);
    if (row == null) {
      return;
    }

    final previousDigest = _digestOrNull(_decode(row));
    final contentChanged =
        previousDigest == null || previousDigest != _digestOrNull(report);
    final updated = contentChanged
        ? report.withId(DirectErrorReport.generateId(report.id))
        : report;
    await _reports.updatePayload(row.id, updated.toJson());
  }

  /// 409 = התוכן הזה לא נקלט; שליחתו מחדש היא הגשה חדשה, ולכן במזהה חדש (§2.3).
  /// ידני — כדי שלא יישלח שוב אוטומטית (409 הוא כשל קבוע, §2.4).
  static DirectErrorReport _withNewIdAfterConflict(DirectErrorReport report) =>
      report
          .withId(DirectErrorReport.generateId(report.id))
          .copyWith(queueType: DirectErrorReportQueueType.manual);

  /// null לדיווח שאינו ניתן לסריאליזציה קנונית (surrogate בודד).
  static String? _digestOrNull(DirectErrorReport report) {
    try {
      return report.contentDigest;
    } on ArgumentError {
      return null;
    }
  }

  Future<void> deletePendingReport(String reportId) async {
    await _reports.deleteIds(await _rowIdsOf(pendingKind, reportId));
  }

  static DirectErrorReport _decode(PendingReport row) =>
      DirectErrorReport.fromJson(row.payload);

  Future<List<int>> _rowIdsOf(String kind, String reportId) async {
    final rows = await _reports.listByKind(kind);
    return rows
        .where((row) => row.payload['id'] == reportId)
        .map((row) => row.id)
        .toList();
  }

  Future<PendingReport?> _rowOf(String kind, String reportId) async {
    final rows = await _reports.listByKind(kind);
    return rows.where((row) => row.payload['id'] == reportId).firstOrNull;
  }

  /// מסמן דיווח מהתור כנשלח ידנית: מעביר אותו להיסטוריית הנשלחים
  /// ומסיר אותו מהתור, מבלי לפנות לשרת.
  Future<void> markPendingReportAsSent(DirectErrorReport report) async {
    await _saveSentReport(report);
    await deletePendingReport(report.id);
  }

  Future<void> queueReport(
    DirectErrorReport report, {
    DirectErrorReportQueueType queueType = DirectErrorReportQueueType.manual,
  }) async {
    await _enqueueIfNeeded(report, queueType: queueType);
  }

  Future<void> clearPendingReports() async {
    await _reports.deleteAllOfKind(pendingKind);
  }

  Future<DirectReportDeliveryResult> submitPendingReport(
    DirectErrorReport report,
  ) async {
    final result = await submitReport(report);
    if (result.isSent) {
      await deletePendingReport(report.id);
    } else if (result.isIdConflict) {
      final row = await _rowOf(pendingKind, report.id);
      if (row != null) {
        await _reports.updatePayload(
          row.id,
          _withNewIdAfterConflict(_decode(row)).toJson(),
        );
      }
      return DirectReportDeliveryResult.failed(
        ReportMessages.pendingReportIdConflict,
        isIdConflict: true,
      );
    }
    return result;
  }

  /// סקריפט שליחה קריא (ללא Base64) של הדיווחים השמורים למחשב המחובר; התוצאה
  /// מוצגת בחלון מערכת כדי להימנע מג'יבריש עברית בקונסול.
  OfflineSendScript buildOfflineSendScript(
    List<DirectErrorReport> reports, {
    required OfflineSendScriptTarget target,
  }) {
    // דיווח פסול היה נדחה בשרת ממילא; הוא נשאר בתור לעריכה ולא מפיל את הייצוא.
    final sendable = reports.where(isSendable).toList();
    return buildOfflineReportScript(
      target: target,
      endpoint: _endpoint,
      payloads: sendable.map((report) => report.toApiPayload()).toList(),
      ids: sendable.map((report) => report.id).toList(),
      idField: 'report_id',
      baseFileName: 'otzaria_send_saved_reports',
    );
  }

  static const String pendingFormat = 'otzaria-reports-pending';
  static const int pendingFormatVersion = 1;
  static const String handoffFormat = 'otzaria-report';
  static const int handoffFormatVersion = 1;

  /// דיווח פסול (surrogate בודד) היה נדחה בשרת ממילא, ולכן אינו נשלח.
  static bool isSendable(DirectErrorReport report) =>
      _digestOrNull(report) != null;

  /// מספר הדיווחים בתור שאפשר להעביר למחשב מחובר.
  Future<int> getSendablePendingReportsCount() async =>
      (await getPendingReports()).where(isSendable).length;

  static Map<String, dynamic> pendingDocument(int count) => {
    'format': pendingFormat,
    'version': pendingFormatVersion,
    'pending': count,
  };

  /// מסמך העברה של דיווח למחשב מחובר, ששולח את `body` כמות שהוא ל-`endpoint`.
  static Map<String, dynamic> handoffDocument(DirectErrorReport report) => {
    'format': handoffFormat,
    'version': handoffFormatVersion,
    'report_id': report.id,
    'endpoint': _endpoint,
    'book_title': report.bookTitle,
    'created_at': report.createdAt.toIso8601String(),
    'body': report.toApiPayload(),
  };

  /// מוסר כל דיווח שבתור ל-[write], ורק אחרי שנכתב מעביר אותו להיסטוריה —
  /// כמו [markPendingReportAsSent]. דיווח שנכשל נשאר בתור.
  Future<ReportHandoffResult> handOffPendingReports(
    Future<void> Function(DirectErrorReport report) write,
  ) async {
    var handedOff = 0;
    var changedMeanwhile = 0;
    final invalidIds = <String>[];
    final failures = <String, Object>{};
    for (final row in await _reports.listByKind(pendingKind)) {
      final report = _decode(row);
      if (!isSendable(report)) {
        invalidIds.add(report.id);
        continue;
      }
      try {
        await write(report);
      } catch (error) {
        failures[report.id] = error;
        continue;
      }
      final kept = _sentReportsCount(await _reports.listByKind(sentKind));
      final move = await _reports.moveIfUnchanged(row, sentKind);
      if (!move.moved) {
        changedMeanwhile++;
        continue;
      }
      handedOff++;
      await _reports.trimKind(sentKind, maxSentReportsToKeep);
      if (!move.replaced) await _sentCounter.increment(floor: kept);
    }
    return ReportHandoffResult(
      handedOff: handedOff,
      changedMeanwhile: changedMeanwhile,
      invalidIds: List.unmodifiable(invalidIds),
      failures: Map.unmodifiable(failures),
    );
  }

  Future<DirectReportDeliveryResult> submitReport(
    DirectErrorReport report,
  ) async {
    final directReportTargetLabel = _resolveDirectReportTargetLabel(report);

    if (_isOfflineMode) {
      if (!queueWhenOfflineEnabled) {
        return DirectReportDeliveryResult.failed(
          ReportMessages.offlineQueueDisabled,
        );
      }

      await _enqueueIfNeeded(
        report,
        queueType: DirectErrorReportQueueType.automaticRetry,
      );
      return DirectReportDeliveryResult.queued(
        ReportMessages.queuedOffline(directReportTargetLabel),
      );
    }

    final attemptResult = await _trySend(report);
    if (attemptResult.isSuccess) {
      final sentRecord = _sentRecord(report, attemptResult);
      await _saveSentReport(sentRecord);
      unawaited(flushPendingReports(onlyAutomaticRetry: true));
      if (sentRecord.serverAcceptedCorrection == false) {
        return DirectReportDeliveryResult.sent(
          ReportMessages.correctionNotSupportedByServer(
            directReportTargetLabel,
          ),
          isDuplicate: attemptResult.isDuplicate,
          correctionNotSupported: true,
        );
      }
      if (attemptResult.isDuplicate) {
        return DirectReportDeliveryResult.sent(
          ReportMessages.duplicateReport(directReportTargetLabel),
          isDuplicate: true,
        );
      }
      if (_isSefariaReport(report)) {
        return DirectReportDeliveryResult.sent(ReportMessages.sentToSefaria);
      }

      return DirectReportDeliveryResult.sent(ReportMessages.sentToOtzaria);
    }

    if (attemptResult.isPermanentFailure) {
      return DirectReportDeliveryResult.failed(
        attemptResult.message,
        isIdConflict: attemptResult.isIdConflict,
      );
    }

    await _enqueueIfNeeded(
      report,
      queueType: DirectErrorReportQueueType.automaticRetry,
    );
    return DirectReportDeliveryResult.queued(
      ReportMessages.queuedAfterFailure(directReportTargetLabel),
    );
  }

  bool _isSefariaReport(DirectErrorReport report) {
    // הכלה ולא התאמה מדויקת: זהה לניתוב המייל בשרת (getEmailRecipients).
    return report.sourceFolder.trim().toLowerCase().contains('sefaria');
  }

  String _resolveDirectReportTargetLabel(DirectErrorReport report) {
    return _isSefariaReport(report)
        ? _sefariaDirectReportTarget
        : _otzariaDirectReportTarget;
  }

  Future<int> flushPendingReports({
    bool onlyAutomaticRetry = false,
  }) async {
    if (_isOfflineMode || _isFlushing) {
      return 0;
    }

    _isFlushing = true;
    final inFlight = _flushInFlight = Completer<void>();
    try {
      final rows = await _reports.listByKind(pendingKind);
      if (rows.isEmpty) {
        return 0;
      }

      final rowsToAttempt = onlyAutomaticRetry
          ? rows
                .where(
                  (row) =>
                      _decode(row).queueType ==
                      DirectErrorReportQueueType.automaticRetry,
                )
                .take(_maxQueuedFlushPerRun)
                .toList()
          : rows.take(_maxQueuedFlushPerRun).toList();

      var sentCount = 0;

      for (final row in rowsToAttempt) {
        final report = _decode(row);
        final attemptResult = await _trySend(report);

        if (attemptResult.isSuccess) {
          await _reports.deleteIds([row.id]);
          await _saveSentReport(_sentRecord(report, attemptResult));
          sentCount++;
          continue;
        }

        if (attemptResult.isIdConflict) {
          await _reports.updatePayload(
            row.id,
            _withNewIdAfterConflict(report).toJson(),
          );
          continue;
        }

        if (attemptResult.isPermanentFailure) {
          // לא חוזר לתור (§2.4), אבל נשמר בהיסטוריה כנדחה — אחרת ההצעה אובדת בשקט.
          await _reports.deleteIds([row.id]);
          await _saveSentReport(
            report.copyWith(rejectionReason: attemptResult.message),
            countAsSent: false,
          );
          continue;
        }

        break;
      }

      return sentCount;
    } finally {
      _isFlushing = false;
      _flushInFlight = null;
      inFlight.complete();
    }
  }

  Future<void> startAutomaticFlush() async {
    if (_flushTimer != null) {
      return;
    }

    unawaited(flushPendingReports(onlyAutomaticRetry: true));
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      unawaited(flushPendingReports(onlyAutomaticRetry: true));
    });
  }

  static bool isValidSenderEmail(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      return false;
    }

    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized);
  }

  Future<void> _enqueueIfNeeded(
    DirectErrorReport report, {
    required DirectErrorReportQueueType queueType,
  }) async {
    if ((await _rowIdsOf(pendingKind, report.id)).isNotEmpty) {
      return;
    }

    await _reports.add(
      pendingKind,
      report.copyWith(queueType: queueType).toJson(),
    );
  }

  Future<void> _saveSentReport(
    DirectErrorReport report, {
    bool countAsSent = true,
  }) async {
    final sentRows = await _reports.listByKind(sentKind);
    final kept = _sentReportsCount(sentRows);
    final existing = sentRows.where((row) => row.payload['id'] == report.id);
    await _reports.deleteIds(existing.map((row) => row.id));
    await _reports.add(sentKind, report.toJson());
    await _reports.trimKind(sentKind, maxSentReportsToKeep);
    if (countAsSent && existing.isEmpty) {
      await _sentCounter.increment(floor: kept);
    }
  }

  static int _sentReportsCount(List<PendingReport> rows) =>
      rows.where((row) => row.payload['rejectionReason'] == null).length;

  /// הרשומה להיסטוריית הנשלחים: הצעת תיקון מסומנת אם השרת תמך בה.
  DirectErrorReport _sentRecord(
    DirectErrorReport report,
    _SendAttemptResult attemptResult,
  ) {
    if (!report.isTextCorrection) return report;
    return report.copyWith(
      serverAcceptedCorrection: attemptResult.correctionSupported,
    );
  }

  Future<_SendAttemptResult> _trySend(DirectErrorReport report) async {
    final String body;
    try {
      body = report.apiBody;
    } on ArgumentError catch (e) {
      // טקסט שאינו ניתן לסריאליזציה קנונית (surrogate בודד) — לא ישתפר בניסיון חוזר.
      debugPrint('Direct report payload invalid: $e');
      return _SendAttemptResult.permanentFailure(ReportMessages.sendFailed);
    }

    if (utf8.encode(body).length > DirectErrorReport.maxApiBodyBytes) {
      return _SendAttemptResult.permanentFailure(
        ReportMessages.bodyTooLarge(DirectErrorReport.maxApiBodyBytes ~/ 1024),
      );
    }

    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == HttpStatus.ok) {
        final decoded = _decodeResponse(response.body);
        return _SendAttemptResult.success(
          isDuplicate: decoded?['duplicate'] == true,
          correctionSupported: decoded?['correction_supported'] == true,
        );
      }

      if (response.statusCode == HttpStatus.conflict) {
        return _SendAttemptResult.permanentFailure(
          ReportMessages.reportIdConflict,
          isIdConflict: true,
        );
      }

      if (_isPermanentHttpFailure(response.statusCode)) {
        return _SendAttemptResult.permanentFailure(
          ReportMessages.serverPermanentFailure(response.statusCode),
        );
      }

      return _SendAttemptResult.transientFailure(
        ReportMessages.serverTransientFailure(response.statusCode),
      );
    } on SocketException catch (e) {
      debugPrint('Direct report network error: $e');
      return _SendAttemptResult.transientFailure(ReportMessages.noInternet);
    } on http.ClientException catch (e) {
      debugPrint('Direct report client error: $e');
      return _SendAttemptResult.transientFailure(ReportMessages.sendFailed);
    } on TimeoutException {
      return _SendAttemptResult.transientFailure(ReportMessages.serverTimeout);
    } catch (e) {
      debugPrint('Direct report unexpected error: $e');
      return _SendAttemptResult.transientFailure(
        ReportMessages.unexpectedSendError,
      );
    }
  }

  /// חוזה §2.4: 400/409/413/422 קבועים; 408/429/5xx וכל השאר זמניים (תור).
  bool _isPermanentHttpFailure(int statusCode) {
    return statusCode == HttpStatus.badRequest ||
        statusCode == HttpStatus.conflict ||
        statusCode == HttpStatus.requestEntityTooLarge ||
        statusCode == 422;
  }

  /// גוף תשובת 200. `duplicate:true` = תוכן זהה כבר נשלח במייל (הדיווח נקלט);
  /// היעדר `correction_supported:true` = אתר ישן שאינו מכיר הצעת תיקון.
  static Map<String, dynamic>? _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

class _SendAttemptResult {
  final bool isSuccess;
  final String message;
  final _SendAttemptFailureType? failureType;
  final bool isDuplicate;
  final bool correctionSupported;
  final bool isIdConflict;

  const _SendAttemptResult._({
    required this.isSuccess,
    required this.message,
    this.failureType,
    this.isDuplicate = false,
    this.correctionSupported = false,
    this.isIdConflict = false,
  });

  const _SendAttemptResult.success({
    bool isDuplicate = false,
    bool correctionSupported = false,
  }) : this._(
         isSuccess: true,
         message: '',
         failureType: null,
         isDuplicate: isDuplicate,
         correctionSupported: correctionSupported,
       );

  bool get isPermanentFailure =>
      !isSuccess && failureType == _SendAttemptFailureType.permanent;

  factory _SendAttemptResult.transientFailure(String message) {
    return _SendAttemptResult._(
      isSuccess: false,
      message: message,
      failureType: _SendAttemptFailureType.transient,
    );
  }

  factory _SendAttemptResult.permanentFailure(
    String message, {
    bool isIdConflict = false,
  }) {
    return _SendAttemptResult._(
      isSuccess: false,
      message: message,
      failureType: _SendAttemptFailureType.permanent,
      isIdConflict: isIdConflict,
    );
  }
}

enum _SendAttemptFailureType {
  transient,
  permanent,
}
