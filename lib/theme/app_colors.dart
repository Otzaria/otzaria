import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
//  app_colors.dart
//  ════════════════════════════════════════════════════════════════════════════
//  צבעים קבועים (hard-coded) של אוצריא.
//
//  **מה שייך לכאן:**
//    צבעים שאינם חלק מה-ColorScheme הדינמי —
//    כגון גוני Dark mode שאי אפשר לגזור מ-fromSeed.
//
//  **מה שאינו שייך לכאן:**
//    • primary, secondary, surface וכו' — אלו נגזרים מ-ColorScheme.fromSeed
//      ב-AppTheme ו-app.dart, ואין צורך לדעת את ערכם הספציפי
//    • צבעים הדורשים BuildContext (כגון Theme.of(context).colorScheme.xxx)
//      — הם שייכים ל-AppSurfaces
// ════════════════════════════════════════════════════════════════════════════

/// צבעים קבועים שאינם חלק מה-ColorScheme הדינמי
class AppColors {
  AppColors._();

  // ── Dark Mode Surfaces ──────────────────────────────────────────────────
  /// רקע ה-Scaffold במצב כהה
  static const Color darkScaffold = Color(0xFF242424);

  // ── Dialogs ────────────────────────────────────────────────────────────
  /// צבע מחסום הדיאלוג (barrier) — חצי שקוף
  static const Color dialogBarrier = Color(0x22000000);

  // ── Document / Print ─────────────────────────────────────────────────────
  /// לבן מוחלט — רקע לרינדור דפי PDF, הדפסה וכל תצוגת "דף נייר"
  /// משמש גם כ-int (pageWhite.toARGB32()) עבור פרמטרי backgroundColor ב-pdfrx
  static const Color pageWhite = Colors.white;

  // ── Highlights ───────────────────────────────────────────────────────────
  /// צבע הדגשת "סימנייה קבועה" (?mark) — רקע צהוב שקוף 50% על השורה הממוקדת
  static const Color permanentHighlight = Color(0x80FFFF00);
}
