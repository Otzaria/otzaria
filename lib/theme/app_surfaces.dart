import 'package:flutter/material.dart';

ColorScheme _cs(BuildContext context) => Theme.of(context).colorScheme;

extension on ColorScheme {
  bool get isDark => brightness == Brightness.dark;
}

/// רקעי מסך לסביבות שימוש שונות באפליקציה
/// כשיש הבדל בין מצב בהיר לכהה, כתוב isDark ומצב כהה מסומן עם ? סימן שאלה.
class AppSurfaces {
  AppSurfaces._();

  /// נקודת ה-override היחידה לרקע מסך העיון (טקסט, PDF, חיפוש).
  /// הכנה לערכות נושא עתידיות שייתכן וירצו להפריד בין רקע מסך עיון לרקע מסכי לוח.
  static Color readerBackground(BuildContext context) =>
      _cs(context).surface;

  /// רקע מסכי לוח — הגדרות, ספריה, כלים וכל מסך משני
  ///
  static Color panelBackground(BuildContext context) {
    final cs = _cs(context);
    return cs.isDark
        ? Colors.black
        : Color.alphaBlend(cs.surfaceContainerHighest.withValues(alpha: 0.475), cs.surface);
  }

  /// נקודת ה-override לרקע מסכי לוח — הכנה לערכות נושא עתידיות.
  static Color solidPanelBackground(BuildContext context) => panelBackground(context);

  /// צבע ברירת המחדל לכרטיסי תוכן באפליקציה.
  static Color card(BuildContext context) =>
      _cs(context).isDark ? _cs(context).surfaceContainer : _cs(context).surface;

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
