import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/startup_timeline.dart';

/// נעילת ההפעלה שמזהה יציאה לא נקייה: נכתבת בעלייה ונמחקת בסגירה מסודרת.
///
/// שולחן הבקרה היחיד של המסלול — העלייה, מסלול הסגירה ומסלול כיבוי המערכת
/// פונים אליו בלבד. הנעילה היא פר-תהליך, ולכן כל חלון שסוגר את התהליך מוחק
/// אותה; המחיקה מוגנת בבדיקת pid בתוך [UncleanExitDetector].
abstract class AppCrashSession {
  /// במובייל אין סגירה מסודרת — מערכת ההפעלה הורגת את התהליך כשהיא רוצה,
  /// וכל הפעלה הייתה נראית כקריסה.
  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// מזהה קריסה של ההפעלה הקודמת ומיד פותח את נעילת ההפעלה הנוכחית.
  /// הסדר קריטי: [UncleanExitDetector.startSession] דורס את הנעילה הקודמת.
  static Future<CrashCandidate?> detectAndStartSession({
    required String version,
    UncleanExitDetector? detector,
  }) async {
    if (!isSupported) return null;
    final active =
        detector ?? UncleanExitDetector(processStartedAt: processStartTime());
    final candidate = await active.detectPreviousCrash();
    await active.startSession(version: version);
    return candidate;
  }

  /// מועמד לתקיעה שהשתחררה בהפעלה הנוכחית, לפי רשומת `App hang` האחרונה.
  static Future<CrashCandidate?> detectRecoveredHang({
    required Duration duration,
    UncleanExitDetector? detector,
  }) async {
    if (!isSupported) return null;
    return (detector ??
            UncleanExitDetector(processStartedAt: processStartTime()))
        .detectRecoveredHang(duration: duration);
  }

  /// תחילת התהליך לפי ציר העלייה, ולא רגע הבדיקה: רשומות שהתהליך הנוכחי
  /// כתב לפני החשיפה (`Slow startup`) אינן ראיה לקריסה של ההפעלה הקודמת.
  @visibleForTesting
  static DateTime processStartTime({
    StartupTimeline? timeline,
    DateTime? now,
  }) {
    final active = timeline ?? StartupTimeline.instance;
    return active.startedAt ??
        (now ?? DateTime.now()).subtract(
          Duration(milliseconds: active.elapsedMs),
        );
  }

  /// מוחק את הנעילה ביציאה מסודרת. סינכרוני — מסלול הסגירה מסתיים ב-`exit(0)`.
  static void markCleanExitSync() {
    if (!isSupported) return;
    UncleanExitDetector().markCleanExitSync();
  }

  /// כותב מחדש נעילה שנמחקה לקראת כיבוי מערכת שבוטל.
  static Future<void> restoreSessionLockIfReleased() async {
    if (!isSupported) return;
    final detector = UncleanExitDetector(processStartedAt: processStartTime());
    if (File(detector.lockPath).existsSync()) return;
    await detector.startSession(version: ErrorLogFile.appVersion);
  }
}
