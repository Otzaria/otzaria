import 'package:flutter/widgets.dart';

/// מידות עיצוב קבועות של התפריט שאינן תלויות במצב הקומפקטי (ולכן לא ב-
/// [AppMenuMetrics]).
///
/// החבילה עצמאית ואינה תלויה בטוקנים של האפליקציה, ולכן הערכים כאן ממשיכים
/// את הערכים שהיו כתובים בקוד, בלי שינוי חזותי. כללי ui_lint (UIL-017/019/020/
/// 023/029/030) אוסרים ליטרלים בבנאים: כל מידה נקראת בשם ומוגדרת פעם אחת.
abstract final class AppMenuVisuals {
  /// צל הפאנל, כשהמארח לא קבע `MenuStyle.elevation`.
  static const double panelElevation = 3;

  /// גודל האייקון ברירת המחדל של [AppMenuMetrics.create].
  static const double iconSize = 18;

  static const double _highlightedRowMarginHorizontal = 6;
  static const double _highlightedRowMarginVertical = 3;
  static const double _highlightedRowPaddingHorizontal = 14;

  /// שורה מודגשת (פריט עם מסגרת בצבע ראשי): ריפוד חיצוני סביב הפריט.
  static const EdgeInsets highlightedRowMargin = EdgeInsets.symmetric(
    horizontal: _highlightedRowMarginHorizontal,
    vertical: _highlightedRowMarginVertical,
  );

  /// שורה מודגשת: ריפוד פנימי אופקי.
  static const EdgeInsets highlightedRowPadding = EdgeInsets.symmetric(
    horizontal: _highlightedRowPaddingHorizontal,
  );

  /// שורה מודגשת: רווח בין התווית לאייקון.
  static const double highlightedRowIconGap = 6;

  /// שורת צבעים: רדיוס אזור הלחיצה של דגימה, רדיוס הדגימה עצמה והאנימציה של
  /// מסגרת הבחירה.
  static const double swatchTapRadius = 6;
  static const double swatchRadius = 5;
  static const Duration swatchAnimation = Duration(milliseconds: 120);

  /// שורת אייקונים: גודל תווית הכפתור ורדיוס אזור הלחיצה שלו.
  static const double iconRowLabelFontSize = 11;
  static const double iconRowButtonRadius = 8;
}
