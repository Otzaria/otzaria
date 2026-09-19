import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

/// מופע חי של פרויקט השו"ת, והשאלה אם אפשר לעבוד מולו.
///
/// ## המופע החונה
///
/// כשפרויקט השו"ת נסגר הוא **אינו נעלם מיד**. הוא מעביר את חלונו
/// ל-`-32000,-32000`, סוגר את חלונות ה-MDI שלו אחד-אחד במשך כשבע
/// שניות, והחלון נשאר קיים וניתן למנייה **ללא הגבלת זמן** — נמדד
/// כשלוש דקות אחרי הסגירה, עם אפס חלונות פתוחים.
///
/// מופע כזה נראה תקין בכל בדיקה: `IsWindowVisible` מחזיר `true`,
/// `IsIconic` מחזיר `false`, `GetWindowPlacement` מחזיר `SW_SHOWNORMAL`,
/// ו-`IsHungAppWindow` מחזיר `false`. גרוע מכך — **הוא גם מגיב**: נמדד
/// שדיאלוג העיון נפתח בו במלוא חמשת הפקדים. ספר שנפתח לתוכו נפתח
/// באמת, ואוצריא מדווחת הצלחה, אבל המשתמש אינו רואה דבר.
///
/// הבחירה הקודמת החמירה את זה: היא מיינה לפי מספר חלונות ה-MDI **בסדר
/// עולה**, כדי להעדיף מופע פנוי. למופע חונה יש אפס חלונות, ולכן הוא
/// נבחר **תמיד** — לפני המופע הגלוי שהמשתמש עובד בו.
///
/// [ResponsaWin32.isOnScreen] היא הבדיקה שמבדילה, והיא גם מקבלת מופע
/// ממוזער: הוא של המשתמש, והוא משוחזר בתום הפתיחה.
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

  /// כל המופעים החיים, בלי סינון. כולל חונים — גילוי **התקנה** לפי מופע
  /// רץ עובד גם מול חונה, ושם זה בדיוק מה שרוצים.
  static List<ResponsaInstance> all() => [
    for (final window in ResponsaWin32.topWindowsByClass(windowClass))
      ResponsaInstance(hwnd: window.hwnd, pid: window.pid),
  ];

  /// המופע שיש לעבוד מולו, או `null` כשאין אף אחד שימושי.
  ///
  /// `null` כאן אינו "התוכנה אינה מותקנת" אלא "אין מופע שאפשר לעבוד
  /// מולו" — והמענה הנכון הוא להעלות מופע חדש, לא להיכשל.
  ///
  /// מבין השימושיים נבחר **הפנוי ביותר**: אין single-instance, ומופע
  /// שצבר כ-22 חלונות מפסיק לפתוח חדשים בשקט.
  static ResponsaInstance? pick(Iterable<ResponsaInstance> instances) {
    final all = instances.toList();
    // `openWindows` היא קריאה חוצת-תהליכים לכל חלון MDI, ולכן היא נקראת
    // פעם אחת לכל מופע ולא בתוך לולאת המיון.
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

  /// המדיניות בלבד, בלי Win32 — כדי שתהיה ניתנת לבדיקה.
  ///
  /// `null` כשאין אף מופע שימושי. **לא** נסיגה לחונה: מופע חונה יפתח את
  /// הספר בהצלחה בלי שהמשתמש יראה דבר, וזה גרוע מכשל מפורש.
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
