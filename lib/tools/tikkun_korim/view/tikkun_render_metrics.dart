/// המידות שמהן נגזרת כל שורה בעמוד התיקון — התרגום של משתני ה-CSS של התוסף.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

/// רוחב הייחוס שאליו מכוילים גדלי הגופן בהגדרות (max-width של עמוד הקורא).
const double kTikkunReferenceWidth = 1250;
const double kTikkunHorizontalPadding = 56;

/// מקדם ביטחון — רוחב המילים בפועל משתנה (טעמים, אותיות רחבות).
const double kTikkunScaleSafety = 0.95;

/// רצפת קנה המידה הרספונסיבי.
const double kTikkunMinScale = 0.45;

/// הרוחב שמתחתיו קנה המידה כבר ברצפה — שני טורים אינם קריאים, ומציגים אחד.
const double kTikkunTwoColumnMinWidth =
    kTikkunHorizontalPadding +
    (kTikkunReferenceWidth - kTikkunHorizontalPadding) *
        kTikkunMinScale /
        kTikkunScaleSafety;

/// גופן הבסיס של השורה, שממנו נגזרות כל מידות ה-em.
const double kTikkunRowBaseFontSize = 16;

/// רוחב עמודת המסמנים (‎flex: 0 0 4.5em‎), ואיתה שני המרווחים שלצדיה.
const double kTikkunMarkersWidthEm = 4.5;
const double kTikkunMarkersAreaEm = kTikkunMarkersWidthEm + 2;

/// הריפוד האופקי של רשימת השורות, בכל צד (ב-em).
const double kTikkunRowPaddingEm = 0.75;

/// רוחב הייחוס כשמוצג טור יחיד ממורכז: העמוד צר כך שהטור — שתופס את כל
/// השורה — יהיה ברוחב טור אחד מתוך שניים באותו קנה מידה.
const double kTikkunSingleColumnReferenceWidth =
    kTikkunReferenceWidth / 2 +
    kTikkunRowBaseFontSize *
        (kTikkunMarkersAreaEm + 2 * kTikkunRowPaddingEm) /
        2;

/// גודל הגופן של הטקסט עצמו ברוחב הייחוס — קבוע, נגזר רק מהרוחב בפועל.
const double kTikkunTextBaseFontSize = 25;

@immutable
class TikkunRenderMetrics {
  /// קנה המידה הרספונסיבי (0.45–1) לפי רוחב אזור הקריאה.
  final double scale;
  final double stamFontSize;
  final double nikudFontSize;
  final double lineHeight;
  final String stamFontFamily;
  final String nikudFontFamily;

  const TikkunRenderMetrics({
    required this.scale,
    required this.stamFontSize,
    required this.nikudFontSize,
    required this.lineHeight,
    required this.stamFontFamily,
    required this.nikudFontFamily,
  });

  /// רוחב הייחוס, שהוא גם רוחב העמוד המרבי, לפי פריסת הטורים.
  static double referenceWidthFor(TikkunSettings settings) =>
      settings.showsSingleCenteredColumn
      ? kTikkunSingleColumnReferenceWidth
      : kTikkunReferenceWidth;

  factory TikkunRenderMetrics.forWidth(double width, TikkunSettings settings) {
    final available = width - kTikkunHorizontalPadding;
    final reference = referenceWidthFor(settings) - kTikkunHorizontalPadding;
    final scale = ((available / reference) * kTikkunScaleSafety).clamp(
      kTikkunMinScale,
      1.0,
    );
    return TikkunRenderMetrics(
      scale: scale,
      stamFontSize: kTikkunTextBaseFontSize * scale,
      nikudFontSize: kTikkunTextBaseFontSize * scale,
      lineHeight: math.max(1.0, settings.resolvedLineSpacing),
      stamFontFamily: settings.stamFontFamily,
      nikudFontFamily: settings.nikudFontFamily,
    );
  }

  /// גופן הבסיס של השורה — יחידת ה-em של הרווחים והמסמנים.
  double get rowFontSize => kTikkunRowBaseFontSize * scale;

  double em(double value) => rowFontSize * value;

  double get markersWidth => em(kTikkunMarkersWidthEm);

  /// המרווח בין הטורים (‎gap: 1em‎ ב-.reader-row).
  double get columnGap => em(1);

  /// המרווח והריפוד האנכיים של השורה, מוכפלים ב-line-spacing כמו ב-CSS.
  double marginBottom(double lineSpacing) => em(lineSpacing * 0.577);

  double paddingBottom(double lineSpacing) => em(lineSpacing * 0.385);

  double minRowHeight(double lineSpacing) => em(lineSpacing * 1.923);

  // ריווח-אותיות מפורש: אחרת הווידג'ט יורש 0.25 מערכת הנושא והמדידה ב-TextPainter לא.
  TextStyle stamStyle({double factor = 1}) => TextStyle(
    fontFamily: stamFontFamily,
    fontSize: stamFontSize * factor,
    height: lineHeight,
    letterSpacing: 0,
  );

  TextStyle nikudStyle({double factor = 1}) => TextStyle(
    fontFamily: nikudFontFamily,
    fontSize: nikudFontSize * factor,
    height: lineHeight,
    letterSpacing: 0,
  );
}

/// רוחב תו ("ch") של סגנון — נמדד פעם אחת לכל (גופן, גודל).
double tikkunChWidth(TextStyle style) {
  final key = '${style.fontFamily}|${style.fontSize}';
  final cached = _chWidthCache[key];
  if (cached != null) return cached;
  final painter = TextPainter(
    text: TextSpan(text: '0', style: style),
    textDirection: TextDirection.rtl,
  )..layout();
  final width = painter.width;
  painter.dispose();
  _chWidthCache[key] = width;
  return width;
}

final Map<String, double> _chWidthCache = {};

/// מקדם הגודל של קטע מיוחד לפי מחלקות העיצוב שלו (`compact`, `compact-lg`…).
double tikkunCompactFactor(Set<String> cssClasses) {
  if (cssClasses.contains('compact')) return 0.7;
  if (cssClasses.contains('compact-md-light')) return 0.75;
  if (cssClasses.contains('compact-md')) return 0.8;
  if (cssClasses.contains('compact-lg')) return 0.85;
  return 1;
}
