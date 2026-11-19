import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/reports/report_queue_flush.dart';
import 'package:otzaria/reports/repository/sent_report_history.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// תוצאת מסירה של דיווח תוסף: נשלח עכשיו או נשמר בתור לשליחה מאוחרת.
enum PluginReportDeliveryStatus { sent, queued }

/// שליחת דיווח משתמש על תוסף לאתר אוצריא, שמאתר את מפתח התוסף ומעביר לו.
///
/// באותו דפוס של דיווחי הטעויות בספרים: כשל זמני או מצב לא-מקוון שומרים
/// את הדיווח בתור המשותף לכל החלונות עם ניסיון חוזר אוטומטי; דחייה קבועה של
/// השרת (400/422) נזרקת לתוסף ואינה נכנסת לתור.
class PluginReportService {
  PluginReportService({
    http.Client? client,
    PendingReportStore? reportStore,
    SentReportsCounter? sentCounter,
  }) : _client = client ?? _shared,
       _reports = reportStore ?? PendingReportStore.instance,
       _sentHistory = SentReportHistory(
         store: reportStore,
         counter: sentCounter,
         boxName: queueBoxName,
         kind: sentKind,
         idField: 'reportId',
         limit: maxSentReportsToKeep,
         fromJson: PluginReportRecord.fromJson,
       );

  static final Uri endpoint = Uri.parse(
    'https://otzaria.org/api/plugin-reports',
  );

  static const String queueBoxName = 'plugin_reports_queue';
  static const String pendingReportsKey = 'pending_reports';
  static const String sentReportsKey = 'sent_reports';
  static const int maxSentReportsToKeep = 100;
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxQueuedFlushPerRun = 20;

  /// סוגי הדיווח המוכרים לשרת; ערך לא מוכר מתורגם ל-'other'.
  static const Set<String> reportTypes = {'bug', 'crash', 'content', 'other'};

  /// אורך מרבי לשדה הפירוט; טקסט ארוך יותר נחתך לפני השליחה.
  static const int maxDetailsLength = 5000;

  static final _flush = ReportQueueFlush();

  /// עוצר את השליחה האוטומטית וממתין לשליחה שבאמצע, כדי שכתיבה חיצונית לתור
  /// (שחזור מגיבוי) לא תדרוס אותה. `startAutomaticFlush` מפעיל מחדש בעלייה.
  static Future<void> suspendAutomaticFlush() => _flush.suspend();

  /// סוגי התור במסד המשותף — זהים למפתחות שהמיגרציה מ-Hive יצרה.
  static const String pendingKind = '$queueBoxName/$pendingReportsKey';
  static const String sentKind = '$queueBoxName/$sentReportsKey';

  final http.Client _client;
  final PendingReportStore _reports;
  final SentReportHistory<PluginReportRecord> _sentHistory;

  static final http.Client _shared = _createClient();

  static http.Client _createClient() {
    final client = http.Client();
    HttpClientRegistry.register(client.close);
    return client;
  }

  static String generateReportId() => generateReportUuid();

  static String normalizeReportType(String? raw) {
    final value = raw?.trim().toLowerCase() ?? '';
    return reportTypes.contains(value) ? value : 'other';
  }

  bool get _queueWhenOfflineEnabled =>
      Settings.getValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
      ) ??
      true;

  bool get _isOfflineMode =>
      Settings.getValue<bool>(SettingsRepository.keyOfflineMode) ?? false;

  /// בונה רשומת דיווח מוכנה לשליחה: נרמול סוג, חיתוך פירוט וזיהוי הגרסה.
  Future<PluginReportRecord> buildRecord({
    required String pluginUid,
    required String pluginName,
    required String pluginVersion,
    required String details,
    String? reportType,
    String? reporterEmail,
  }) async {
    final trimmedDetails = details.trim();
    if (trimmedDetails.isEmpty) {
      throw Exception('details required');
    }

    String? appVersion;
    try {
      appVersion = appReleaseVersion(await PackageInfo.fromPlatform());
    } catch (_) {}

    final email = reporterEmail?.trim() ?? '';
    return PluginReportRecord(
      reportId: generateReportId(),
      pluginUid: pluginUid,
      pluginName: pluginName,
      pluginVersion: pluginVersion,
      reportType: normalizeReportType(reportType),
      details: trimmedDetails.length > maxDetailsLength
          ? trimmedDetails.substring(0, maxDetailsLength)
          : trimmedDetails,
      reporterEmail: email.isEmpty ? null : email,
      appVersion: appVersion,
      platform: Platform.operatingSystem,
      createdAt: DateTime.now(),
    );
  }

  /// שולח דיווח או שומר אותו בתור. זורק על דחייה קבועה של השרת,
  /// ועל מצב לא-מקוון כשהתור האוטומטי כבוי בהגדרות.
  Future<PluginReportDeliveryStatus> submitReport(
    PluginReportRecord record,
  ) async {
    if (_isOfflineMode) {
      if (!_queueWhenOfflineEnabled) {
        throw Exception('offline and report queue is disabled');
      }
      await _enqueueIfNeeded(record);
      return PluginReportDeliveryStatus.queued;
    }

    final attemptResult = await _trySend(record);
    if (attemptResult.isSuccess) {
      await _saveSentReport(record);
      _flush.runInBackground(flushPendingReports);
      return PluginReportDeliveryStatus.sent;
    }

    if (attemptResult.isPermanentFailure) {
      throw Exception(attemptResult.message);
    }

    await _enqueueIfNeeded(record);
    return PluginReportDeliveryStatus.queued;
  }

  /// שולח דיווח שמור מהתור. הרשומה מוסרת מהתור לפני השליחה — אחרת
  /// ה-flush שההצלחה מפעילה עלול לטעון את התור לפניה ולשלוח אותה שוב.
  Future<PluginReportDeliveryStatus> submitPendingReport(
    PluginReportRecord record,
  ) async {
    if (_isOfflineMode && !_queueWhenOfflineEnabled) {
      throw Exception('offline and report queue is disabled');
    }
    await deletePendingReport(record.reportId);
    // כשל זמני מחזיר את הרשומה לתור בתוך submitReport.
    return submitReport(record);
  }

  Future<int> getPendingReportsCount() => _reports.countByKind(pendingKind);

  Future<List<PluginReportRecord>> getPendingReports() async {
    return (await _reports.listByKind(pendingKind)).map(_decode).toList();
  }

  /// היסטוריית הנשלחים מוצגת מהחדש לישן, ולכן הפוכה לסדר ההוספה.
  Future<List<PluginReportRecord>> getSentReports() => _sentHistory.list();

  /// כל הדיווחים שנשלחו אי-פעם — לא רק אלה שנשארו בהיסטוריה.
  Future<int> getSentReportsTotal() => _sentHistory.total();

  Future<void> deletePendingReport(String reportId) async {
    await _reports.deleteIds(await _rowIdsOf(pendingKind, reportId));
  }

  /// מעדכן סוג ופירוט של דיווח בתור. שינוי בתוכן מקבל `reportId` חדש: השרת
  /// מסנן מזהה שכבר נקלט, והגרסה המתוקנת הייתה נבלעת כשליחה כפולה.
  Future<void> updatePendingReport(
    String reportId, {
    required String reportType,
    required String details,
  }) async {
    final row = (await _reports.listByKind(
      pendingKind,
    )).where((row) => row.payload['reportId'] == reportId).firstOrNull;
    if (row == null) return;

    final current = _decode(row);
    final type = normalizeReportType(reportType);
    final trimmed = details.trim();
    final text = trimmed.length > maxDetailsLength
        ? trimmed.substring(0, maxDetailsLength)
        : trimmed;
    if (text.isEmpty) {
      throw Exception('details required');
    }
    if (type == current.reportType && text == current.details) return;

    final updated = current.copyWith(
      reportId: generateReportId(),
      reportType: type,
      details: text,
    );
    await _reports.updatePayload(row.id, updated.toJson());
  }

  Future<void> clearPendingReports() async {
    await _reports.deleteAllOfKind(pendingKind);
  }

  Future<void> deleteSentReport(String reportId) =>
      _sentHistory.delete(reportId);

  Future<void> clearSentReports() => _sentHistory.clear();

  static PluginReportRecord _decode(PendingReport row) =>
      PluginReportRecord.fromJson(row.payload);

  Future<List<int>> _rowIdsOf(String kind, String reportId) =>
      _reports.idsWhere(kind, 'reportId', reportId);

  /// מנסה לשלוח את הדיווחים השמורים; עוצר בכשל זמני ראשון, ומסיר מהתור
  /// דיווחים שנדחו סופית. מחזיר את מספר הדיווחים שנשלחו.
  Future<int> flushPendingReports() async {
    if (_isOfflineMode) return 0;

    return _flush.run(() async {
      final rowsToAttempt = await _reports.listByKind(
        pendingKind,
        limit: _maxQueuedFlushPerRun,
      );
      var sentCount = 0;

      for (final row in rowsToAttempt) {
        final record = _decode(row);
        final attemptResult = await _trySend(record);

        if (attemptResult.isSuccess) {
          await _reports.deleteIds([row.id]);
          await _saveSentReport(record);
          sentCount++;
          continue;
        }

        if (attemptResult.isPermanentFailure) {
          debugPrint(
            'Plugin report permanently failed and was removed from queue: '
            '${record.reportId}',
          );
          await _reports.deleteIds([row.id]);
          continue;
        }

        break;
      }

      return sentCount;
    });
  }

  Future<void> startAutomaticFlush() async {
    _flush.start(flushPendingReports);
  }

  /// בונה סקריפט שליחה של הדיווחים השמורים למחשב מחובר, לפי מערכת ההפעלה.
  OfflineSendScript buildOfflineSendScript(
    List<PluginReportRecord> records, {
    required OfflineSendScriptTarget target,
  }) {
    return buildOfflineReportScript(
      target: target,
      endpoint: endpoint.toString(),
      payloads: records.map((record) => record.toApiPayload()).toList(),
      ids: records.map((record) => record.reportId).toList(),
      idField: 'reportId',
      baseFileName: 'otzaria_send_plugin_reports',
    );
  }

  Future<void> _enqueueIfNeeded(PluginReportRecord record) async {
    if ((await _rowIdsOf(pendingKind, record.reportId)).isNotEmpty) {
      return;
    }

    await _reports.add(pendingKind, record.toJson());
  }

  Future<void> _saveSentReport(PluginReportRecord record) =>
      _sentHistory.save(record.reportId, record.toJson());

  Future<_SendAttemptResult> _trySend(PluginReportRecord record) async {
    try {
      final response = await _client
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(record.toApiPayload()),
          )
          .timeout(_timeout);

      switch (ReportServerResponse(response.statusCode, null).kind) {
        case ReportResponseKind.accepted:
          return const _SendAttemptResult.success();
        // תור התוספים מנסה שוב גם על 409 ו-413.
        case ReportResponseKind.rejected
            when response.statusCode != HttpStatus.requestEntityTooLarge:
          return _SendAttemptResult.permanentFailure(
            'report rejected: HTTP ${response.statusCode}',
          );
        default:
          break;
      }

      return _SendAttemptResult.transientFailure(
        'server error: HTTP ${response.statusCode}',
      );
    } on SocketException catch (e) {
      debugPrint('Plugin report network error: $e');
      return const _SendAttemptResult.transientFailure('no internet');
    } on http.ClientException catch (e) {
      debugPrint('Plugin report client error: $e');
      return const _SendAttemptResult.transientFailure('send failed');
    } on TimeoutException {
      return const _SendAttemptResult.transientFailure('server timeout');
    } catch (e) {
      debugPrint('Plugin report unexpected error: $e');
      return const _SendAttemptResult.transientFailure(
        'unexpected send error',
      );
    }
  }
}

class _SendAttemptResult {
  final bool isSuccess;
  final String message;
  final bool isPermanentFailure;

  const _SendAttemptResult._({
    required this.isSuccess,
    required this.message,
    required this.isPermanentFailure,
  });

  const _SendAttemptResult.success()
    : this._(isSuccess: true, message: '', isPermanentFailure: false);

  const _SendAttemptResult.transientFailure(String message)
    : this._(isSuccess: false, message: message, isPermanentFailure: false);

  const _SendAttemptResult.permanentFailure(String message)
    : this._(isSuccess: false, message: message, isPermanentFailure: true);
}
