import 'package:flutter/foundation.dart' show ValueNotifier;

/// תור פעולות הכתיבה לספרים האישיים עם ספירה נצפית של העבודה הממתינה.
/// מופע התור של ספק הספרייה משותף למסכים ושורד את פירוקם.
class PersonalBooksOperationQueue {
  Future<void> _tail = Future.value();

  /// מספר הפעולות הממתינות או הרצות כרגע.
  /// הספירה עולה כבר בהוספה כדי שמצב העסוק ישקף גם פעולות ממתינות.
  final ValueNotifier<int> busyCount = ValueNotifier(0);

  bool get isBusy => busyCount.value > 0;

  /// מוסיף [operation] לתור הסריאלי ומחזיר את תוצאתה.
  ///
  /// פעולות מבוצעות בסדר הוספה בלבד, לעולם לא במקביל.
  Future<T> enqueue<T>(Future<T> Function() operation) {
    busyCount.value++;
    final result = _tail.then<T>((_) async {
      try {
        return await operation();
      } finally {
        busyCount.value--;
      }
    });
    // _tail לעולם לא נדחית; אחרת שרשרת ה-then תיקלע לדד-לוק.
    _tail = result.then<void>((_) {}).catchError((_) {});
    return result;
  }
}
