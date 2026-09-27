import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/responsa_failure.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_launcher.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';

/// מצב פרויקט השו"ת כפי שאוצריא רואה אותו.
class ResponsaStatus {
  final bool installed;
  final bool running;
  final int? version;
  final String? installPath;
  final int? pid;
  final ResponsaVersionConfidence confidence;
  final List<ResponsaInstallation> installations;

  const ResponsaStatus({
    required this.installed,
    required this.running,
    required this.confidence,
    this.version,
    this.installPath,
    this.pid,
    this.installations = const [],
  });

  static const ResponsaStatus notInstalled = ResponsaStatus(
    installed: false,
    running: false,
    confidence: ResponsaVersionConfidence.unknown,
  );

  /// אין רשימת גרסאות נתמכות - המבנה נבדק בזמן הפתיחה, ולכן כל מהדורה
  /// מותקנת היא מועמדת.
  bool get canOpen => installed;
}

/// תוצאת פתיחה כפי שהיא חוזרת ל-UI. `ok == false` הוא ערך, לא חריג.
class ResponsaOpenReport {
  final bool ok;
  final ResponsaFailure? failure;
  final String? message;
  final String? window;
  final String? usedRef;

  /// ההפניות שנוסו. בכשל זה מה שהופך "לא נמצא" להודעה שאפשר לפעול לפיה.
  final List<String> triedRefs;

  /// כותרות החלונות שאוצריא פתחה במופע, כולל מפתיחות קודמות.
  final List<String> openedWindows;

  const ResponsaOpenReport({
    required this.ok,
    this.failure,
    this.message,
    this.window,
    this.usedRef,
    this.triedRefs = const [],
    this.openedWindows = const [],
  });
}

/// הגבול בין UI אסינכרוני לאוטומציה חוסמת: כל פעולה חוסמת רצה באיזולט רקע,
/// כי ב-Windows ה-UI isolate רץ על ה-platform thread וקריאת Win32 מקפיאה אותו.
class ResponsaController {
  ResponsaController({bool Function()? allowAutoStart})
    : _allowAutoStart = allowAutoStart ?? _always;

  static bool _always() => true;

  final bool Function() _allowAutoStart;

  /// נקרא מחדש בכל פעם ולא נלכד בבנייה: הבקר נוצר לפני שהמשתמש מדליק את
  /// ההגדרה, וערך לכוד היה נשאר `false` עד הפעלה מחדש.
  bool get autoStart => _allowAutoStart();

  var _busy = false;

  /// כאן ולא באוטומציה, כי כל פתיחה רצה באיזולט משלה; בלעדיה
  /// `releaseMdiWindows` לא מכיר את חלונותינו וסוגר את של המשתמש.
  final List<String> _openedWindows = [];

  /// חלון ראשי אחרי הפעלה קרה עולה בדרך כלל תוך ~5 שניות.
  static const Duration launchTimeout = Duration(seconds: 60);

  static const Duration openBudget = Duration(minutes: 3);

  /// מצב ההתקנה והמופע. מהיר; אינו נוגע בתוכנה.
  Future<ResponsaStatus> status() async {
    if (!Platform.isWindows) return ResponsaStatus.notInstalled;
    return Isolate.run(_readStatus);
  }

  static ResponsaStatus _readStatus() {
    final installations = ResponsaInstallationDiscovery.discover();
    final usable = installations.where((i) => i.exists).toList();
    final live = ResponsaInstance.all();
    // "רץ" = יש מופע שאפשר לעבוד מולו; מופע חונה מחוץ למסך אינו נחשב.
    final active = ResponsaInstance.pick(live);

    int? version;
    if (active != null) {
      version = ResponsaInstallationDiscovery.versionFromWindowTitle(
        active.title,
      );
    }
    version ??= usable.isEmpty ? null : usable.first.version;

    if (usable.isEmpty && live.isEmpty) return ResponsaStatus.notInstalled;
    return ResponsaStatus(
      installed: usable.isNotEmpty || live.isNotEmpty,
      running: active != null,
      version: version,
      installPath: usable.isEmpty ? null : usable.first.installPath,
      pid: active?.pid,
      confidence: ResponsaVersionProfile.forVersion(version).confidence,
      installations: installations,
    );
  }

  /// [installPath] = ההתקנה שממנה נבנה הקטלוג: הפניה ממאגר אחד לא בהכרח
  /// מוליכה לאותו ספר במאגר אחר.
  Future<ResponsaOpenReport> openBook(
    List<String> references, {
    String? expectedTitle,
    String? installPath,
  }) async {
    if (!Platform.isWindows) {
      return const ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: 'פתיחת ספרים בבר אילן נתמכת ב-Windows בלבד.',
      );
    }

    // פתיחה אחת בכל רגע: שתי פתיחות חופפות מתחרות על אותו מופע
    // ומשאירות חלונות פתוחים שאיש אינו סוגר.
    if (_busy) {
      return const ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: 'פתיחת ספר בבר אילן כבר מתבצעת. יש להמתין לסיומה.',
      );
    }
    _busy = true;
    try {
      final launch = await _ensureRunning(installPath);
      if (launch != null) return launch;

      final report = await _runInIsolate(
        _OpenRequest(
          references: references,
          expectedTitle: expectedTitle,
          installPath: installPath,
          openedWindows: List.of(_openedWindows),
        ),
      );
      if (report.openedWindows.isNotEmpty) {
        _openedWindows
          ..clear()
          ..addAll(report.openedWindows);
      }
      return report;
    } finally {
      _busy = false;
    }
  }

  Future<ResponsaOpenReport> _runInIsolate(_OpenRequest request) async {
    try {
      return await Isolate.run(() => _openBookInIsolate(request));
    } catch (error, stackTrace) {
      // כשל לא צפוי באיזולט לעולם לא מגיע ל-UI כחריג.
      debugPrint('ResponsaController: isolate failed: $error\n$stackTrace');
      return ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.timeout,
        message: 'פתיחת הספר בבר אילן נכשלה באופן בלתי צפוי: $error',
      );
    }
  }

  /// `null` כשהכול תקין. הכשל הוא `responsaNotRunning` ולא `timeout`, שהיה
  /// מציג בטעות "התוכנה אינה מגיבה".
  Future<ResponsaOpenReport?> _ensureRunning(String? installPath) async {
    final result = await ResponsaLauncher.ensureRunning(
      installPath: installPath,
      allowLaunch: autoStart,
      timeout: launchTimeout,
    );
    if (result.running) return null;
    return ResponsaOpenReport(
      ok: false,
      failure: ResponsaFailure.responsaNotRunning,
      message: result.message,
    );
  }

  // ------------------------------------------------ מה שרץ באיזולט

  static Future<ResponsaOpenReport> _openBookInIsolate(
    _OpenRequest request,
  ) async {
    // רק מופע של ההתקנה שממנה נבנה הקטלוג, ולא חונה מחוץ למסך - שם הספר
    // נפתח והמשתמש אינו רואה דבר.
    final selection = ResponsaInstallationDiscovery.selectInstallation(
      preferredPath: request.installPath,
    );
    final instance = selection == null
        ? null
        : ResponsaInstance.pick(selection.instances);
    if (instance == null) {
      return ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: selection == null
            ? 'בר אילן אינו מותקן במחשב הזה.'
            : 'בר אילן (${selection.installation.displayName}) אינו פעיל. '
                  'יש לפתוח אותו ולנסות שוב.',
      );
    }

    final version = ResponsaInstallationDiscovery.versionFromWindowTitle(
      instance.title,
    );

    final automation = ResponsaAutomation(
      pid: instance.pid,
      profile: ResponsaVersionProfile.forVersion(version),
      openedWindows: request.openedWindows,
    );

    try {
      final outcome = automation.openBook(
        request.references,
        ResponsaDeadline(openBudget),
        expectedTitle: request.expectedTitle,
      );
      return ResponsaOpenReport(
        ok: true,
        window: outcome.window,
        usedRef: outcome.usedRef,
        triedRefs: outcome.triedRefs,
        openedWindows: automation.openedWindows,
      );
    } on ResponsaAutomationException catch (error) {
      return ResponsaOpenReport(
        ok: false,
        failure: error.failure,
        message: error.message,
        triedRefs: switch (error.details['tried']) {
          final List<String> tried => tried,
          _ => request.references,
        },
        // גם בכשל: ייתכן שנפתח חלון ונפסל, והוא שלנו לסגור.
        openedWindows: automation.openedWindows,
      );
    }
  }
}

class _OpenRequest {
  final List<String> references;
  final String? expectedTitle;
  final String? installPath;

  /// החלונות שאוצריא פתחה בפתיחות קודמות.
  final List<String> openedWindows;

  const _OpenRequest({
    required this.references,
    this.expectedTitle,
    this.installPath,
    this.openedWindows = const [],
  });
}
