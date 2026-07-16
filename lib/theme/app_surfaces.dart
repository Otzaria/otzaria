import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_colors.dart';

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
      _cs(context).isDark ? AppColors.darkScaffold : _cs(context).surface;

  /// רקע מסכי לוח — הגדרות, ספריה, כלים וכל מסך משני
  static Color panelBackground(BuildContext context) {
    final cs = _cs(context);
    return cs.isDark
        ? Colors.black
        : Color.alphaBlend(
            cs.surfaceContainerHighest.withValues(alpha: 0.475), cs.surface);
  }

  /// נקודת ה-override לרקע מסכי לוח — הכנה לערכות נושא עתידיות.
  static Color solidPanelBackground(BuildContext context) =>
      panelBackground(context);

  /// רקע סרגל עליון (AppTopBar) — נקודת ה-override היחידה לצבע הסרגל.
  static Color topBarBackground(BuildContext context) =>
      _cs(context).surfaceContainerHigh;

  /// צבע ברירת המחדל לכרטיסי תוכן באפליקציה.
  static Color card(BuildContext context) => _cs(context).isDark
      ? _cs(context).surfaceContainer
      : _cs(context).surface;

  /// צבע מפריד פנימי בין שורות בתוך כרטיס תוכן.
  /// משמש בהגדרות עם עץ נפתח
  static Color cardRowDivider(BuildContext context) => panelBackground(context);

  /// שכבת בחירה לכרטיסי תוכן.
  ///
  /// מוגדרת בשכבת ה-theme כדי למנוע overrides מקומיים של שקיפות
  /// מחוץ ל-`lib/theme/`.
  static Color cardSelectionOverlay(BuildContext context) =>
      Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3);

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

  /// אגודל הסקרולבר המותאם — בולט בזמן גרירה, מעומעם במנוחה.
  static Color scrollbarThumb(ColorScheme cs, {required bool isDragging}) =>
      isDragging
          ? cs.primary.withValues(alpha: 0.8)
          : cs.onSurfaceVariant.withValues(alpha: 0.4);

  /// רקע מתג קומפקטי בסגנון גלולה (מתגי דיאלוג החיפוש) — מודגש כשדלוק.
  static Color togglePill(ColorScheme cs, {required bool active}) => active
      ? cs.primaryContainer.withValues(alpha: 0.6)
      : cs.surfaceContainerHighest.withValues(alpha: 0.5);

  /// overlayColor ל-TabBar שמצייר hover מותאם אישית (foregroundPainter)
  /// ולכן רוצה לבטל את ה-hover/focus הגלובלי של [TabBarTheme].
  static final WidgetStateProperty<Color?> tabBarNoOverlay =
      WidgetStateProperty.all(Colors.transparent);
}
