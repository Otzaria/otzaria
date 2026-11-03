import 'package:flutter/widgets.dart';

class LayoutBreakpoints {
  static const double compact = 600; // mobile
  static const double medium = 840; // tablet
  static const double expanded = 1200; // desktop
}

/// סוג החלון לפי רוחבו, להחלטות ברמת החלון בלבד: דיאלוג צר מול רחב, ניווט,
/// מספר עמודות במסך. רכיב שיכול לשבת בחלונית צרה מחליט לפי `LayoutBuilder`
/// וקבוע עם שם, לא לפי החלון.
enum WindowClass {
  compact,
  medium,
  expanded,
  large;

  static WindowClass fromWidth(double width) {
    if (width < LayoutBreakpoints.compact) return compact;
    if (width < LayoutBreakpoints.medium) return medium;
    if (width < LayoutBreakpoints.expanded) return expanded;
    return large;
  }

  static WindowClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  /// מתחת ל-[LayoutBreakpoints.compact]: טלפון או חלון צר במחשב.
  bool get isCompact => this == compact;
}

class LayoutPadding {
  static const double compact = 16;
  static const double medium = 24;
  static const double expanded = 32;
}

/// קבועי מידות לפריסת ממשק
class LayoutConstraints {
  LayoutConstraints._();

  /// רוחב מקסימלי לתוכן בתוך מסכי לוח (הגדרות, ספריה, כלים)
  /// מאפשר מרכוז תוכן על מסכים רחבים מאוד
  static const double panelContentMaxWidth = 860.0;

  /// רוחב ברירת המחדל של חלונית צד (DD-28).
  static const double sidePaneWidth = 340.0;

  /// רוחב מינימלי של התוכן הראשי לצד חלונית צד.
  static const double mainContentMinWidth = 500.0;

  /// הרוחב המינימלי להצגת חלונית צד ותוכן ראשי זה לצד זה.
  static const double sideBySideMinWidth = sidePaneWidth + mainContentMinWidth;

  /// גובה שורת הכותרת של החלון בדסקטופ: הכרטיסיות וכפתורי החלון.
  static const double windowCaptionHeight = 40.0;
}
