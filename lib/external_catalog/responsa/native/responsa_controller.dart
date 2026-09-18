import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

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

  /// האם אפשר לנסות לפתוח ספר. אין כאן רשימת גרסאות — המבנה נבדק בפועל
  /// בזמן הפתיחה, ולכן כל מהדורה מותקנת היא מועמדת.
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

  const ResponsaOpenReport({
    required this.ok,
    this.failure,
    this.message,
    this.window,
    this.usedRef,
    this.triedRefs = const [],
  });
}

/// הפעלת פרויקט השו"ת ושליטה בו — מתוך אוצריא, בלי שום רכיב חיצוני.
///
/// **כל פעולה חוסמת רצה באיזולט רקע.** על Windows ה-UI isolate רץ על
/// ה-platform thread, וקריאת Win32 סינכרונית שם מקפיאה כל פריים וכל
/// טיימר. הבקר הוא הגבול: מעליו הכול אסינכרוני, מתחתיו הכול חוסם.
///
/// הביטול אמיתי: דגל ב**זיכרון משותף** (`Pointer<Int32>`) שהאיזולט בודק
/// בכל נקודת המתנה. פורט הודעות לא היה עובד — האיזולט חסום בקוד
/// סינכרוני ואינו מעבד הודעות.
class ResponsaController {
  ResponsaController({this.autoStart = true});

  /// האם מותר להעלות מופע של התוכנה כשאינה רצה.
  final bool autoStart;

  Pointer<Int32>? _cancelFlag;
  Isolate? _running;

  /// כמה להמתין לחלון הראשי אחרי הפעלה קרה. נמדד ~5 שניות.
  static const Duration launchTimeout = Duration(seconds: 60);

  static const Duration openBudget = Duration(minutes: 3);
  static const Duration simanBudget = Duration(seconds: 90);

  /// מצב ההתקנה והמופע. מהיר; אינו נוגע בתוכנה.
  Future<ResponsaStatus> status() async {
    if (!Platform.isWindows) return ResponsaStatus.notInstalled;
    return Isolate.run(_readStatus);
  }

  static ResponsaStatus _readStatus() {
    final installations = ResponsaInstallationDiscovery.discover();
    final usable = installations.where((i) => i.exists).toList();
    final live = ResponsaWin32.topWindowsByClass('ResponsaProject');

    int? version;
    int? pid;
    if (live.isNotEmpty) {
      pid = live.first.pid;
      version = ResponsaInstallationDiscovery.versionFromWindowTitle(
        ResponsaWin32.windowText(live.first.hwnd),
      );
    }
    version ??= usable.isEmpty ? null : usable.first.version;

    if (usable.isEmpty && live.isEmpty) return ResponsaStatus.notInstalled;
    return ResponsaStatus(
      installed: usable.isNotEmpty || live.isNotEmpty,
      running: live.isNotEmpty,
      version: version,
      installPath: usable.isEmpty ? null : usable.first.installPath,
      pid: pid,
      confidence: ResponsaVersionProfile.forVersion(version).confidence,
      installations: installations,
    );
  }

  /// פותח ספר. [references] הוא סולם ההפניות מהקטלוג, לא הכותרת.
  ///
  /// [installPath] הוא נתיב ההתקנה שממנה נבנה הקטלוג. הוא אינו קישוט:
  /// הפניה שנבנתה ממאגר אחד אינה בהכרח מוליכה לאותו ספר במאגר אחר, ועל
  /// מחשב עם שתי התקנות אפשר בקלות לפתוח את הספר הלא-נכון.
  Future<ResponsaOpenReport> openBook(
    List<String> references, {
    String? expectedTitle,
    int? siman,
    String? installPath,
  }) async {
    if (!Platform.isWindows) {
      return const ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: 'פתיחת ספרים בבר אילן נתמכת ב-Windows בלבד.',
      );
    }

    final launch = await _ensureRunning(installPath);
    if (launch != null) return launch;

    return _runCancellable(
      (flagAddress) => _OpenRequest(
        references: references,
        expectedTitle: expectedTitle,
        siman: siman,
        installPath: installPath,
        cancelFlagAddress: flagAddress,
      ),
      _openBookInIsolate,
    );
  }

  /// מבטל את הפעולה הרצה. הביטול אמיתי — האיזולט עוצר בנקודת ההמתנה
  /// הבאה ומחזיר `cancelled`.
  void cancel() {
    final flag = _cancelFlag;
    if (flag != null) flag.value = 1;
  }

  bool get isBusy => _running != null;

  Future<ResponsaOpenReport> _runCancellable(
    _OpenRequest Function(int flagAddress) build,
    Future<ResponsaOpenReport> Function(_OpenRequest) body,
  ) async {
    final flag = calloc<Int32>();
    _cancelFlag = flag;
    try {
      return await Isolate.run(() => body(build(flag.address)));
    } catch (error, stackTrace) {
      // כשל לא צפוי באיזולט לעולם לא מגיע ל-UI כחריג.
      debugPrint('ResponsaController: isolate failed: $error\n$stackTrace');
      return ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.timeout,
        message: 'פתיחת הספר בבר אילן נכשלה באופן בלתי צפוי: $error',
      );
    } finally {
      _cancelFlag = null;
      calloc.free(flag);
    }
  }

  /// ההתקנה שיש לעבוד מולה ומצבה, כפי שנקרא באיזולט רקע.
  ///
  /// `null` כשאין אף התקנה שימושית.
  static Future<({String executable, String installPath, bool running})?>
  _resolveTarget(String? installPath) => Isolate.run(() {
    final selection = ResponsaInstallationDiscovery.selectInstallation(
      preferredPath: installPath,
    );
    if (selection == null) return null;
    return (
      executable: selection.installation.executable,
      installPath: selection.installation.installPath,
      running: selection.instances.isNotEmpty,
    );
  });

  /// מוודא שהתוכנה רצה, ומעלה אותה אם מותר.
  ///
  /// **לעולם בלי ארגומנטים.** ארגומנט שאינו מתג מפיל את `RESPONSA.exe`
  /// מיד ב-`0xC000041D`, בלי חלון ובלי הודעה — וזה נראה למשתמש כאילו
  /// אוצריא הפילה את התוכנה.
  Future<ResponsaOpenReport?> _ensureRunning(String? installPath) async {
    // "רץ" נמדד מול **ההתקנה הנכונה**, לא מול כל מופע שהוא. על מחשב עם
    // שתי התקנות, מופע חי של האחת גרם לדלג על ההפעלה של האחרת, ואז
    // הפתיחה נכשלה ב"אינו פעיל" בלי שאיש ניסה להפעיל דבר.
    var target = await _resolveTarget(installPath);
    if (target == null) {
      return const ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: 'בר אילן (פרויקט השו"ת) אינו מותקן במחשב הזה.',
      );
    }
    if (target.running) return null;
    if (!autoStart) {
      return const ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: 'הפעלת בר אילן מתוך אוצריא כבויה בהגדרות.',
      );
    }

    try {
      await Process.start(
        target.executable,
        const [],
        workingDirectory: target.installPath,
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      debugPrint('ResponsaController: launch failed: $error');
      return const ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: 'לא ניתן להפעיל את בר אילן. יש לפתוח אותו ידנית ולנסות שוב.',
      );
    }

    final deadline = DateTime.now().add(launchTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      target = await _resolveTarget(installPath);
      if (target?.running ?? false) return null;
    }
    // `responsaNotRunning` ולא `timeout`: התוכנה אינה רצה, וזה מה
    // שהמשתמש צריך לדעת. `timeout` היה מוביל להודעה על תוכנה שאינה
    // מגיבה, שהיא תיאור שגוי של המצב.
    return const ResponsaOpenReport(
      ok: false,
      failure: ResponsaFailure.responsaNotRunning,
      message: 'בר אילן לא עלה בזמן שהוקצב. יש לפתוח אותו ולנסות שוב.',
    );
  }

  // ------------------------------------------------ מה שרץ באיזולט

  static Future<ResponsaOpenReport> _openBookInIsolate(
    _OpenRequest request,
  ) async {
    // המופעים של **ההתקנה שממנה נבנה הקטלוג** בלבד. מופע של התקנה אחרת
    // יכול להציג מאגר אחר, ולפתוח ספר שאינו זה שהמשתמש ביקש.
    final selection = ResponsaInstallationDiscovery.selectInstallation(
      preferredPath: request.installPath,
    );
    final live = selection?.instances ?? const <({int hwnd, int pid})>[];
    if (live.isEmpty) {
      return ResponsaOpenReport(
        ok: false,
        failure: ResponsaFailure.responsaNotRunning,
        message: selection == null
            ? 'בר אילן אינו מותקן במחשב הזה.'
            : 'בר אילן (${selection.installation.displayName}) אינו פעיל. '
                  'יש לפתוח אותו ולנסות שוב.',
      );
    }

    // מבין אלה — הפנוי ביותר: אין single-instance, ומופע שצבר חלונות
    // רבים מפסיק לפתוח חדשים.
    live.sort(
      (a, b) => ResponsaWin32.mdiTitles(a.hwnd).length.compareTo(
        ResponsaWin32.mdiTitles(b.hwnd).length,
      ),
    );
    final instance = live.first;
    final version = ResponsaInstallationDiscovery.versionFromWindowTitle(
      ResponsaWin32.windowText(instance.hwnd),
    );

    final flag = Pointer<Int32>.fromAddress(request.cancelFlagAddress);
    final automation = ResponsaAutomation(
      pid: instance.pid,
      profile: ResponsaVersionProfile.forVersion(version),
    )..cancelled = () => flag.value != 0;

    try {
      final outcome = automation.openBook(
        request.references,
        ResponsaDeadline(openBudget),
        expectedTitle: request.expectedTitle,
      );
      if (request.siman != null) {
        // כשל בניווט אינו מבטל פתיחה מוצלחת — הספר פתוח, רק לא בסימן.
        try {
          automation.gotoSiman(
            _bookTitleOf(outcome.window),
            request.siman!,
            ResponsaDeadline(simanBudget),
          );
        } on ResponsaAutomationException catch (error) {
          debugPrint('gotoSiman failed: ${error.message}');
        }
      }
      return ResponsaOpenReport(
        ok: true,
        window: outcome.window,
        usedRef: outcome.usedRef,
        triedRefs: outcome.triedRefs,
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
      );
    }
  }

  /// כותרת חלון היא `<ספר> סימן <גימטריה>`; הניווט מצפה לשם הספר.
  static String _bookTitleOf(String windowTitle) {
    final index = windowTitle.indexOf('סימן');
    return index <= 0
        ? windowTitle.trim()
        : windowTitle.substring(0, index).trim();
  }
}

class _OpenRequest {
  final List<String> references;
  final String? expectedTitle;
  final int? siman;
  final String? installPath;
  final int cancelFlagAddress;

  const _OpenRequest({
    required this.references,
    required this.cancelFlagAddress,
    this.expectedTitle,
    this.siman,
    this.installPath,
  });
}
