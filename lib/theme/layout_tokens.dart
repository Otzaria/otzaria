class LayoutBreakpoints {
  static const double compact = 600; // mobile
  static const double medium = 840; // tablet
  static const double expanded = 1200; // desktop
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

  /// רוחב סרגל הצד במסכי לוח בדסקטופ
  static const double panelSidebarWidth = 210.0;
}
