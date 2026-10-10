import 'dart:async';

/// מודיע על כל כתיבה להערות השמורות של ספר, כדי שתצוגה שמחזיקה עותק משלה
/// (טור מפרש, רשימת מפרשים, חלונית ההערות) תתרענן גם אחרי שינוי שנעשה במקום אחר.
class PersonalNotesChanges {
  PersonalNotesChanges._();

  // לא סינכרוני: המאזינים מקבלים את האירוע אחרי שהכתיבה הסתיימה, ולא בתוך build.
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();

  /// מפתחות הספרים (`personalNotesBookKey`) שהערותיהם השתנו.
  static Stream<String> get stream => _controller.stream;

  static void notify(String bookId) => _controller.add(bookId);
}
