import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// צללים של משטחים מוגבהים (DD-12).
///
/// כרטיס ומשטח רגיל לא מקבלים צל אלא מסגרת `outlineVariant`. צל יש רק
/// לשתי רמות ההגבהה: [AppTokens.elevation1] (סרגל עליון וחלונית מוצמדת)
/// ו־[AppTokens.elevation2] (תפריט, tooltip, חלונית צפה וגרירה).
class AppShadows {
  AppShadows._();

  /// צבע הצל של כל משטח מוגבה, ל־`shadowColor` של [Material].
  static Color color(ColorScheme cs) => cs.shadow.withValues(alpha: 0.22);

  /// הצל של משטח צף שמצויר ב־[BoxDecoration] ולא ב־[Material].
  static List<BoxShadow> floating(ColorScheme cs) => [
    BoxShadow(color: color(cs), blurRadius: 8, offset: const Offset(0, 2)),
  ];
}
