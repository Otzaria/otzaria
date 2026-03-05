import 'package:flutter/material.dart';

/// קבועי צבעים סטטיים לתמה של אוצריא
///
/// כל הצבעים הדינמיים (seed color, primary, secondary) מנוהלים
/// ע"י [ColorScheme.fromSeed] ב-app.dart — זה הקובץ לצבעים הקבועים בלבד.
class AppColors {
  AppColors._();

  // ── Dark Mode Surfaces ——————————————————————————
  /// רקע ה-Scaffold במצב כהה
  static const Color darkScaffold = Color(0xFF242424);

  /// צבע כרטיסים ורכיבי Card במצב כהה
  static const Color darkCard = Color(0xFF333333);

  /// צבע ה-AppBar במצב כהה
  static const Color darkAppBar = Color(0xFF2A2A2A);

  // ── Dark Mode Text & Icons ————————————————————
  /// צבע טקסט ואייקונים ראשיים במצב כהה
  static const Color darkOnSurface = Color(0xFFE0E0E0);

  // ── Dark Mode Borders ————————————————————————
  /// צבע גבולות ומפרידים במצב כהה
  static const Color darkOutline = Color(0xFF4A4A4A);

  // ── Dialogs ——————————————————————————————————
  /// צבע מחסום הדיאלוג (barrier) — חצי שקוף, שני המצבים
  static const Color dialogBarrier = Color(0x22000000);
}
