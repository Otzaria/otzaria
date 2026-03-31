import 'package:kosher_dart/kosher_dart.dart';

/// מחשב את החודש העברי הבא תוך שמירה על לוגיקת שנה מעוברת
/// מעבר שנה מתרחש רק במעבר אלול (6) → תשרי (7)
JewishDate computeNextJewishMonth(JewishDate current) {
  final y = current.getJewishYear();
  final m = current.getJewishMonth();
  final leap = current.isJewishLeapYear();
  final JewishDate next = JewishDate();

  if (m == 6) {
    // אלול → תשרי, שנה עולה
    next.setJewishDate(y + 1, 7, 1);
  } else if (leap && m == 12) {
    // אדר א → אדר ב (אותה שנה)
    next.setJewishDate(y, 13, 1);
  } else if ((!leap && m == 12) || m == 13) {
    // אדר (שאינה מעוברת) או אדר ב (מעוברת) → ניסן (אותה שנה)
    next.setJewishDate(y, 1, 1);
  } else {
    next.setJewishDate(y, m + 1, 1);
  }
  return next;
}

/// מחשב את החודש העברי הקודם תוך שמירה על לוגיקת שנה מעוברת
/// מעבר שנה מתרחש רק במעבר תשרי (7) → אלול (6)
JewishDate computePreviousJewishMonth(JewishDate current) {
  final y = current.getJewishYear();
  final m = current.getJewishMonth();
  final leap = current.isJewishLeapYear();
  final JewishDate prev = JewishDate();

  if (m == 7) {
    // תשרי → אלול, שנה יורדת
    prev.setJewishDate(y - 1, 6, 1);
  } else if (leap && m == 13) {
    // אדר ב → אדר א (אותה שנה)
    prev.setJewishDate(y, 12, 1);
  } else if (m == 1) {
    // ניסן → אדר (לפי מעוברת)
    final lastMonthThisYear = leap ? 13 : 12;
    prev.setJewishDate(y, lastMonthThisYear, 1);
  } else {
    prev.setJewishDate(y, m - 1, 1);
  }
  return prev;
}
