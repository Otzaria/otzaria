import 'package:kosher_dart/kosher_dart.dart';
import 'package:timezone/timezone.dart' as tz;

/// מחזיר את סימן השניות: נקודה (`.`) כשהשניות
/// 0–29, נקודותיים (`:`) כשהן 30–59. הסימן מציין לקורא אם הזמן האמיתי
/// נופל במחצית הראשונה או השנייה של הדקה (הזמן עצמו אינו מעוגל).
String secondsMarker(DateTime dt) => dt.second < 30 ? '.' : ':';

/// תווי בידי לעטיפת השעה כיחידת LTR: LEFT-TO-RIGHT ISOLATE ו-POP.
/// בלעדיהם סימן השניות (תו ניטרלי) נדחף משמאל למספרים בהקשר RTL, כי
/// ספרות נחשבות לכיוון ימני בפתרון תווים ניטרליים. העטיפה מקבעת את סדר
/// המקטע כ-LTR ומשאירה את הסימן צמוד מימין למספרים.
const String _ltrIsolateStart = '\u2066';
const String _ltrIsolateEnd = '\u2069';

/// מעצב שעה לפורמט HH:MM עם תמיכה ב-timezone, ובסופו סימן שניות
/// ([secondsMarker]). הזמן נחתך לדקה ואינו מעוגל,
/// והמקטע עטוף ב-LTR isolate לתצוגה תקינה ב-RTL.
String formatZmanTime(DateTime dt, tz.Location tzLocation) {
  final tzDateTime = tz.TZDateTime.from(dt, tzLocation);
  final hh = tzDateTime.hour.toString().padLeft(2, '0');
  final mm = tzDateTime.minute.toString().padLeft(2, '0');
  return '$_ltrIsolateStart$hh:$mm${secondsMarker(tzDateTime)}$_ltrIsolateEnd';
}

final RegExp _isolatedClockTimePattern = RegExp(
  '$_ltrIsolateStart(\\d{1,2}):(\\d{2})([.:]?)$_ltrIsolateEnd',
);

// LRM ורווח קשיח: כרטיסים זוגיים מפצלים כותרת מערך ברווח האחרון, וגוף
// ההתראה מוצג בלי ה-isolate, ובלי ה-LRM ה-AM היה מתהפך לפני השעה.
const String _periodSeparator = '‎ ';

/// מחזיר את [text] לתצוגה, ובשעון 12 שעות ממיר כל שעה שעיצבה
/// [formatZmanTime] ל-h:mm עם AM/PM. הנתונים עצמם נשארים ב-24 שעות למיון ולהתראות.
String zmanTimeForDisplay(String text, {required bool twelveHourClock}) {
  if (!twelveHourClock) return text;
  return text.replaceAllMapped(_isolatedClockTimePattern, (match) {
    final hour = int.parse(match[1]!);
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour < 12 ? 'AM' : 'PM';
    return '$_ltrIsolateStart$hour12:${match[2]}${match[3]}'
        '$_periodSeparator$period$_ltrIsolateEnd';
  });
}

// תומך בעטיפת ה-LTR isolate ובסימן השניות האופציונלי (`.`/`:`).
final RegExp _clockTimePattern = RegExp(
  '^$_ltrIsolateStart?'
  r'\d{1,2}:\d{2}[.:]?'
  '$_ltrIsolateEnd?\$',
);

/// בודק אם מחרוזת זמן היא שעת-שעון (HH:MM) — שעבורה מיון לקסיקוגרפי שקול
/// למיון כרונולוגי. זמני קידוש לבנה מוצגים כתאריך עברי ("ליל ... HH:MM")
/// ואינם ברי-מיון כרונולוגי לפי מחרוזת התצוגה.
bool isClockTime(String time) => _clockTimePattern.hasMatch(time);

const List<String> _hebrewNightNames = [
  '',
  'ליל ראשון',
  'ליל שני',
  'ליל שלישי',
  'ליל רביעי',
  'ליל חמישי',
  'ליל שישי',
  'ליל שבת',
];

/// מעצב תאריך עברי לילי לתצוגה: "ליל <שבוע> <יום-חודש> לחודש HH:MM".
/// [advanceToNextDay] מקדם את היום העברי (כשהרגע חל אחרי השקיעה).
String formatHebrewNightLabel(
  DateTime moment, {
  required bool advanceToNextDay,
}) {
  final hour = moment.hour.toString().padLeft(2, '0');
  final minute = moment.minute.toString().padLeft(2, '0');
  final time =
      '$_ltrIsolateStart$hour:$minute${secondsMarker(moment)}$_ltrIsolateEnd';
  final jewishDate = JewishDate.fromDateTime(
    DateTime(moment.year, moment.month, moment.day),
  );
  if (advanceToNextDay) jewishDate.forward();
  final formatter = HebrewDateFormatter()..hebrewFormat = true;
  final dayOfMonth = formatter.formatHebrewNumber(
    jewishDate.getJewishDayOfMonth(),
  );
  final dayOfWeek = jewishDate.getDayOfWeek();
  final nightName = (dayOfWeek >= 1 && dayOfWeek <= 7)
      ? _hebrewNightNames[dayOfWeek]
      : '';
  return '$nightName $dayOfMonth לחודש $time';
}
