import 'dart:math';

import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/utils/jewish_month_navigation.dart';

/// מזיזה תאריך לועזי לחודש הבא או הקודם תוך שמירה על אותו יום אם אפשר.
///
/// אם היום המבוקש לא קיים בחודש היעד, הפונקציה מחזירה את היום האחרון
/// הזמין באותו חודש.
DateTime shiftGregorianMonthPreservingDay(
  DateTime current, {
  required bool forward,
}) {
  final targetYear = forward
      ? (current.month == 12 ? current.year + 1 : current.year)
      : (current.month == 1 ? current.year - 1 : current.year);
  final targetMonth = forward
      ? (current.month == 12 ? 1 : current.month + 1)
      : (current.month == 1 ? 12 : current.month - 1);
  final targetDaysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;
  final targetDay = min(current.day, targetDaysInMonth);
  return DateTime(targetYear, targetMonth, targetDay);
}

/// מזיזה תאריך עברי לחודש הבא או הקודם תוך שמירה על אותו יום אם אפשר.
///
/// אם היום המבוקש לא קיים בחודש היעד, הפונקציה מחזירה את היום האחרון
/// הזמין באותו חודש.
JewishDate shiftJewishMonthPreservingDay(
  JewishDate current, {
  required bool forward,
}) {
  final target = forward
      ? computeNextJewishMonth(current)
      : computePreviousJewishMonth(current);
  final targetYear = target.getJewishYear();
  final targetMonth = target.getJewishMonth();
  final targetDate = JewishDate()..setJewishDate(targetYear, targetMonth, 1);
  final targetDaysInMonth = targetDate.getDaysInJewishMonth();
  final targetDay = min(current.getJewishDayOfMonth(), targetDaysInMonth);
  target.setJewishDate(targetYear, targetMonth, targetDay);
  return target;
}
