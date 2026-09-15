import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';

/// המשבצת שתחתיה נשמר מצב **פר-חלון** (סשן כרטיסיות, שולחן פעיל, גבולות).
abstract final class UserStateSlot {
  /// המשבצת של החלון היחיד בפלטפורמה שאין בה אפיק חלונות.
  static const int single = 1;

  /// המשבצת של החלון הזה, או null כשאין לו — ואז אין לו לאן לשמור.
  ///
  /// ⚠️ בלי אפיק (מובייל, פלטפורמה ללא ריבוי חלונות) החלון היחיד הוא
  /// [single]. עם אפיק ובלי משבצת (כולן תפוסות) — null, ולא נפילה
  /// למשבצת של חלון אחר: זו הייתה דורסת את הסשן שלו.
  static int? get current {
    final slot = WindowBus.instance.slot;
    if (slot != null) return slot;
    return MultiWindowService.canOpenWindows ? null : single;
  }
}
