/// המידות שמהן נגזרת כל שורה בעמוד התיקון — התרגום של משתני ה-CSS של התוסף.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart';

/// רוחב הייחוס שאליו מכוילים גדלי הגופן בהגדרות (max-width של עמוד הקורא).
const double kTikkunReferenceWidth = 1482;
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

/// גובה האות כשבר מגודל הגופן, לגופן שטרם נמדד — כמו ב-Ashkenazi-Stam.
const double kTikkunDefaultLetterHeight = 0.62;

/// הריווח בין השורות במרווח 1.0, בגבהי אות. מעל "כמלוא שיטה" שבספר תורה,
/// כי צוואר הלמ"ד והתגין ממלאים את הרווח ההלכתי ומצופפים את המראה.
const double kTikkunLineGapLetters = 1.75;

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

/// רוחב תוכן הטור לפי הגאומטריה של השורה — אותם מרווחים שהיא מציירת בפועל.
/// גודל הכתב נגזר ממנו ומתקציב השורה, כך שהרוחב המרונדר שווה בדיוק לזה
/// שהמעמד חתך לפיו (ראה stam_width_model_test).
double tikkunColumnContentFor(
  double pageWidth,
  double scale,
  TikkunSettings settings,
) {
  final rowFont = kTikkunRowBaseFontSize * scale;
  final rowWidth = pageWidth - 2 * rowFont * kTikkunRowPaddingEm;
  final free = rowWidth - rowFont * kTikkunMarkersAreaEm;
  final column = settings.showsSingleCenteredColumn ? free : free / 2;
  return column - rowFont;
}

@immutable
class TikkunRenderMetrics {
  /// קנה המידה הרספונסיבי (0.45–1) לפי רוחב אזור הקריאה.
  final double scale;
  final double stamFontSize;
  final double nikudFontSize;
  final double lineHeight;

  /// המרחק בין שורה לשורה: גובה האות ועוד הריווח, שהוא
  /// [kTikkunLineGapLetters] גבהי אות כפול הגדרת המרווח.
  final double rowPitch;
  final String stamFontFamily;
  final String nikudFontFamily;

  /// רוחב העמוד שהמידות נגזרו ממנו, בלי הזום.
  final double pageWidth;

  const TikkunRenderMetrics({
    required this.scale,
    required this.stamFontSize,
    required this.nikudFontSize,
    required this.lineHeight,
    required this.rowPitch,
    required this.stamFontFamily,
    required this.nikudFontFamily,
    required this.pageWidth,
  });

  /// רוחב הייחוס, שהוא גם רוחב העמוד המרבי, לפי פריסת הטורים.
  static double referenceWidthFor(TikkunSettings settings) =>
      settings.showsSingleCenteredColumn
      ? kTikkunSingleColumnReferenceWidth
      : kTikkunReferenceWidth;

  /// [zoom] מכפיל את קנה המידה בלבד. הפריסה נגזרת מיחסי ה-em ולכן אינה
  /// משתנה — הייצוא ל-PDF אינו מעביר אותו וממילא אינו מושפע.
  /// דף רחב פי [pageWidthFactor] נפרש עד [maxPageWidth] באותו כתב, ומוקטן רק
  /// כשאין די מקום.
  factory TikkunRenderMetrics.forWidth(
    double width,
    TikkunSettings settings, {
    double zoom = 1,
    required double lineWidthEm,
    double pageWidthFactor = 1,
    double? maxPageWidth,
  }) {
    final regularWidth = math.min(width, referenceWidthFor(settings));
    final available = width - kTikkunHorizontalPadding;
    final reference = referenceWidthFor(settings) - kTikkunHorizontalPadding;
    final baseScale = ((available / reference) * kTikkunScaleSafety).clamp(
      kTikkunMinScale,
      1.0,
    );
    final scale = baseScale * zoom;
    final columns = settings.showsSingleCenteredColumn ? 1 : 2;
    final pageWidth = math.min(
      maxPageWidth ?? width,
      regularWidth +
          (pageWidthFactor - 1) *
              tikkunColumnContentFor(regularWidth, baseScale, settings) *
              columns,
    );
    // הגאומטריה נמדדת בלי הזום, שמגדיל אחר כך את הכול באותו יחס.
    final fontSize =
        tikkunColumnContentFor(pageWidth, baseScale, settings) /
        (lineWidthEm * pageWidthFactor) *
        zoom;
    final letter =
        stamLetterHeightFor(settings.stamFontFamily) ??
        kTikkunDefaultLetterHeight;
    final lineHeight =
        letter * (1 + kTikkunLineGapLetters * settings.lineSpacing);
    return TikkunRenderMetrics(
      pageWidth: pageWidth,
      scale: scale,
      stamFontSize: fontSize,
      nikudFontSize: fontSize,
      lineHeight: lineHeight,
      rowPitch: fontSize * lineHeight,
      stamFontFamily: settings.stamFontFamily,
      nikudFontFamily: settings.nikudFontFamily,
    );
  }

  /// אותה גאומטריה בכתב מוקטן פי [factor] — לשורת דף רחב בתוך דף רגיל.
  TikkunRenderMetrics withFontScale(double factor) => TikkunRenderMetrics(
    pageWidth: pageWidth,
    scale: scale,
    stamFontSize: stamFontSize * factor,
    nikudFontSize: nikudFontSize * factor,
    lineHeight: lineHeight,
    rowPitch: rowPitch,
    stamFontFamily: stamFontFamily,
    nikudFontFamily: nikudFontFamily,
  );

  /// גופן הבסיס של השורה — יחידת ה-em של הרווחים והמסמנים.
  double get rowFontSize => kTikkunRowBaseFontSize * scale;

  double em(double value) => rowFontSize * value;

  double get markersWidth => em(kTikkunMarkersWidthEm);

  /// המרווח בין הטורים (‎gap: 1em‎ ב-.reader-row).
  double get columnGap => em(1);

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
