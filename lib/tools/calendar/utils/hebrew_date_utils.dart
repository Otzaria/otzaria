import 'package:kosher_dart/kosher_dart.dart';

/// מחזיר את הדף היומי (בבלי) לתאריך נתון
Daf getDafYomi(DateTime date) {
  JewishCalendar jewishCalendar = JewishCalendar.fromDateTime(date);
  return YomiCalculator.getDafYomiBavli(jewishCalendar);
}

/// מחזיר תאריך עברי מפורמט כמחרוזת
String getHebrewDateFormattedAsString(DateTime dateTime) {
  final hebrewCalendar = JewishCalendar.fromDateTime(dateTime);
  HebrewDateFormatter hebrewDateFormatter = HebrewDateFormatter()
    ..hebrewFormat = true;
  return hebrewDateFormatter.format(hebrewCalendar);
}

/// מחזיר חותמת זמן עברית (תאריך + שעה)
String getHebrewTimeStamp() {
  return '${getHebrewDateFormattedAsString(DateTime.now())} ${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second}';
}

/// מעצב מספר עמוד לאותיות עבריות ללא גרשיים
String formatAmud(int amud) {
  return HebrewDateFormatter()
      .formatHebrewNumber(amud)
      .replaceAll('״', '')
      .replaceAll('׳', '');
}
