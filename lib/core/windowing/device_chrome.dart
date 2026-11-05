import 'dart:io';

import 'package:flutter/foundation.dart';

/// איזה כרום המכשיר צריך: חלון מחשב עם כפתורי חלון בשורת הכותרת, או מכשיר
/// נייד שאין בו חלון.
///
/// הבדיקה לפי `dart:io` ולא לפי `defaultTargetPlatform`, כמו שהייתה בשורת
/// הכותרת: ב-flutter_test הפלטפורמה ברירת המחדל היא Android, אבל המארח הוא
/// Windows, והבדיקות של כפתורי החלון מניחות מחשב.
class DeviceChrome {
  DeviceChrome._();

  /// בבדיקות: `true` מדמה טלפון (בלי כפתורי חלון), `false` מדמה מחשב.
  @visibleForTesting
  static bool? debugMobileOverride;

  /// טלפון או טאבלט (Android/iOS).
  static bool get isMobile =>
      debugMobileOverride ??
      (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// חלון מחשב (Windows/Linux/macOS), שבשורת הכותרת שלו כפתורי חלון.
  static bool get hasWindowCaption {
    final override = debugMobileOverride;
    if (override != null) return !override;
    return !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  }
}
