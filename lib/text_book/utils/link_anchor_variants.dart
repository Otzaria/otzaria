/// הווריאנטים הטיפוגרפיים של סמני-האות של המפרשים (עוגן-נקודה).
///
/// מקור אמת יחיד לשני מסלולי הרינדור — HtmlWidget (CSS) והקריאה הרציפה
/// (TextStyle). כשהמיפוי היה משוכפל, מצב הקריאה הרציפה פשוט לא יישם אותו
/// וכל המפרשים קיבלו סמן זהה.
library;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:otzaria/theme/app_fonts.dart';

/// גופן כתב רש"י של הווריאנטים.
const String kLinkAnchorRashiFont = 'NotoRashiHebrew';

/// יחס ההקטנה של סמן-האות ביחס לטקסט הסובב.
const double kLinkAnchorMarkerScale = 0.7;

/// תיאור ניטרלי-לרינדור של וריאנט טיפוגרפי בודד.
@immutable
class LinkAnchorVariant {
  final bool bold;
  final bool italic;
  final bool rashiScript;
  final bool underline;

  const LinkAnchorVariant({
    this.bold = false,
    this.italic = false,
    this.rashiScript = false,
    this.underline = false,
  });
}

/// הווריאנטים לפי סדר האינדקס במחלקה `link-anchor-<index>`.
const List<LinkAnchorVariant> kLinkAnchorVariants = [
  LinkAnchorVariant(bold: true),
  LinkAnchorVariant(italic: true),
  LinkAnchorVariant(bold: true, italic: true),
  LinkAnchorVariant(rashiScript: true),
  LinkAnchorVariant(rashiScript: true, bold: true),
  LinkAnchorVariant(underline: true),
];

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
