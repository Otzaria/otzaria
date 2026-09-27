import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

/// מופע שנסגר נשאר "חונה" ב-`-32000,-32000` לזמן בלתי מוגבל, נראה תקין בכל
/// בדיקת Win32 ואף מגיב - רק [ResponsaWin32.isOnScreen] מבדילה אותו.
class ResponsaInstance {
  /// החלון הראשי.
  final int hwnd;

  final int pid;

  const ResponsaInstance({required this.hwnd, required this.pid});

  /// מחלקת החלון הראשי של פרויקט השו"ת, בכל המהדורות שנבדקו.
  static const String windowClass = 'ResponsaProject';

  bool get visible => ResponsaWin32.isVisible(hwnd);

  bool get onScreen => ResponsaWin32.isOnScreen(hwnd);

  bool get minimized => ResponsaWin32.isMinimized(hwnd);

  /// מופע שהמשתמש רואה, או יראה בלחיצה אחת.
  bool get usable => visible && onScreen;

  /// כמה חלונות ספר פתוחים בו. קריאה חוצת-תהליכים — לא לקרוא בלולאת מיון.
  int get openWindows => ResponsaWin32.mdiTitles(hwnd).length;

  String get title => ResponsaWin32.windowText(hwnd);

  /// כולל חונים: לגילוי התקנה לפי מופע רץ גם חונה מעיד.
  static List<ResponsaInstance> all() => [
    for (final window in ResponsaWin32.topWindowsByClass(windowClass))
      ResponsaInstance(hwnd: window.hwnd, pid: window.pid),
  ];

  /// `null` = אין מופע שמיש (יש להעלות חדש). נבחר הפנוי ביותר, כי מופע שצבר
  /// כ-22 חלונות מפסיק לפתוח חדשים בשקט.
  static ResponsaInstance? pick(Iterable<ResponsaInstance> instances) {
    final all = instances.toList();
    final states = [
      for (final instance in all)
        (
          usable: instance.usable,
          windows: instance.usable ? instance.openWindows : 0,
        ),
    ];
    final parked = states.where((s) => !s.usable).length;
    if (parked > 0) {
      debugPrint(
        'ResponsaInstance: $parked מופעים חונים מחוץ למסך — אינם נבחרים',
      );
    }
    final index = pickIndex(states);
    return index == null ? null : all[index];
  }

  /// בלי נסיגה לחונה: הוא יפתח את הספר "בהצלחה" בלי שהמשתמש יראה דבר, וזה
  /// גרוע מכשל מפורש.
  @visibleForTesting
  static int? pickIndex(List<({bool usable, int windows})> states) {
    int? best;
    for (var index = 0; index < states.length; index++) {
      if (!states[index].usable) continue;
      if (best == null || states[index].windows < states[best].windows) {
        best = index;
      }
    }
    return best;
  }
}
