// lib/tools/calendar/helpers/calendar_date_helpers.dart
//
// איחוד של שלושה קבצים:
//   • utils/calendar_date_parser.dart   — פירוש תאריך קלט
//   • utils/hebrew_date_utils.dart      — חישובי תאריך עברי בסיסיים
//   • view/widgets/calendar_date_formatters.dart — עיצוב תאריכים לתצוגה
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  קבועים
// ═══════════════════════════════════════════════════════════════════════════

const List<String> kHebrewMonths = [
  'ניסן',
  'אייר',
  'סיון',
  'תמוז',
  'אב',
  'אלול',
  'תשרי',
  'חשון',
  'כסלו',
  'טבת',
  'שבט',
  'אדר',
];

const List<String> kHebrewDays = [
  'ראשון',
  'שני',
  'שלישי',
  'רביעי',
  'חמישי',
  'שישי',
  'שבת',
];

// ═══════════════════════════════════════════════════════════════════════════
//  מ-hebrew_date_utils.dart
// ═══════════════════════════════════════════════════════════════════════════

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
  final now = DateTime.now();
  return '${getHebrewDateFormattedAsString(now)} ${now.hour}:${now.minute}:${now.second}';
}

/// מעצב מספר עמוד לאותיות עבריות ללא גרשיים
String formatAmud(int amud) {
  return HebrewDateFormatter()
      .formatHebrewNumber(amud)
      .replaceAll('״', '')
      .replaceAll('׳', '');
}

// ═══════════════════════════════════════════════════════════════════════════
//  מ-calendar_date_formatters.dart
// ═══════════════════════════════════════════════════════════════════════════

/// ממיר מספר יום עברי לאותיות (ללא גרשיים)
String formatHebrewDay(int day) => numberToHebrewWithoutQuotes(day);

/// ממיר מספר לאותיות עבריות ללא גרשיים
String numberToHebrewWithoutQuotes(int number) {
  if (number <= 0) return '';
  String result = '';
  int num = number;
  if (num >= 100) {
    int hundreds = (num ~/ 100) * 100;
    const hundredsMap = {
      900: 'תתק',
      800: 'תת',
      700: 'תש',
      600: 'תר',
      500: 'תק',
      400: 'ת',
      300: 'ש',
      200: 'ר',
      100: 'ק',
    };
    result += hundredsMap[hundreds] ?? '';
    num %= 100;
  }
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  if (num == 15) {
    result += 'טו';
  } else if (num == 16) {
    result += 'טז';
  } else {
    if (num >= 10) {
      result += tens[num ~/ 10];
      num %= 10;
    }
    if (num > 0) result += ones[num];
  }
  return result;
}

/// מחזיר שם החודש העברי (כולל אדר א/ב בשנה מעוברת)
String getHebrewMonthNameFor(JewishDate jewishDate) {
  final int m = jewishDate.getJewishMonth();
  final bool leap = jewishDate.isJewishLeapYear();
  if (leap && m == 12) return 'אדר א׳';
  if (leap && m == 13) return 'אדר ב׳';
  final int idx = (m - 1).clamp(0, kHebrewMonths.length - 1);
  return kHebrewMonths[idx];
}

/// מחזיר שם חודש לועזי
String getGregorianMonthName(int month) {
  const months = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];
  return months[month - 1];
}

/// מעצב שנה עברית בפורמט ה׳תשפ״ה
String formatHebrewYear(int year) {
  final hdf = HebrewDateFormatter()..hebrewFormat = true;
  final thousands = year ~/ 1000;
  final remainder = year % 1000;
  String remainderStr = hdf
      .formatHebrewNumber(remainder)
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('׳', '')
      .replaceAll('״', '');

  String formattedRemainder;
  if (remainderStr.length > 1) {
    formattedRemainder =
        '${remainderStr.substring(0, remainderStr.length - 1)}״${remainderStr.substring(remainderStr.length - 1)}';
  } else if (remainderStr.length == 1) {
    formattedRemainder = '$remainderStr׳';
  } else {
    formattedRemainder = remainderStr;
  }
  return thousands == 5 ? 'ה׳$formattedRemainder' : formattedRemainder;
}

/// מחזיר כותרת חודש/שנה לפי מצב הלוח
String getCurrentMonthYearText(CalendarState state) {
  final DateTime gregorianDate;
  final JewishDate jewishDate;
  if (state.calendarView == CalendarView.month) {
    gregorianDate = state.currentGregorianDate;
    jewishDate = state.currentJewishDate;
  } else {
    gregorianDate = state.selectedGregorianDate;
    jewishDate = state.selectedJewishDate;
  }
  final gregName = getGregorianMonthName(gregorianDate.month);
  final gregNum = gregorianDate.month;
  final hebName = getHebrewMonthNameFor(jewishDate);
  final hebYear = formatHebrewYear(jewishDate.getJewishYear());
  return '$hebName $hebYear • $gregName ($gregNum) ${gregorianDate.year}';
}

/// מחזיר תיאור מקוצר לתאריך אירוע (עברי + לועזי)
String formatEventDate(DateTime date) {
  final jewishDate = JewishDate.fromDateTime(date);
  final hebrewStr =
      '${formatHebrewDay(jewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(jewishDate)}';
  final gregorianStr =
      '${date.day} ${getGregorianMonthName(date.month)} ${date.year}';
  return '$hebrewStr • $gregorianStr';
}

/// מחרוזת לתצוגה של סוג חזרה
String getRecurrenceLabel(RecurrenceType type) {
  switch (type) {
    case RecurrenceType.weekly:
      return 'חוזר שבועי';
    case RecurrenceType.monthlyHebrew:
      return 'חוזר חודשי (עברי)';
    case RecurrenceType.monthlyGregorian:
      return 'חוזר חודשי (לועזי)';
    case RecurrenceType.annualHebrew:
      return 'חוזר שנתי (עברי)';
    case RecurrenceType.annualGregorian:
      return 'חוזר שנתי (לועזי)';
    case RecurrenceType.none:
      return '';
  }
}

/// קיצור תיאור
String truncateDescription(String description) {
  const int maxLength = 50;
  if (description.length <= maxLength) return description;
  return '${description.substring(0, maxLength)}...';
}

// ═══════════════════════════════════════════════════════════════════════════
//  מ-calendar_date_parser.dart  (+ תלות ב-formatters)
// ═══════════════════════════════════════════════════════════════════════════

/// מנסה לפרש תאריך קלט שהמשתמש הקליד בפורמט עברי או לועזי.
///
/// התומך ב:
/// - `15/3/2025` / `15-3-2025`
/// - `כ״ה אדר תשפ״ה`
/// - `כ״ה אדר ב תשפ״ה`
///
/// מחזיר [DateTime] אם הפירוש הצליח, או `null` אם לא.
DateTime? parseCalendarInputDate(BuildContext context, String input) {
  final cleanInput = input.trim();
  final gregorianPattern = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})$');
  final match = gregorianPattern.firstMatch(cleanInput);
  if (match != null) {
    try {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      if (year >= 1900 && year <= 2200) {
        return DateTime(year, month, day);
      }
    } catch (_) {}
  }

  try {
    final parts = cleanInput.split(RegExp(r'\s+'));
    if (parts.length < 2 || parts.length > 4) return null;

    final day = hebrewNumberToInt(parts[0]);
    String monthName;
    int yearPartIndex;

    if (parts.length >= 3 &&
        parts[1] == 'אדר' &&
        (parts[2] == 'א' ||
            parts[2] == 'א׳' ||
            parts[2] == 'ב' ||
            parts[2] == 'ב׳')) {
      monthName = '${parts[1]} ${parts[2]}';
      yearPartIndex = 3;
    } else {
      monthName = parts[1];
      yearPartIndex = 2;
    }

    final month = hebrewMonthToInt(monthName);
    final int year;
    if (parts.length > yearPartIndex) {
      year = hebrewYearToInt(parts[yearPartIndex]);
    } else {
      year =
          context.read<CalendarCubit>().state.currentJewishDate.getJewishYear();
    }

    if (day > 0 && month > 0 && year > 5000) {
      final jewishDate = JewishDate()..setJewishDate(year, month, day);
      return jewishDate.getGregorianCalendar();
    }
  } catch (_) {}

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  פונקציות עזר לפירוש תאריך עברי
// ─────────────────────────────────────────────────────────────────────────────

/// ממיר אות עברית למספר (לפענוח תאריך עברי שהוקלד)
int hebrewNumberToInt(String hebrew) {
  const hebrewValue = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ל': 30,
    'מ': 40,
    'נ': 50,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'צ': 90,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };
  final cleanHebrew = hebrew
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  if (cleanHebrew == 'טו') return 15;
  if (cleanHebrew == 'טז') return 16;
  int sum = 0;
  for (int i = 0; i < cleanHebrew.length; i++) {
    sum += hebrewValue[cleanHebrew[i]] ?? 0;
  }
  return sum;
}

/// ממיר שם חודש עברי לספרה
int hebrewMonthToInt(String monthName) {
  final clean = monthName.trim();
  if (clean == 'אדר א' || clean == 'אדר א׳' || clean == 'אדר 1') return 12;
  if (clean == 'אדר ב' || clean == 'אדר ב׳' || clean == 'אדר 2') return 13;
  final idx = kHebrewMonths.indexOf(clean);
  if (idx != -1) return idx + 1;
  if (clean == 'חשוון' || clean == 'מרחשוון') return 8;
  if (clean == 'סיוון') return 3;
  throw Exception('Invalid month name: $clean');
}

/// ממיר שנה עברית (אותיות) לספרה
int hebrewYearToInt(String hebrewYear) {
  String clean = hebrewYear
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  int baseYear = 0;
  if (clean.startsWith('ה')) {
    baseYear = 5000;
    clean = clean.substring(1);
  }
  final yearFromLetters = hebrewNumberToInt(clean);
  if (baseYear == 0 && yearFromLetters > 0) baseYear = 5000;
  return baseYear + yearFromLetters;
}
