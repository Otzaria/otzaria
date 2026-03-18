import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

class CalendarTimeEntry {
  final String id;
  final String name;
  final String time;
  final bool isSpecial;

  const CalendarTimeEntry({
    required this.id,
    required this.name,
    required this.time,
    required this.isSpecial,
  });
}

List<CalendarTimeEntry> buildCalendarTimeEntries(CalendarState state) {
  final dailyTimes = state.dailyTimes;
  final entries = <CalendarTimeEntry>[
    CalendarTimeEntry(
      id: 'alos',
      name: 'עלות השחר',
      time: dailyTimes['alos'] ?? '',
      isSpecial: isSpecialTimeName('עלות השחר'),
    ),
    CalendarTimeEntry(
      id: 'alos16point1Degrees',
      name: "עלוה\"ש (72 דק') במע'",
      time: dailyTimes['alos16point1Degrees'] ?? '',
      isSpecial: isSpecialTimeName("עלוה\"ש (72 דק') במע'"),
    ),
    CalendarTimeEntry(
      id: 'alos19point8Degrees',
      name: "עלוה\"ש (90 דק') במע'",
      time: dailyTimes['alos19point8Degrees'] ?? '',
      isSpecial: isSpecialTimeName("עלוה\"ש (90 דק') במע'"),
    ),
    CalendarTimeEntry(
      id: 'sunrise',
      name: 'זריחה',
      time: dailyTimes['sunrise'] ?? '',
      isSpecial: isSpecialTimeName('זריחה'),
    ),
    CalendarTimeEntry(
      id: 'sofZmanShmaMGA',
      name: 'סוף זמן ק"ש - מג"א',
      time: dailyTimes['sofZmanShmaMGA'] ?? '',
      isSpecial: isSpecialTimeName('סוף זמן ק"ש - מג"א'),
    ),
    CalendarTimeEntry(
      id: 'sofZmanTfilaMGA',
      name: 'סוף זמן תפילה - מג"א',
      time: dailyTimes['sofZmanTfilaMGA'] ?? '',
      isSpecial: isSpecialTimeName('סוף זמן תפילה - מג"א'),
    ),
    CalendarTimeEntry(
      id: 'chatzos',
      name: 'חצות היום',
      time: dailyTimes['chatzos'] ?? '',
      isSpecial: isSpecialTimeName('חצות היום'),
    ),
    CalendarTimeEntry(
      id: 'minchaGedola',
      name: 'מנחה גדולה',
      time: dailyTimes['minchaGedola'] ?? '',
      isSpecial: isSpecialTimeName('מנחה גדולה'),
    ),
    CalendarTimeEntry(
      id: 'minchaKetana',
      name: 'מנחה קטנה',
      time: dailyTimes['minchaKetana'] ?? '',
      isSpecial: isSpecialTimeName('מנחה קטנה'),
    ),
    CalendarTimeEntry(
      id: 'plagHaMincha',
      name: 'פלג המנחה',
      time: dailyTimes['plagHaMincha'] ?? '',
      isSpecial: isSpecialTimeName('פלג המנחה'),
    ),
    CalendarTimeEntry(
      id: 'sunset',
      name: 'שקיעה',
      time: dailyTimes['sunset'] ?? '',
      isSpecial: isSpecialTimeName('שקיעה'),
    ),
    CalendarTimeEntry(
      id: 'tzeis',
      name: 'צאת הכוכבים',
      time: dailyTimes['tzeis'] ?? '',
      isSpecial: isSpecialTimeName('צאת הכוכבים'),
    ),
  ];

  final jewishCalendar = JewishCalendar.fromDateTime(
    state.selectedGregorianDate,
  );
  if (jewishCalendar.isChanukah()) {
    final candleLighting = dailyTimes['candleLighting'];
    if (candleLighting != null && candleLighting.isNotEmpty) {
      entries.add(
        CalendarTimeEntry(
          id: 'candleLighting',
          name: 'הדלקת נרות',
          time: candleLighting,
          isSpecial: isSpecialTimeName('הדלקת נרות'),
        ),
      );
    }
  }

  return entries.where((entry) => entry.time.isNotEmpty).toList();
}

bool isSpecialTimeName(String timeName) {
  return timeName.contains('חמץ') ||
      timeName.contains('הדלקת נרות') ||
      timeName.contains('יציאת') ||
      timeName.contains('צאת השבת') ||
      timeName.contains('ספירת העומר') ||
      timeName.contains('תענית') ||
      timeName.contains('חנוכה') ||
      timeName.contains('קידוש לבנה') ||
      timeName.contains('עלוה"ש') ||
      timeName.contains('עלות השחר');
}
