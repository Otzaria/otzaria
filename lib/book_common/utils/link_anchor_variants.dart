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

/// תרגום הווריאנט להצהרות CSS עבור flutter_widget_from_html.
Map<String, String> linkAnchorVariantCss(LinkAnchorVariant? variant) {
  if (variant == null) return const {};
  return {
    if (variant.bold) 'font-weight': 'bold',
    if (variant.italic) 'font-style': 'italic',
    if (variant.rashiScript) 'font-family': kLinkAnchorRashiFont,
    if (variant.underline) 'text-decoration': 'underline',
  };
}

/// החלת הווריאנט על [style] עבור רינדור ישיר ל-TextSpan (קריאה רציפה).
///
/// תכונה שהווריאנט אינו קובע נשארת בירושה מהטקסט הסובב, בדיוק כמו ב-CSS.
TextStyle applyLinkAnchorVariant(LinkAnchorVariant? variant, TextStyle style) {
  if (variant == null) return style;
  final fontFamily = variant.rashiScript
      ? kLinkAnchorRashiFont
      : style.fontFamily;
  return style.copyWith(
    fontFamily: fontFamily,
    fontWeight: variant.bold ? FontWeight.bold : null,
    // בולד אמיתי לגופן משתנה — נגזר מהגופן שנפתר בפועל בסמן.
    fontVariations: variant.bold
        ? AppFonts.boldFontVariations(fontFamily)
        : null,
    fontStyle: variant.italic ? FontStyle.italic : null,
    decoration: variant.underline ? TextDecoration.underline : null,
  );
}
