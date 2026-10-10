import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// מה שקרה בפועל עם קריסה שזוהתה בעלייה.
enum CrashReportOutcome { ignored, throttled, prompted, sentAutomatically }

/// הטיפול בקריסה של ההפעלה הקודמת: לפי ההגדרה — התעלמות, שליחה אוטומטית
/// (בכפוף למגבלה) או הצגת ההצעה למשתמש.
class CrashReportFlow {
  CrashReportFlow({
    required this.showPrompt,
    AppReportService? service,
    AppReportCollector? collector,
    AppReportRedactor? redactor,
    AutoCrashReportThrottle? throttle,
    AppCrashReportMode Function()? readMode,
    String Function()? savedEmail,
    this.appVersion,
    DateTime Function()? clock,
  }) : _service = service ?? AppReportService(),
       _collector = collector ?? AppReportCollector(),
       _redactor = redactor ?? AppReportRedactor.fromPlatform(),
       _throttle = throttle ?? AutoCrashReportThrottle.defaultLocation(),
       _readMode = readMode ?? currentMode,
       _savedEmail = savedEmail ?? AppReportBloc.savedSenderEmail,
       _clock = clock ?? DateTime.now;

  /// מציג את ההצעה למשתמש; מחזיר false כשאין עדיין Navigator להציג בו.
  final Future<bool> Function(CrashCandidate candidate) showPrompt;

  /// גרסת התוכנה לדיווח; ברירת המחדל היא הגרסה הרשומה בלוג.
  final String? appVersion;

  final AppReportService _service;
  final AppReportCollector _collector;
  final AppReportRedactor _redactor;
  final AutoCrashReportThrottle _throttle;
  final AppCrashReportMode Function() _readMode;
  final String Function() _savedEmail;
  final DateTime Function() _clock;

  /// מצב הדיווח אחרי קריסה כפי שהוא שמור בהגדרות.
  static AppCrashReportMode currentMode() {
    if (!Settings.isInitialized) return AppCrashReportMode.ask;
    return AppCrashReportMode.parse(
      Settings.getValue<String>(SettingsRepository.keyAppCrashReportMode),
    );
  }

  Future<CrashReportOutcome> handle(CrashCandidate candidate) async {
    final mode = _readMode();
    final version = appVersion ?? ErrorLogFile.appVersion;
    final throttleKey = CrashReportDecision.throttleKeyFor(candidate);
    final throttleAllows =
        mode != AppCrashReportMode.always ||
        await _throttle.canReport(
          signatureHash: throttleKey,
          appVersion: version,
        );

    switch (CrashReportDecision.decide(
      mode: mode,
      candidate: candidate,
      throttleAllows: throttleAllows,
    )) {
      case CrashReportAction.none:
        return mode == AppCrashReportMode.always
            ? CrashReportOutcome.throttled
            : CrashReportOutcome.ignored;
      case CrashReportAction.prompt:
        final shown = await showPrompt(candidate);
        return shown ? CrashReportOutcome.prompted : CrashReportOutcome.ignored;
      case CrashReportAction.sendAutomatically:
        await _sendAutomatically(candidate, version: version);
        // נרשם גם כשהדיווח רק נשמר בתור — אחרת עלייה חוזרת תשלח אותו שוב.
        await _throttle.recordReported(
          signatureHash: throttleKey,
          appVersion: version,
        );
        return CrashReportOutcome.sentAutomatically;
    }
  }

  Future<void> _sendAutomatically(
    CrashCandidate candidate, {
    required String version,
  }) async {
    AppReportAttachments? attachments;
    try {
      attachments = await _collector.collect();
    } catch (error) {
      debugPrint('Auto crash report: collection failed: $error');
    }
    final report = AppReport(
      reportId: AppReport.generateReportId(),
      type: AppReportType.crash,
      trigger: AppReportTrigger.autoCrash,
      title: CrashReportDecision.titleFor(candidate),
      // מייל שמור לא תקין היה נדחה ב-422 ומוחק את הדיווח — שולחים בלעדיו.
      reporterEmail: AppReport.isValidEmail(_savedEmail()) ? _savedEmail() : '',
      appVersion: version,
      platform: AppReport.currentPlatform(),
      osVersion: AppReportCollector.osVersion(),
      arch: AppReportCollector.detectArch(),
      signature: candidate.signature,
      createdAt: _clock(),
      diagnostics: attachments?.diagnostics,
      errorLog: attachments?.errorLog,
      // בלי minidump: הוא מכיל זיכרון של התהליך ונשלח רק בהסכמה בטופס.
    ).redactedWith(_redactor);
    await _service.send(report);
  }
}
