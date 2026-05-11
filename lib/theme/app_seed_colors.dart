import 'package:flutter/material.dart';

/// צבעי הבסיס הזמינים לבחירת ערכת הצבעים של האפליקציה.
///
/// כל צבע משמש כ-seed ל-[ColorScheme.fromSeed] ומייצר ערכת צבעים מלאה.
class AppSeedColors {
  AppSeedColors._();

  // ── ברירות מחדל ————————————————————————————————
  static const Color defaultLight = darkBrown;
  static const Color defaultDark = purple;

  // ── צבעי ספקטרום ————————————————————————————————
  static const Color red = Color(0xFFF44336);
  static const Color orange = Color(0xFFFF9800);
  static const Color amber = Color(0xFFFFC107);
  static const Color green = Color(0xFF4CAF50);
  static const Color teal = Color(0xFF009688);
  static const Color blue = Color(0xFF2196F3);
  static const Color blueGrey = Color(0xFF607D8B);
  static const Color navy = Color(0xFF001A33);
  static const Color purple = Color(0xFF9C27B0);

  // ── צבעים נייטרלים ————————————————————————————
  static const Color brown = Color(0xFF795548);
  static const Color parchment = Color(0xFFD7CCC8);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color darkBrown = Color(0xFF2C1B02);

  /// רשימת כל הצבעים עם שמותיהם בעברית
  static const List<({Color color, String name})> options = [
    (color: red, name: 'אדום'),
    (color: orange, name: 'כתום'),
    (color: amber, name: 'ענבר'),
    (color: green, name: 'ירוק'),
    (color: teal, name: 'טורקיז'),
    (color: blue, name: 'כחול'),
    (color: blueGrey, name: 'אפור גרפיט'),
    (color: navy, name: 'כחול כהה'),
    (color: purple, name: 'סגול'),
    (color: brown, name: 'חום'),
    (color: parchment, name: 'פרגמנט / בז\''),
    (color: grey, name: 'אפור'),
    (color: darkBrown, name: 'חום עמוק'),
  ];

  /// מחזיר את השם העברי של צבע, או null אם לא נמצא ברשימה.
  static String? nameOf(Color color) {
    for (final entry in options) {
      if (entry.color == color) return entry.name;
    }
    return null;
  }
}
