import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';

/// תוצאת ניסיון להעלות את בר אילן.
class ResponsaLaunchResult {
  /// `true` = יש מופע חי של ההתקנה המבוקשת.
  final bool running;

  /// ההתקנה שנבחרה, גם כשההעלאה נכשלה.
  final String? installPath;

  /// הודעה למשתמש כש-[running] הוא `false`.
  final String? message;

  const ResponsaLaunchResult({
    required this.running,
    this.installPath,
    this.message,
  });
}

/// לעולם בלי ארגומנטים: ארגומנט שאינו מתג מפיל את `RESPONSA.exe` מיד
/// ב-`0xC000041D`, בלי חלון ובלי הודעה.
class ResponsaLauncher {
  ResponsaLauncher._();

  /// חלון ראשי אחרי הפעלה קרה עולה בדרך כלל תוך ~5 שניות.
  static const Duration launchTimeout = Duration(seconds: 60);

  /// כל כמה זמן לבדוק אם המופע עלה.
  static const Duration _poll = Duration(milliseconds: 600);

  /// `running` = יש מופע שמיש, לא "יש תהליך" (חונה נחשב כבוי). באיזולט רקע
  /// כי סריקת הכוננים חוסמת.
  static Future<({String executable, String installPath, bool running})?>
  resolve(String? installPath) => Isolate.run(() {
    final selection = ResponsaInstallationDiscovery.selectInstallation(
      preferredPath: installPath,
    );
    if (selection == null) return null;
    return (
      executable: selection.installation.executable,
      installPath: selection.installation.installPath,
      running: ResponsaInstance.pick(selection.instances) != null,
    );
  });

  /// "רץ" נבדק מול ההתקנה המבוקשת ולא מול כל מופע: מופע של התקנה אחרת היה
  /// מדלג על ההפעלה.
  static Future<ResponsaLaunchResult> ensureRunning({
    String? installPath,
    bool allowLaunch = true,
    Duration timeout = launchTimeout,
  }) async {
    if (!Platform.isWindows) {
      return const ResponsaLaunchResult(
        running: false,
        message: 'בר אילן (פרויקט השו"ת) נתמך ב-Windows בלבד.',
      );
    }

    var target = await resolve(installPath);
    if (target == null) {
      return const ResponsaLaunchResult(
        running: false,
        message: 'בר אילן (פרויקט השו"ת) אינו מותקן במחשב הזה.',
      );
    }
    if (target.running) {
      return ResponsaLaunchResult(
        running: true,
        installPath: target.installPath,
      );
    }
    if (!allowLaunch) {
      return ResponsaLaunchResult(
        running: false,
        installPath: target.installPath,
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
      debugPrint('ResponsaLauncher: launch failed: $error');
      return ResponsaLaunchResult(
        running: false,
        installPath: target.installPath,
        message:
            'לא ניתן להפעיל את בר אילן מ-${target.installPath}. '
            'יש לפתוח אותו ידנית ולנסות שוב.',
      );
    }

    // בודקים מופעים בלבד ולא `resolve`, שסורק את כל הכוננים - בכל 600ms
    // זו סריקה מלאה, וההתקנה כבר ידועה.
    final wanted = target.installPath;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_poll);
      if (await _hasUsableInstance(wanted)) {
        return ResponsaLaunchResult(running: true, installPath: wanted);
      }
    }
    return ResponsaLaunchResult(
      running: false,
      installPath: wanted,
      message:
          'בר אילן הופעל אך לא עלה בתוך ${timeout.inSeconds} שניות. '
          'יש לפתוח אותו ולנסות שוב.',
    );
  }

  /// מופעים בלבד - בלי סריקת כוננים ובלי רישום.
  static Future<bool> _hasUsableInstance(String installPath) => Isolate.run(
    () =>
        ResponsaInstance.pick(
          ResponsaInstallationDiscovery.instancesOf(installPath),
        ) !=
        null,
  );
}
