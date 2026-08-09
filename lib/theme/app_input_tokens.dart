// lib/theme/app_input_tokens.dart
//
// Tokens משותפים לכל שדות הקלט באפליקציה.
// מגדיר גבהים, רדיוסים, גדלי פונט ו-alpha values אחידים.

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

abstract class AppInputTokens {
  // ── גבהים ──────────────────────────────────────────────────────────────────
  static const double regularHeight = 48.0;
  static const double compactHeight = 36.0;

  // ── רדיוסים ────────────────────────────────────────────────────────────────
  static const double regularRadius = 28.0;
  static const double compactRadius = 20.0;

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

  static double radius(bool isCompact) =>
      isCompact ? compactRadius : regularRadius;

  static double fontSize(bool isCompact) =>
      isCompact ? compactFontSize : regularFontSize;

  /// מילוי הרקע האחיד של שדות הקלט — משמש גם פקדים שאינם שדה טקסט
  /// (כפתור־תפריט בשורת החיפוש) כדי שיֵראו חלק מאותה שורה.
  static Color fillColor(BuildContext context, {bool enabled = true}) =>
      Theme.of(context).colorScheme.onSurface.withValues(
        alpha: enabled ? unfocusedAlpha : disabledAlpha,
      );

  /// עיטור אחיד לשדות קלט משניים (מספר/טקסט קצר) — אותו מילוי ואותה
  /// פינה מעוגלת כמו שדה החיפוש, בלי מסגרת ובלי תווית פנימית.
  /// את התווית יש להציג מעל השדה ([LabeledInput]).
  static InputDecoration filledDecoration(
    BuildContext context, {
    String? hintText,
    TextStyle? hintStyle,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool enabled = true,
  }) {
    // אותה פינה של שדה החיפוש (AppTokens.borderRadiusAll), כדי ששדות
    // שיושבים באותה שורה ייראו כמשפחה אחת.
    const border = OutlineInputBorder(
      borderRadius: AppTokens.borderRadiusAll,
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      filled: true,
      fillColor: fillColor(context, enabled: enabled),
      hintText: hintText,
      hintStyle: hintStyle,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
    );
  }
}
