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

  /// עיטור אחיד לשדות קלט משניים (מספר/טקסט קצר) — אותו מילוי ואותה
  /// פינה מעוגלת כמו שדה החיפוש, עם תווית פנימית במקום מסגרת.
  static InputDecoration filledDecoration(
    BuildContext context, {
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool enabled = true,
  }) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(compactRadius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      filled: true,
      fillColor: cs.onSurface.withValues(
        alpha: enabled ? unfocusedAlpha : disabledAlpha,
      ),
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      errorBorder: border,
      focusedErrorBorder: border,
    );
  }
}
