import 'package:flutter/widgets.dart';

class LayoutBreakpoints {
  static const double compact = 600; // mobile
  static const double medium = 840; // tablet
  static const double expanded = 1200; // desktop

  /// גובה חלון "נמוך" (compact height של M3): טלפון לרוחב, או חלון שטוח
  /// במחשב. מתחתיו הגובה הוא האילוץ, ולא הרוחב (q12 Q8).
  static const double compactHeight = 480;
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

  /// חלון נמוך: גובהו מתחת ל-[LayoutBreakpoints.compactHeight] (טלפון
  /// לרוחב). שם הכרום מצטמצם: צפיפות קומפקטית, וסרגל אחד ולא שניים.
  static bool isShortOf(BuildContext context) =>
      MediaQuery.sizeOf(context).height < LayoutBreakpoints.compactHeight;

  /// ניווט בעמודה שבצד, וכרטיסיות בשורת הכותרת ולא בשורה שנייה: בכל חלון
  /// שאינו צר, וגם בחלון צר ונמוך (טלפון קטן לרוחב, 568×320), כי שם סרגל
  /// תחתון ושורת כרטיסיות שנייה היו לוקחים יותר ממחצית הגובה.
  static bool usesSideNavigationOf(BuildContext context) =>
      !of(context).isCompact || isShortOf(context);
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

  /// גובה סרגל הניווט התחתון (טלפון לאורך): 64, כמו "flexible navigation
  /// bar" של M3 Expressive, עם תווית לכל יעד. ברירת המחדל של M3 הייתה 80
  /// (q12 Q8, ss6).
  static const double bottomNavigationBarHeight = 64.0;
}
