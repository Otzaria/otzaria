import 'package:flutter/material.dart';

/// רקעי מסך לסביבות שימוש שונות באפליקציה
///
/// משמש ליצירת עקביות ויזואלית בין מסכי "לוח" (panel screens):
/// הגדרות, ספריה, כלים — בניגוד למסך העיון (המסך הראשי).
class AppSurfaces {
  AppSurfaces._();

  /// נקודת ה-override היחידה לרקע מסך העיון (טקסט, PDF, חיפוש).
  ///
  /// כל רכיבי העיון — ה-Scaffold, ה-CustomTitleBar, ה-PdfViewer ופס
  /// הגלילה — מסתמכים על פונקציה זו. כדי לשנות ערכת נושא, מספיק לשנות
  /// את ערך החזרה כאן; שאר הקוד מתעדכן אוטומטית.
  static Color readerBackground(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  /// רקע מסכי לוח — הגדרות, ספריה, כלים וכל מסך משני
  ///
  /// מחזיר:
  /// - מצב כהה: שחור מוחלט (כרטיסי SettingsCard בולטים מעליו)
  /// - מצב בהיר: surfaceContainerHighest בשקיפות 48% (טון עדין מעל הרקע הלבן)
  ///
  /// **שימוש:**
  /// ```dart
  /// Scaffold(
  ///   backgroundColor: AppSurfaces.panelBackground(context),
  ///   ...
  /// )
  /// ```
  static Color panelBackground(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (theme.brightness == Brightness.dark) return Colors.black;
    return Color.alphaBlend(
      cs.surfaceContainerHighest.withValues(alpha: 0.475),
      cs.surface,
    );
  }

  /// זהה ל-[panelBackground] — נשמר לתאימות עם קוד קיים.
  static Color solidPanelBackground(BuildContext context) =>
      panelBackground(context);

  /// צבע ברירת המחדל לכרטיסי תוכן באפליקציה.
  ///
  /// תואם לכרטיסי הגדרות ולכרטיסי תוצאות בכלים:
  /// - מצב כהה: [ColorScheme.surfaceContainer]
  /// - מצב בהיר: [ColorScheme.surface]
  static Color card(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainer
        : theme.colorScheme.surface;
  }

  /// רקע פריט נבחר ברשימת ניווט (TOC, מפרשים וכד').
  ///
  /// 30% primaryContainer — מספק הדגשה עדינה שמסמנת בחירה
  /// מבלי לכבות את הנוסח על גביה.
  static Color selectedItem(ColorScheme cs) =>
      cs.primaryContainer.withValues(alpha: 0.3);

  /// רקע הדגשה לשורה שמעליה מרחפים בגרירה (drag target).
  ///
  /// 8% primary — רמז עדין למקום השחרור מבלי להסתיר את תוכן השורה.
  static Color dragTargetHighlight(ColorScheme cs) =>
      cs.primary.withValues(alpha: 0.08);

  /// רקע רצועת [PanelOpenHandle] — מתפוגג מעט במצב רגיל, אטום יותר ב-hover.
  static Color panelOpenHandle(ColorScheme cs, {required bool isHovering}) =>
      cs.surfaceContainerHighest.withValues(alpha: isHovering ? 0.95 : 0.8);

  /// overlayColor ל-TabBar שמצייר hover מותאם אישית (foregroundPainter)
  /// ולכן רוצה לבטל את ה-hover/focus הגלובלי של [TabBarTheme].
  static final WidgetStateProperty<Color?> tabBarNoOverlay =
      WidgetStateProperty.all(Colors.transparent);
}
