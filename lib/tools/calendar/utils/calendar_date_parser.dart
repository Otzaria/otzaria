import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';

/// מנסה לפרש תאריך קלט שהמשתמש הקליד בפורמט עברי או לועזי.
///
/// התומך ב:
/// - `15/3/2025`
/// - `15-3-2025`
/// - `כ"ה אדר תשפ"ה`
/// - `כ"ה אדר ב תשפ"ה`
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
