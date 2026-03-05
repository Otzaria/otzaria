import 'package:flutter/material.dart';

/// רקעי מסך לסביבות שימוש שונות באפליקציה
///
/// משמש ליצירת עקביות ויזואלית בין מסכי "לוח" (panel screens):
/// הגדרות, ספריה, כלים — בניגוד למסך העיון (המסך הראשי).
class AppSurfaces {
  AppSurfaces._();

  /// רקע מסכי לוח — הגדרות, ספריה, כלים וכל מסך משני
  ///
  /// מחזיר:
  /// - מצב כהה: שחור מוחלט (כרטיסי SettingsCard בולטים מעליו)
  /// - מצב בהיר: surfaceContainerHighest בשקיפות 28% (טון עדין מעל הרקע הלבן)
  ///
  /// **שימוש:**
  /// ```dart
  /// Scaffold(
  ///   backgroundColor: AppSurfaces.panelBackground(context),
  ///   ...
  /// )
  /// ```
  static Color panelBackground(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Colors.black
        : cs.surfaceContainerHighest.withValues(alpha: 0.28);
  }
}
