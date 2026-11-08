import 'package:flutter/material.dart';

/// צבעי כפתור פעולה בשורת הכותרת, כמו כפתורי החלון של Windows 11.
///
/// הערכים מחקים את כרום מערכת ההפעלה ולא את ערכת הנושא של האפליקציה
/// (DESIGN_SYSTEM §2.1.3 מקרה 3, DD-24), ולכן הם כאן ב־`lib/core/windowing`
/// ולא ב־`AppSurfaces`.
@immutable
class CaptionButtonColors {
  const CaptionButtonColors._(this.background, this.icon);

  final Color background;
  final Color icon;

  static CaptionButtonColors of({
    required Brightness brightness,
    required bool hovering,
    required bool pressed,
  }) {
    final isDark = brightness == Brightness.dark;
    var background = Colors.transparent;
    var icon = isDark ? Colors.white : Colors.black.withValues(alpha: 0.8956);
    if (hovering) {
      background = isDark
          ? Colors.white.withValues(alpha: 0.0605)
          : Colors.black.withValues(alpha: 0.0373);
    }
    if (pressed) {
      background = isDark
          ? Colors.white.withValues(alpha: 0.0419)
          : Colors.black.withValues(alpha: 0.0241);
      icon = isDark
          ? Colors.white.withValues(alpha: 0.786)
          : Colors.black.withValues(alpha: 0.6063);
    }
    return CaptionButtonColors._(background, icon);
  }
}
