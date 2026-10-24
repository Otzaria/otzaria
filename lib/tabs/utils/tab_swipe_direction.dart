import 'dart:ui';

/// ממירה הצטברות גרירה אופקית (בפיקסלים לוגיים) לכיוון מעבר טאב.
///
/// ב-RTL העמוד הבא (אינדקס גבוה יותר) מונח משמאל לעמוד הנוכחי ב-PageView,
/// ולכן גרירת התוכן ימינה (dx חיובי) חושפת אותו — כלומר מתקדמים טאב.
/// ב-LTR ההפך.
///
/// [accumulatedDx] - סכום רכיבי ה-dx של הגרירה מתחילת המחווה
/// [textDirection] - כיוון הפריסה הנוכחי
/// מחזירה `1` למעבר לטאב הבא או `-1` למעבר לטאב הקודם.
int tabSwipeDirection({
  required double accumulatedDx,
  required TextDirection textDirection,
}) {
  final towardHigherIndex =
      (accumulatedDx > 0) == (textDirection == TextDirection.rtl);
  return towardHigherIndex ? 1 : -1;
}

/// אינדקס הטאב שאליו מעבירה החלקה בודדת, או `null` כשאין לאן לזוז (הטאב
/// הנוכחי הוא הקצה בכיוון ההחלקה). בלי גלישה מהסוף להתחלה — כמו ה-PageView.
int? swipeTargetTabIndex({
  required int currentIndex,
  required int tabCount,
  required double accumulatedDx,
  required TextDirection textDirection,
}) {
  if (accumulatedDx == 0) return null;
  final target =
      currentIndex +
      tabSwipeDirection(
        accumulatedDx: accumulatedDx,
        textDirection: textDirection,
      );
  return target >= 0 && target < tabCount ? target : null;
}
