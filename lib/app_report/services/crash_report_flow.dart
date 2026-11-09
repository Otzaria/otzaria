import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// מה שקרה בפועל עם קריסה שזוהתה בעלייה.
enum CrashReportOutcome {
  ignored,
  throttled,
  prompted,
  sentAutomatically,
  suggestedFasterDrive,
}

/// הטיפול בקריסה או בתקיעה שזוהו: לפי ההגדרה — התעלמות, שליחה אוטומטית
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
    bool Function()? isPortable,
    void Function()? showFasterDriveHint,
  }) : _service = service ?? AppReportService(),
       _collector = collector ?? AppReportCollector(),
       _redactor = redactor ?? AppReportRedactor.fromPlatform(),
       _throttle = throttle ?? AutoCrashReportThrottle.defaultLocation(),
       _readMode = readMode ?? currentMode,
       _savedEmail = savedEmail ?? AppReportBloc.savedSenderEmail,
       _clock = clock ?? DateTime.now,
       _isPortable = isPortable ?? (() => AppPaths.isPortable),
       _showFasterDriveHint = showFasterDriveHint ?? _showFasterDriveHintOnce;

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
  final bool Function() _isPortable;
  final void Function() _showFasterDriveHint;

  static bool _fasterDriveHintShown = false;

  static void _showFasterDriveHintOnce() {
    // בלי Navigator ההודעה לא מוצגת; ננסה שוב באירוע הבא.
    if (_fasterDriveHintShown || navigatorKey.currentContext == null) return;
    _fasterDriveHintShown = true;
    UiSnack.showWarning(
      ReportMessages.portableSlowDriveHint,
      duration: const Duration(seconds: 12),
    );
  }

  /// מצב הדיווח אחרי קריסה כפי שהוא שמור בהגדרות.
  static AppCrashReportMode currentMode() {
    if (!Settings.isInitialized) return AppCrashReportMode.ask;
    return AppCrashReportMode.parse(
      Settings.getValue<String>(SettingsRepository.keyAppCrashReportMode),
    );
  }

  static Future<void> _automaticReportTail = Future.value();

  Future<CrashReportOutcome> handle(CrashCandidate candidate) {
    if (_readMode() != AppCrashReportMode.always) return _handle(candidate);
    // המכסה משותפת לכל המופעים; הבדיקה, השליחה והרישום חייבים לרוץ יחד.
    final next = _automaticReportTail.then((_) => _handle(candidate));
    _automaticReportTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<CrashReportOutcome> _handle(CrashCandidate candidate) async {
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
      isPortable: _isPortable(),
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
      case CrashReportAction.suggestFasterDrive:
        _showFasterDriveHint();
        return CrashReportOutcome.suggestedFasterDrive;
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
      type: CrashReportDecision.reportTypeFor(candidate),
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
      diagnostics: candidate.details == null
          ? attachments?.diagnostics
          : {...?attachments?.diagnostics, 'hangDetails': candidate.details},
      errorLog: attachments?.errorLog,
      // בלי minidump: הוא מכיל זיכרון של התהליך ונשלח רק בהסכמה בטופס.
    ).redactedWith(_redactor);
    await _service.send(report);
  }
}
