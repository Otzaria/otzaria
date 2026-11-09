// lib/theme/app_input_tokens.dart
//
// Tokens משותפים לכל שדות הקלט באפליקציה.
// מגדיר גבהים, רדיוסים, גדלי פונט ו-alpha values אחידים.

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';

abstract class AppInputTokens {
  // ── גבהים ──────────────────────────────────────────────────────────────────
  static const double regularHeight = 48.0;
  static const double compactHeight = 36.0;

  // ── גדלי פונט ──────────────────────────────────────────────────────────────
  static const double regularFontSize = AppTokens.fontLG; // 16
  static const double compactFontSize = 13.0;

  // ── Alpha values לרקעים ────────────────────────────────────────────────────
  static const double unfocusedAlpha = 0.07;
  static const double focusedAlpha = 0.12;
  static const double disabledAlpha = 0.04;

  // ── פונקציות עזר ───────────────────────────────────────────────────────────

  static double height(bool isCompact) =>
      isCompact ? compactHeight : regularHeight;

  static double fontSize(bool isCompact) =>
      isCompact ? compactFontSize : regularFontSize;
}

/// שדה בתוך טופס בדיאלוג: מילוי במשטח הבהיר של הכרטיס ([AppSurfaces.card]) על
/// גוף הדיאלוג, כך שהשדות בולטים מהרקע. אחד לכל הטפסים, כדי ששני טפסים של אותו
/// דבר לא ייראו שונה.
extension DialogFormFieldDecoration on InputDecoration {
  InputDecoration filledOnDialog(BuildContext context) =>
      copyWith(filled: true, fillColor: AppSurfaces.card(context));
}
