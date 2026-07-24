import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/data/repository/hive_list_repository.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

enum DirectReportDeliveryStatus {
  sent,
  queued,
  failed,
}

class DirectReportDeliveryResult {
  final DirectReportDeliveryStatus status;
  final String message;

  const DirectReportDeliveryResult._({
    required this.status,
    required this.message,
  });

  factory DirectReportDeliveryResult.sent(String message) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.sent,
      message: message,
    );
  }

  factory DirectReportDeliveryResult.queued(String message) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.queued,
      message: message,
    );
  }

  factory DirectReportDeliveryResult.failed(String message) {
    return DirectReportDeliveryResult._(
      status: DirectReportDeliveryStatus.failed,
      message: message,
    );
  }

  bool get isSent => status == DirectReportDeliveryStatus.sent;

  bool get isQueued => status == DirectReportDeliveryStatus.queued;
}

/// מערכת ההפעלה של המחשב המחובר שאליו מיועד סקריפט השליחה האופליין.
enum OfflineSendScriptTarget { windows, unix }

/// תוצר בניית סקריפט השליחה: תוכן הקובץ ושם הקובץ המתאים.
class OfflineSendScript {
  final String content;
  final String fileName;

  const OfflineSendScript({required this.content, required this.fileName});
}

class DirectErrorReportService {
  static const String _endpoint = 'https://otzaria.org/api/reportingerrors';
  static const String _queueBoxName = 'error_reports_queue';
  static const String _queueKey = 'pending_reports';
  static const String _sentKey = 'sent_reports';
  static const int _maxSentReportsToKeep = 100;
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _flushInterval = Duration(minutes: 5);
  static const int _maxQueuedFlushPerRun = 20;
  static const String _otzariaDirectReportTarget = 'אוצריא';
  static const String _sefariaDirectReportTarget = 'ספריא';
  static const String _psBodyMarker = 'OTZARIA_REPORTS_PS_BODY';

  static Timer? _flushTimer;
  static bool _isFlushing = false;

  final http.Client _client;
  final HiveListRepository<DirectErrorReport> _queueRepository;
  final HiveListRepository<DirectErrorReport> _sentRepository;

  DirectErrorReportService({
    http.Client? client,
    HiveListRepository<DirectErrorReport>? queueRepository,
    HiveListRepository<DirectErrorReport>? sentRepository,
  }) : _client = client ?? http.Client(),
       _queueRepository =
           queueRepository ??
           HiveListRepository<DirectErrorReport>(
             boxName: _queueBoxName,
             key: _queueKey,
             fromJson: DirectErrorReport.fromJson,
             toJson: (report) => report.toJson(),
           ),
       _sentRepository =
           sentRepository ??
           HiveListRepository<DirectErrorReport>(
             boxName: _queueBoxName,
             key: _sentKey,
             fromJson: DirectErrorReport.fromJson,
             toJson: (report) => report.toJson(),
           );

  /// סוגר את ה-HTTP client הפנימי. ב-Windows admin install הקרנל נתקע
  /// לכמה שניות בעת ניקוי socket handles ביציאה, אז יש לקרוא לפונקציה
  /// הזו כשלב מקדים ל-onWindowClose עבור המופע הארוך-טווח (זה שמריץ
  /// את `startAutomaticFlush` ב-main.dart). מופעים קצרי-טווח שנוצרים
  /// בדיאלוגים ובמסכי הגדרות לא צריכים להיכלל כאן.
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

  Future<int> getPendingReportsCount() async {
    final reports = await _queueRepository.load();
    return reports.length;
  }

  Future<List<DirectErrorReport>> getPendingReports() async {
    return _queueRepository.load();
  }

  Future<List<DirectErrorReport>> getSentReports() async {
    return _sentRepository.load();
  }

  Future<void> deleteSentReport(String reportId) async {
    final reports = await _sentRepository.load();
    reports.removeWhere((report) => report.id == reportId);
    await _sentRepository.save(reports);
  }

  Future<void> clearSentReports() async {
    await _sentRepository.clear();
  }

  Future<void> updatePendingReport(DirectErrorReport report) async {
    final reports = await _queueRepository.load();
    final index = reports.indexWhere((item) => item.id == report.id);
    if (index == -1) {
      return;
    }

    reports[index] = report;
    await _queueRepository.save(reports);
  }

  Future<void> deletePendingReport(String reportId) async {
    final reports = await _queueRepository.load();
    reports.removeWhere((report) => report.id == reportId);
    await _queueRepository.save(reports);
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
    await _queueRepository.clear();
  }

  Future<DirectReportDeliveryResult> submitPendingReport(
    DirectErrorReport report,
  ) async {
    final result = await submitReport(report);
    if (result.isSent) {
      await deletePendingReport(report.id);
    }
    return result;
  }

  /// בונה סקריפט שליחה של הדיווחים השמורים, מותאם למערכת ההפעלה של המחשב
  /// המחובר שבו יופעל. הסקריפט קריא לבני אדם (ללא Base64), ומציג את התוצאה
  /// בחלון מערכת כדי להימנע מג'יבריש עברית בקונסול.
  OfflineSendScript buildOfflineSendScript(
    List<DirectErrorReport> reports, {
    required OfflineSendScriptTarget target,
  }) {
    switch (target) {
      case OfflineSendScriptTarget.windows:
        return OfflineSendScript(
          content: _buildWindowsBatchScript(reports),
          fileName: 'otzaria_send_saved_reports.bat',
        );
      case OfflineSendScriptTarget.unix:
        return OfflineSendScript(
          content: _buildUnixShellScript(reports),
          fileName: 'otzaria_send_saved_reports.sh',
        );
    }
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
      await _saveSentReport(report);
      unawaited(flushPendingReports(onlyAutomaticRetry: true));
      if (_isSefariaReport(report)) {
        return DirectReportDeliveryResult.sent(ReportMessages.sentToSefaria);
      }

      return DirectReportDeliveryResult.sent(ReportMessages.sentToOtzaria);
    }

    if (attemptResult.isPermanentFailure) {
      return DirectReportDeliveryResult.failed(attemptResult.message);
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
    final normalizedSource = report.sourceFolder.trim().toLowerCase();
    return normalizedSource.contains('sefariatootzaria') ||
        normalizedSource.contains('sefaria');
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
    try {
      final pendingReports = await _queueRepository.load();
      if (pendingReports.isEmpty) {
        return 0;
      }

      final reportsToAttempt = onlyAutomaticRetry
          ? pendingReports
                .where(
                  (report) =>
                      report.queueType ==
                      DirectErrorReportQueueType.automaticRetry,
                )
                .take(_maxQueuedFlushPerRun)
                .toList()
          : pendingReports.take(_maxQueuedFlushPerRun).toList();

      if (reportsToAttempt.isEmpty) {
        return 0;
      }

      final remainingReports = List<DirectErrorReport>.from(pendingReports);
      var sentCount = 0;

      for (final report in reportsToAttempt) {
        final attemptResult = await _trySend(report);

        if (attemptResult.isSuccess) {
          remainingReports.removeWhere((item) => item.id == report.id);
          await _saveSentReport(report);
          sentCount++;
          continue;
        }

        if (attemptResult.isPermanentFailure) {
          debugPrint(
            'Direct report permanently failed and was removed from queue: ${report.id}',
          );
          remainingReports.removeWhere((item) => item.id == report.id);
          continue;
        }

        break;
      }

      await _queueRepository.save(remainingReports);
      return sentCount;
    } finally {
      _isFlushing = false;
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
    final pendingReports = await _queueRepository.load();
    final alreadyQueued = pendingReports.any((item) => item.id == report.id);
    if (alreadyQueued) {
      return;
    }

    pendingReports.add(report.copyWith(queueType: queueType));
    await _queueRepository.save(pendingReports);
  }

  Future<void> _saveSentReport(DirectErrorReport report) async {
    final sentReports = await _sentRepository.load();
    sentReports.removeWhere((item) => item.id == report.id);
    sentReports.insert(0, report);
    if (sentReports.length > _maxSentReportsToKeep) {
      sentReports.removeRange(_maxSentReportsToKeep, sentReports.length);
    }
    await _sentRepository.save(sentReports);
  }

  Future<_SendAttemptResult> _trySend(DirectErrorReport report) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(report.toApiPayload()),
          )
          .timeout(_timeout);

      if (response.statusCode == HttpStatus.ok) {
        return const _SendAttemptResult.success();
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

  bool _isPermanentHttpFailure(int statusCode) {
    return statusCode == HttpStatus.badRequest || statusCode == 422;
  }

  /// בונה קובץ .bat קריא: שורת הפעלה קצרה שקוראת את הקובץ עצמו, מחלצת את גוף
  /// ה-PowerShell שאחרי הסמן ומריצה אותו. הסמן נבנה ב-PowerShell מ-[char]35
  /// כדי שלא יופיע כפי שהוא בשורת הפקודה ויתנגש עם החיפוש.
  String _buildWindowsBatchScript(List<DirectErrorReport> reports) {
    final payloads = reports.map((report) => report.toApiPayload()).toList();
    final payloadJson = jsonEncode(payloads);
    final powerShellBody = _buildWindowsPowerShellBody(payloadJson);
    final script =
        '''@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "\$f=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); \$m=[char]35+'$_psBodyMarker'; iex \$f.Substring(\$f.IndexOf(\$m)+\$m.Length)"
exit /b %ERRORLEVEL%
#$_psBodyMarker
$powerShellBody''';
    // cmd.exe דורש CRLF; מנרמלים קודם ל-LF כדי שמקור CRLF לא ייצור \r\r\n.
    return script.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  }

  String _buildWindowsPowerShellBody(String payloadJson) {
    return '''Add-Type -AssemblyName System.Windows.Forms | Out-Null
\$ErrorActionPreference = 'Stop'
\$endpoint = '$_endpoint'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

\$payloadsJson = @'
$payloadJson
'@

\$payloads = \$payloadsJson | ConvertFrom-Json
\$sent = 0
\$failed = 0
\$lines = @()
foreach (\$payload in @(\$payloads)) {
  try {
    \$body = \$payload | ConvertTo-Json -Depth 10 -Compress
    \$bodyBytes = [System.Text.Encoding]::UTF8.GetBytes(\$body)
    \$response = Invoke-WebRequest -Uri \$endpoint -Method Post -ContentType 'application/json; charset=utf-8' -Body \$bodyBytes -UseBasicParsing
    if (\$response.StatusCode -eq 200) {
      \$sent++
      \$lines += ('נשלח: ' + \$payload.report_id)
    } else {
      \$failed++
      \$lines += ('נכשל: ' + \$payload.report_id + ' (סטטוס ' + \$response.StatusCode + ')')
    }
  } catch {
    \$failed++
    \$lines += ('נכשל: ' + \$payload.report_id + ' (' + \$_.Exception.Message + ')')
  }
}

\$summary = "נשלחו בהצלחה: \$sent`r`nנכשלו: \$failed`r`n`r`n" + (\$lines -join "`r`n")
[System.Windows.Forms.MessageBox]::Show(\$summary, '${ReportMessages.offlineScriptWindowTitle}') | Out-Null''';
  }

  /// בונה קובץ .sh ל-Linux/macOS: שולח כל דיווח ב-curl ומציג את הסיכום בחלון
  /// גרפי (zenity/kdialog/osascript) עם נפילה חזרה לפלט במסוף אם אין כלי גרפי.
  String _buildUnixShellScript(List<DirectErrorReport> reports) {
    final buffer = StringBuffer()
      ..writeln('#!/usr/bin/env bash')
      ..writeln("endpoint='$_endpoint'")
      ..writeln('sent=0')
      ..writeln('failed=0')
      ..writeln('results=""')
      ..writeln('')
      ..writeln('send_one() {')
      ..writeln('  local body="\$1"')
      ..writeln('  local id="\$2"')
      ..writeln('  local code')
      ..writeln(
        "  code=\$(printf '%s' \"\$body\" | curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json; charset=utf-8' --data-binary @- \"\$endpoint\")",
      )
      ..writeln('  if [ "\$code" = "200" ]; then')
      ..writeln('    sent=\$((sent + 1))')
      ..writeln('    results="\${results}\\nנשלח: \${id}"')
      ..writeln('  else')
      ..writeln('    failed=\$((failed + 1))')
      ..writeln('    results="\${results}\\nנכשל: \${id} (סטטוס \${code})"')
      ..writeln('  fi')
      ..writeln('}')
      ..writeln('');

    for (var index = 0; index < reports.length; index++) {
      final report = reports[index];
      final payloadJson = jsonEncode(report.toApiPayload());
      final delimiter = 'OTZARIA_PAYLOAD_$index';
      buffer
        ..writeln('send_one "\$(cat <<\'$delimiter\'')
        ..writeln(payloadJson)
        ..writeln(delimiter)
        ..writeln(')" ${_shellSingleQuote(report.id)}');
    }

    buffer
      ..writeln('')
      ..writeln(
        'summary="נשלחו בהצלחה: \${sent}\\nנכשלו: \${failed}\\n\${results}"',
      )
      ..writeln('tmp="\$(mktemp)"')
      ..writeln("printf '%b\\n' \"\$summary\" > \"\$tmp\"")
      ..writeln('if command -v zenity >/dev/null 2>&1; then')
      ..writeln(
        "  zenity --text-info --filename=\"\$tmp\" --title='${ReportMessages.offlineScriptWindowTitle}'",
      )
      ..writeln('elif command -v kdialog >/dev/null 2>&1; then')
      ..writeln(
        "  kdialog --title '${ReportMessages.offlineScriptWindowTitle}' --textbox \"\$tmp\"",
      )
      ..writeln('elif command -v osascript >/dev/null 2>&1; then')
      ..writeln(
        "  osascript -e \"display dialog (do shell script \\\"cat \\\" & quoted form of \\\"\$tmp\\\") buttons {\\\"סגור\\\"} with title \\\"${ReportMessages.offlineScriptWindowTitle}\\\"\" >/dev/null 2>&1",
      )
      ..writeln('else')
      ..writeln("  cat \"\$tmp\"")
      ..writeln('fi')
      ..writeln('rm -f "\$tmp"');

    return buffer.toString();
  }

  String _shellSingleQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }
}

class _SendAttemptResult {
  final bool isSuccess;
  final String message;
  final _SendAttemptFailureType? failureType;

  const _SendAttemptResult._({
    required this.isSuccess,
    required this.message,
    this.failureType,
  });

  const _SendAttemptResult.success()
    : this._(isSuccess: true, message: '', failureType: null);

  bool get isPermanentFailure =>
      !isSuccess && failureType == _SendAttemptFailureType.permanent;

  factory _SendAttemptResult.transientFailure(String message) {
    return _SendAttemptResult._(
      isSuccess: false,
      message: message,
      failureType: _SendAttemptFailureType.transient,
    );
  }

  factory _SendAttemptResult.permanentFailure(String message) {
    return _SendAttemptResult._(
      isSuccess: false,
      message: message,
      failureType: _SendAttemptFailureType.permanent,
    );
  }
}

enum _SendAttemptFailureType {
  transient,
  permanent,
}
