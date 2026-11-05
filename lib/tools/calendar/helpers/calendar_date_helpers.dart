// lib/tools/calendar/helpers/calendar_date_helpers.dart

import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

export 'package:otzaria/utils/calendar_days.dart';

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

const List<String> kGregorianMonths = [
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

// ═══════════════════════════════════════════════════════════════════════════
//  חישובי תאריך עברי בסיסיים
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
//  עיצוב תאריכים לתצוגה
// ═══════════════════════════════════════════════════════════════════════════

/// ממיר מספר יום עברי לאותיות (ללא גרשיים)
String formatHebrewDay(int number) {
  if (number <= 0) return '';
  String result = '';
  int num = number;
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
String getGregorianMonthName(int month) => kGregorianMonths[month - 1];

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
//  פירוש תאריך קלט
// ═══════════════════════════════════════════════════════════════════════════

/// מנסה לפרש תאריך קלט שהמשתמש הקליד בפורמט עברי או לועזי.
///
/// התומך ב:
/// - לועזי: `15/3/2025`, `15 3 25`, `15.3`, `15-אוגוסט-26`, `15 באוגוסט`
///   (מפריד = כל רצף של רווח / `/` / `.` / `-`; החודש כספרה או כשם, עם/בלי `ב`;
///    השנה בת 2 או 4 ספרות)
/// - עברי: `כ״ה אדר תשפ״ה`, `כ״ה אדר ב תשפ״ה`, `טו תמוז פו`
///
/// עוטף את [parseCalendarDate] עם שנת ההווה. [context] נשמר לתאימות API.
/// מחזיר [DateTime] אם הפירוש הצליח, או `null` אם לא.
DateTime? parseCalendarInputDate(BuildContext context, String input) {
  return parseCalendarDate(
    input,
    currentJewishYear: JewishDate.fromDateTime(DateTime.now()).getJewishYear(),
  );
}

/// גרסה נטולת [BuildContext] של [parseCalendarInputDate] — לשימוש בדיאלוגים
/// שאין להם גישה ל-[CalendarCubit]. [currentJewishYear] משמש להשלמת שנה
/// עברית חסרה, ו-[currentGregorianYear] להשלמת שנה לועזית חסרה.
DateTime? parseCalendarDate(
  String input, {
  required int currentJewishYear,
  int? currentGregorianYear,
}) {
  final tokens = input
      .trim()
      .split(RegExp(r'[\s/.\-]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length < 2 || tokens.length > 4) return null;

  final gregorian = _tryParseGregorianTokens(
    tokens,
    currentGregorianYear ?? DateTime.now().year,
  );
  if (gregorian != null) return gregorian;

  return _tryParseHebrewTokens(tokens, currentJewishYear);
}

/// מפרש חודש לועזי מ-token: ספרה (1-12) או שם חודש (עם/בלי הקידומת `ב`).
int? _gregorianMonthToInt(String token) {
  final asNumber = int.tryParse(token);
  if (asNumber != null) {
    return (asNumber >= 1 && asNumber <= 12) ? asNumber : null;
  }
  var name = token;
  if (name.startsWith('ב') && name.length > 1) name = name.substring(1);
  final idx = kGregorianMonths.indexOf(name);
  return idx == -1 ? null : idx + 1;
}

/// מנרמל שנה בת 2 ספרות ל-4 (26 → 2026).
int _normalizeGregorianYear(int year) => year < 100 ? 2000 + year : year;

DateTime? _tryParseGregorianTokens(List<String> tokens, int currentYear) {
  if (tokens.length < 2 || tokens.length > 3) return null;
  final day = int.tryParse(tokens[0]);
  if (day == null) return null;
  final month = _gregorianMonthToInt(tokens[1]);
  if (month == null) return null;

  int year;
  if (tokens.length == 3) {
    final parsed = int.tryParse(tokens[2]);
    if (parsed == null) return null;
    year = _normalizeGregorianYear(parsed);
  } else {
    year = currentYear;
  }
  if (year < 1900 || year > 2200) return null;

  final date = DateTime(year, month, day);
  final isExact = date.year == year && date.month == month && date.day == day;
  return isExact ? date : null;
}

DateTime? _tryParseHebrewTokens(List<String> tokens, int currentJewishYear) {
  try {
    if (tokens.length < 2 || tokens.length > 4) return null;

    final day = hebrewNumberToInt(tokens[0]);
    String monthName;
    int yearPartIndex;

    if (tokens.length >= 3 &&
        tokens[1] == 'אדר' &&
        (tokens[2] == 'א' ||
            tokens[2] == 'א׳' ||
            tokens[2] == 'ב' ||
            tokens[2] == 'ב׳')) {
      monthName = '${tokens[1]} ${tokens[2]}';
      yearPartIndex = 3;
    } else {
      monthName = tokens[1];
      yearPartIndex = 2;
    }

    final month = hebrewMonthToInt(monthName);
    final int year;
    if (tokens.length > yearPartIndex) {
      year = hebrewYearToInt(
        tokens[yearPartIndex],
        currentJewishYear: currentJewishYear,
      );
    } else {
      year = currentJewishYear;
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
  final cleanHebrew = hebrew
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');
  return gematriaToNumber(cleanHebrew);
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

/// ממיר שנה עברית (אותיות) לספרה.
///
/// שנה מקוצרת ללא מאות (למשל `פו`) מושלמת למאה של [currentJewishYear]
/// (פו → תשפ״ו), אחרת נופלת חזרה לאלף החמישי.
int hebrewYearToInt(String hebrewYear, {int? currentJewishYear}) {
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
  if (baseYear == 0 && yearFromLetters > 0) {
    baseYear = yearFromLetters < 100 && currentJewishYear != null
        ? (currentJewishYear ~/ 100) * 100
        : 5000;
  }
  return baseYear + yearFromLetters;
}
