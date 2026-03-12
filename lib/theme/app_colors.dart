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

  /// צבע כרטיסים ורכיבי Card במצב כהה
  static const Color darkCard = Color(0xFF333333);

  /// צבע ה-AppBar במצב כהה
  static const Color darkAppBar = Color(0xFF2A2A2A);

  // ── Dark Mode Text & Icons ────────────────────────────────────────────────
  /// צבע טקסט ואייקונים ראשיים במצב כהה
  static const Color darkOnSurface = Color(0xFFE0E0E0);

  // ── Dark Mode Borders ────────────────────────────────────────────────────
  /// צבע גבולות ומפרידים במצב כהה
  static const Color darkOutline = Color(0xFF4A4A4A);

  // ── Dialogs ────────────────────────────────────────────────────────────
  /// צבע מחסום הדיאלוג (barrier) — חצי שקוף
  static const Color dialogBarrier = Color(0x22000000);

  // ── Light Mode Surfaces ────────────────────────────────────────────────
  /// רקע עורך הזום ב-PDF במצב בהיר
  static const Color lightPdfZoomEditorBackground = Color(0xFFF9ECDF);
}
