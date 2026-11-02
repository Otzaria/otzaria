import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';

/// סימני CSS לצבעי הדגשת החיפוש והסימון (DD-17).
///
/// ההדגשה נכתבת ב-HTML של השורה בלי תלות בערכת הנושא (והתוצאה נשמרת
/// במטמון), והסימנים מוחלפים בצבעי [AppSurfaces] רגע לפני הרינדור.
abstract final class SearchHighlightCss {
  static const String hit = 'otzaria-search-hit';
  static const String current = 'otzaria-search-current';
  static const String currentBackground = 'otzaria-search-current-bg';
  static const String mark = 'otzaria-mark';
  static const String onMark = 'otzaria-on-mark';

  static final RegExp _token = RegExp(
    r'otzaria-(?:search-current-bg|search-current|search-hit|on-mark|mark)'
    r'(?![\w-])',
  );

  /// בדיקה זולה, לפני שנדרשת ערכת הנושא.
  static bool hasTokens(String html) =>
      html.contains('otzaria-search-') || html.contains('otzaria-mark');

  /// [html] עם צבעי ערכת הנושא [cs] במקום הסימנים.
  static String resolve(String html, ColorScheme cs) {
    if (!hasTokens(html)) return html;
    return html.replaceAllMapped(_token, (match) {
      final color = switch (match[0]) {
        hit => AppSurfaces.searchHit(cs),
        current => AppSurfaces.searchHitCurrent(cs),
        currentBackground => AppSurfaces.searchHitCurrentBackground(cs),
        mark => AppSurfaces.permanentMark(cs),
        _ => AppSurfaces.onPermanentMark(cs),
      };
      return _cssHex(color);
    });
  }

  /// `#rrggbbaa`, שכל מסלולי הרינדור קוראים.
  static String _cssHex(Color color) {
    final argb = color.toARGB32();
    final rgb = (argb & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
    final alpha = (argb >>> 24).toRadixString(16).padLeft(2, '0');
    return '#$rgb$alpha';
  }
}
