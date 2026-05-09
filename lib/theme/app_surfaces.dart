import 'package:flutter/material.dart';

/// רקעי מסך לסביבות שימוש שונות באפליקציה
///
/// משמש ליצירת עקביות ויזואלית בין מסכי "לוח" (panel screens):
/// הגדרות, ספריה, כלים — בניגוד למסך העיון (המסך הראשי).
class AppSurfaces {
  AppSurfaces._();

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
}
