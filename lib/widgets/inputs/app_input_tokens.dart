// lib/widgets/inputs/app_input_tokens.dart
//
// Tokens משותפים לכל שדות הקלט באפליקציה.
// מגדיר גבהים, רדיוסים, גדלי פונט ו-alpha values אחידים.

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

  // ── רוחבי אייקונים ─────────────────────────────────────────────────────────
  static const double regularPrefixMinWidth = 44.0;
  static const double compactPrefixMinWidth = 36.0;

  static const double regularSuffixMinWidth = 40.0;
  static const double compactSuffixMinWidth = 32.0;

  static const double regularIconSize = 20.0;
  static const double compactIconSize = 18.0;

  // ── פונקציות עזר ───────────────────────────────────────────────────────────

  static double height(bool isCompact) =>
      isCompact ? compactHeight : regularHeight;

  static double radius(bool isCompact) =>
      isCompact ? compactRadius : regularRadius;

  static double fontSize(bool isCompact) =>
      isCompact ? compactFontSize : regularFontSize;

  static double prefixMinWidth(bool isCompact) =>
      isCompact ? compactPrefixMinWidth : regularPrefixMinWidth;

  static double suffixMinWidth(bool isCompact) =>
      isCompact ? compactSuffixMinWidth : regularSuffixMinWidth;

  static double iconSize(bool isCompact) =>
      isCompact ? compactIconSize : regularIconSize;
}
