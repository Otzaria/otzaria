import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
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

/// העלאת בר אילן מתוך אוצריא.
///
/// משותף לפתיחת ספר ולבניית הקטלוג. שתיהן זקוקות למופע חי, ושתיהן
/// נכשלו קודם בהודעה "אינו פעיל" בלי שאיש ניסה להפעיל דבר.
///
/// **לעולם בלי ארגומנטים.** ארגומנט שאינו מתג מפיל את `RESPONSA.exe`
/// מיד ב-`0xC000041D`, בלי חלון ובלי הודעה — וזה נראה למשתמש כאילו
/// אוצריא הפילה את התוכנה.
class ResponsaLauncher {
  ResponsaLauncher._();

  /// כמה להמתין לחלון הראשי אחרי הפעלה קרה. נמדד ~5 שניות.
  static const Duration launchTimeout = Duration(seconds: 60);

  /// כל כמה זמן לבדוק אם המופע עלה.
  static const Duration _poll = Duration(milliseconds: 600);

  /// ההתקנה שיש לעבוד מולה ומצבה. `null` כשאין אף התקנה שימושית.
  ///
  /// `running` פירושו **יש מופע שאפשר לעבוד מולו** — לא "יש תהליך".
  /// מופע חונה מחוץ למסך נחשב כאן ככבוי, וזו כל הנקודה: הוא מגיב
  /// לפקודות ופותח ספרים, אבל המשתמש אינו רואה דבר. ראו
  /// [ResponsaInstance].
  ///
  /// רץ באיזולט רקע: סריקת הכוננים וספירת החלונות הן קריאות Win32
  /// חוסמות, ועל Windows ה-UI isolate רץ על ה-platform thread.
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

  /// מוודא שיש מופע חי של ההתקנה המבוקשת, ומעלה אותה כש-[allowLaunch].
  ///
  /// "רץ" נמדד מול **ההתקנה הנכונה**, לא מול כל מופע שהוא. על מחשב עם
  /// שתי התקנות, מופע חי של האחת גרם לדלג על ההפעלה של האחרת, ואז
  /// הפעולה נכשלה על התקנה כבויה.
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

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_poll);
      target = await resolve(installPath);
      if (target?.running ?? false) {
        return ResponsaLaunchResult(
          running: true,
          installPath: target!.installPath,
        );
      }
    }
    return ResponsaLaunchResult(
      running: false,
      installPath: target?.installPath,
      message:
          'בר אילן הופעל אך לא עלה בתוך ${timeout.inSeconds} שניות. '
          'יש לפתוח אותו ולנסות שוב.',
    );
  }
}
