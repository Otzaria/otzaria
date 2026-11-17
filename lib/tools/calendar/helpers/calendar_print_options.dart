import 'dart:convert';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

/// כמה זמני יום אפשר לבחור להדפסה בכל תצוגה. בתא חודשי המקום מצומצם (שבעה
/// תאים ברוחב עמוד), בשבוע כל עמוד הוא גובה העמודה, וביום אין הגבלה (`null`).
int? maxPrintedZmanim(CalendarView view) => switch (view) {
  CalendarView.month => 3,
  CalendarView.week => 14,
  CalendarView.day => null,
};

/// הזמנים שמודפסים כשלא נבחר דבר ידנית, לפי התצוגה: בחודש אין זמנים בתאים,
/// בשבוע זריחה ושקיעה, וביום הזמנים שמופעלים בלוח ([dayZmanim]).
Set<String> defaultPrintedZmanim(
  CalendarView view, {
  Set<String> dayZmanim = const {},
}) => switch (view) {
  CalendarView.month => const {},
  CalendarView.week => const {'sunrise', 'sunset'},
  CalendarView.day => dayZmanim,
};

/// הזמנים שהמשתמש בחר להדפיס, והשמירה שלהם.
///
/// `null` = ברירת המחדל של כל תצוגה: בחודש בלי זמנים בתאים, בשבוע זריחה
/// ושקיעה, וביום הזמנים שמוצגים בלוח. סט ריק הוא בחירה אישית בלי זמנים.
/// הבחירה נשמרת מהדפסה להדפסה ונקראת
/// ישירות מההגדרות, כדי שדיאלוג ההדפסה והיוצר של ה-PDF יישארו בלי תלות
/// במצב המסך שנתפס בעת פתיחת הדיאלוג.
abstract final class CalendarPrintZmanimStore {
  static const String key = 'key-calendar-print-zmanim';

  static Set<String>? load() {
    if (!Settings.isInitialized) return null;
    final raw = Settings.getValue<String>(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final ids = decoded.whereType<String>().toSet();
      return ids;
    } catch (_) {
      return null;
    }
  }

  /// שומר את [ids]; רק `null` מחזיר לברירת המחדל.
  static Future<void> save(Set<String>? ids) async {
    if (!Settings.isInitialized) return;
    await Settings.setValue<String>(
      key,
      ids == null ? '' : jsonEncode(ids.toList()..sort()),
    );
  }
}
