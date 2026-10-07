/// הווריאנטים הטיפוגרפיים של סמני-האות של המפרשים (עוגן-נקודה).
///
/// מקור אמת יחיד לשני מסלולי הרינדור — HtmlWidget (CSS) והקריאה הרציפה
/// (TextStyle); כל מסלול שלא ייגזר מכאן יאבד את הבחנת הווריאנטים.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:otzaria/theme/app_fonts.dart';

/// הסוגריים שבהם נתונה האות המודפסת בסמן — ההבדל הראשון שהעין תופסת בין
/// שני מפרשים על אותו דף, לפני הבדלי המשקל והנטייה.
enum LinkAnchorDelimiter {
  parentheses('(', ')'),
  brackets('[', ']'),
  braces('{', '}');

  const LinkAnchorDelimiter(this.open, this.close);

  final String open;
  final String close;

  /// האות עטופה בסוגריים האלה, למשל "[א]".
  String wrap(String letter) => '$open$letter$close';
}

/// גופן כתב רש"י של הווריאנטים.
const String kLinkAnchorRashiFont = 'NotoRashiHebrew';

/// יחס ההקטנה של סמן-האות ביחס לטקסט הסובב.
const double kLinkAnchorMarkerScale = 0.7;

/// הרמת קו הבסיס של סימון מעל קו הבסיס של הטקסט, כיחס מגודל הסימון.
const double kRaisedMarkerRaiseFactor = 0.40;

enum AnchorMarkerFont { line, rashi }

enum AnchorMarkerVariants { perCommentator, uniform }

enum AnchorMarkerColor { primary, text }

/// עיצוב אותיות העוגן שבחר המשתמש — מקור אמת יחיד לכל מסלולי התצוגה.
@immutable
class AnchorMarkerStyle {
  final double scale;
  final double raise;
  final AnchorMarkerFont font;
  final AnchorMarkerVariants variants;
  final AnchorMarkerColor color;

  const AnchorMarkerStyle({
    this.scale = kLinkAnchorMarkerScale,
    this.raise = kRaisedMarkerRaiseFactor,
    this.font = AnchorMarkerFont.line,
    this.variants = AnchorMarkerVariants.perCommentator,
    this.color = AnchorMarkerColor.primary,
  });

  /// ההגדרה הפעילה; מתעדכנת מ-SettingsBloc.
  static AnchorMarkerStyle current = const AnchorMarkerStyle();

  AnchorMarkerStyle copyWith({
    double? scale,
    double? raise,
    AnchorMarkerFont? font,
    AnchorMarkerVariants? variants,
    AnchorMarkerColor? color,
  }) => AnchorMarkerStyle(
    scale: scale ?? this.scale,
    raise: raise ?? this.raise,
    font: font ?? this.font,
    variants: variants ?? this.variants,
    color: color ?? this.color,
  );

  Map<String, Object> toJson() => {
    'scale': scale,
    'raise': raise,
    'font': font.name,
    'variants': variants.name,
    'color': color.name,
  };

  factory AnchorMarkerStyle.fromJson(Map<String, dynamic> json) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((value) => value.name == name).firstOrNull ?? fallback;
    double number(Object? value, double fallback) =>
        value is num ? value.toDouble() : fallback;
    return AnchorMarkerStyle(
      scale: number(json['scale'], kLinkAnchorMarkerScale),
      raise: number(json['raise'], kRaisedMarkerRaiseFactor),
      font: pick(AnchorMarkerFont.values, json['font'], AnchorMarkerFont.line),
      variants: pick(
        AnchorMarkerVariants.values,
        json['variants'],
        AnchorMarkerVariants.perCommentator,
      ),
      color: pick(
        AnchorMarkerColor.values,
        json['color'],
        AnchorMarkerColor.primary,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnchorMarkerStyle &&
      scale == other.scale &&
      raise == other.raise &&
      font == other.font &&
      variants == other.variants &&
      color == other.color;

  @override
  int get hashCode => Object.hash(scale, raise, font, variants, color);
}

/// וריאנט טיפוגרפי בודד. [delimiter] נכתב לתוך טקסט ה-HTML ולא ל-CSS, ולכן שני
/// מסלולי הרינדור מקבלים אותו מהתוכן; את השאר כל מסלול מחיל בדרכו.
@immutable
class LinkAnchorVariant {
  final bool bold;
  final bool italic;
  final bool rashiScript;
  final bool underline;
  final LinkAnchorDelimiter delimiter;

  const LinkAnchorVariant({
    this.bold = false,
    this.italic = false,
    this.rashiScript = false,
    this.underline = false,
    this.delimiter = LinkAnchorDelimiter.parentheses,
  });
}

/// הווריאנטים לפי האינדקס במחלקה `link-anchor-<index>`: מכפלת שלושת סוגי
/// הסוגריים בארבע ההדגשות, כדי שמפרשים על אותו דף יתנגשו לעתים רחוקות.
const List<LinkAnchorVariant> kLinkAnchorVariants = [
  LinkAnchorVariant(bold: true),
  LinkAnchorVariant(italic: true),
  LinkAnchorVariant(bold: true, italic: true),
  LinkAnchorVariant(rashiScript: true),
  LinkAnchorVariant(rashiScript: true, bold: true),
  LinkAnchorVariant(underline: true),
  LinkAnchorVariant(bold: true, delimiter: LinkAnchorDelimiter.brackets),
  LinkAnchorVariant(italic: true, delimiter: LinkAnchorDelimiter.brackets),
  LinkAnchorVariant(underline: true, delimiter: LinkAnchorDelimiter.brackets),
  LinkAnchorVariant(rashiScript: true, delimiter: LinkAnchorDelimiter.brackets),
  LinkAnchorVariant(bold: true, delimiter: LinkAnchorDelimiter.braces),
  LinkAnchorVariant(italic: true, delimiter: LinkAnchorDelimiter.braces),
  LinkAnchorVariant(underline: true, delimiter: LinkAnchorDelimiter.braces),
  LinkAnchorVariant(rashiScript: true, delimiter: LinkAnchorDelimiter.braces),
];

/// האות עטופה בסוגריים של הווריאנט שבאינדקס [variantIndex]. אינדקס שאינו
/// ברשימה נופל לסוגריים העגולים — ברירת המחדל ההיסטורית.
String wrapLinkAnchorLetter(String letter, int variantIndex) {
  final delimiter =
      variantIndex >= 0 && variantIndex < kLinkAnchorVariants.length
      ? kLinkAnchorVariants[variantIndex].delimiter
      : LinkAnchorDelimiter.parentheses;
  return delimiter.wrap(letter);
}

/// מספר הווריאנטים הזמינים (ראו [anchorStyleIndexByCommentator]).
final int kLinkAnchorStyleCount = kLinkAnchorVariants.length;

/// הווריאנט לפי מחלקות ה-CSS של האלמנט, או null כשאין מחלקת וריאנט.
LinkAnchorVariant? linkAnchorVariantFromClasses(Iterable<String> classes) {
  for (var index = 0; index < kLinkAnchorVariants.length; index++) {
    if (classes.contains('link-anchor-$index')) {
      return kLinkAnchorVariants[index];
    }
  }
  return null;
}

bool _rashiScript(LinkAnchorVariant? variant) =>
    (variant?.rashiScript ?? false) ||
    AnchorMarkerStyle.current.font == AnchorMarkerFont.rashi;

/// תרגום הווריאנט להצהרות CSS עבור flutter_widget_from_html.
Map<String, String> linkAnchorVariantCss(LinkAnchorVariant? variant) {
  return {
    if (variant?.bold ?? false) 'font-weight': 'bold',
    if (variant?.italic ?? false) 'font-style': 'italic',
    if (_rashiScript(variant)) 'font-family': kLinkAnchorRashiFont,
    if (variant?.underline ?? false) 'text-decoration': 'underline',
  };
}

/// גודל, גופן ווריאנט של גליף הציון — ל-HtmlWidget (CSS).
Map<String, String> anchorMarkerCss(Iterable<String> classes) => {
  'font-size': '${AnchorMarkerStyle.current.scale}em',
  ...linkAnchorVariantCss(linkAnchorVariantFromClasses(classes)),
};

/// גודל, גופן ווריאנט של גליף הציון — לרינדור ישיר ל-TextSpan.
TextStyle anchorMarkerTextStyle(Iterable<String> classes, TextStyle parent) =>
    applyLinkAnchorVariant(
      linkAnchorVariantFromClasses(classes),
      parent.copyWith(
        fontSize: (parent.fontSize ?? 18) * AnchorMarkerStyle.current.scale,
      ),
    );

/// החלת הווריאנט על [style] עבור רינדור ישיר ל-TextSpan (קריאה רציפה).
///
/// תכונה שהווריאנט אינו קובע נשארת בירושה מהטקסט הסובב, בדיוק כמו ב-CSS.
TextStyle applyLinkAnchorVariant(LinkAnchorVariant? variant, TextStyle style) {
  final rashi = _rashiScript(variant);
  if (variant == null && !rashi) return style;
  final fontFamily = rashi ? kLinkAnchorRashiFont : style.fontFamily;
  final bold = variant?.bold ?? false;
  return style.copyWith(
    fontFamily: fontFamily,
    fontWeight: bold ? FontWeight.bold : null,
    // בולד אמיתי לגופן משתנה — נגזר מהגופן שנפתר בפועל בסמן.
    fontVariations: bold ? AppFonts.boldFontVariations(fontFamily) : null,
    fontStyle: (variant?.italic ?? false) ? FontStyle.italic : null,
    decoration: (variant?.underline ?? false) ? TextDecoration.underline : null,
  );
}
