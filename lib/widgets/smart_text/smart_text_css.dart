/// ה-CSS ש-[SmartTextWidget] מחיל על מחלקות ה-markup של הקורא.
///
/// מקור יחיד לשני מסלולי הרינדור: `customStylesBuilder` של HtmlWidget, וממיר
/// הספאנים ([InlineHtmlDocument]) שמפרש את אותן הצהרות באותו סדר.
library;

import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

/// ה-CSS של אלמנט לפי תגו ומחלקותיו, או null כשאין כלל ספציפי — אז חל
/// [smartTextHeadingCss] (ועיצוב ה-markdown, שנשאר ב-HtmlWidget בלבד).
///
/// [linkColorCss] ו-[headingColorCss] — ערכי `color` של צבע הקישור וצבע כותרת
/// הקטע; הם תלויי ערכת נושא, ולכן מועברים מבחוץ.
Map<String, String>? smartTextElementCss(
  String? tag,
  Set<String> classes, {
  required bool hasHref,
  required String? fontFamily,
  required String linkColorCss,
  required String headingColorCss,
}) {
  if (tag == 'span' && classes.contains('subscript-text')) {
    return const {'font-size': 'smaller'};
  }
  // סימונים מורמים: הגליפים נשארים בשורה — תופסים את המקום ואת הסדר הנכון,
  // וזמינים לבחירה ולהעתקה — אבל שקופים, ו-RaisedMarkerOverlay מצייר אותם.
  if (tag == 'span' && classes.contains(kFootnoteMarkerClass)) {
    return const {
      'font-size': '${kFootnoteMarkerScale}em',
      'font-style': 'italic',
      'color': 'transparent',
    };
  }
  if (tag == 'span' && classes.contains(kRaisedSupClass)) {
    return const {
      'font-size': '${kHtmlSmallerFontScale}em',
      'color': 'transparent',
    };
  }
  // סימון הערה מוטמעת לחיץ: הגליף שקוף ומורם בשכבה; ה-recognizer והריחוף
  // נשארים על הספאן, והשכבה מפנה אליו לחיצות.
  if (tag == 'a' && classes.contains('book-note-marker')) {
    return const {
      'font-size': '${kFootnoteMarkerScale}em',
      'font-style': 'italic',
      'color': 'transparent',
      'text-decoration': 'none',
    };
  }
  // סמן-מספר מודפס בגוף הספר, למשל (9): נשאר בגודלו ובמקומו, בגוון הקישור.
  if (tag == 'a' && classes.contains('numbered-note-marker')) {
    return {'color': linkColorCss, 'text-decoration': 'none'};
  }
  // סמן-אות של מפרש: הגליף שקוף, והווריאנט נשאר עליו כדי שרוחב המקום יתאים
  // לציור המורם, שנושא את הצבע, הקו התחתון והרקע הפעיל.
  if ((tag == 'span' || tag == 'a') && classes.contains('link-anchor')) {
    return {
      'font-size': '${kLinkAnchorMarkerScale}em',
      'white-space': 'nowrap',
      'color': 'transparent',
      'text-decoration': 'none',
      ...linkAnchorVariantCss(linkAnchorVariantFromClasses(classes)),
      'text-decoration-color': 'transparent',
    };
  }
  // טווח-ציטוט (לינקר): צבע הקישור בגופן הטקסט הסובב, בלי קו תחתון.
  if ((tag == 'span' || tag == 'a') && classes.contains('link-anchor-range')) {
    return {'text-decoration': 'none', 'color': linkColorCss};
  }
  if (tag == 'h3' && classes.contains(kSectionHeadingClass)) {
    return {
      ...smartTextHeadingCss(tag, fontFamily),
      'color': headingColorCss,
      // הכותרת צמודה לשורה שהיא פותחת, שמוצגת מיד מתחתיה.
      'margin-bottom': '0',
    };
  }
  if (tag == 'a' && hasHref) return {'color': linkColorCss};
  return null;
}

/// משקל וגודל כותרת שמבדילים אותה מהטקסט (ריק לתג שאינו כותרת).
Map<String, String> smartTextHeadingCss(String? tag, String? fontFamily) {
  final weight = AppFonts.headingFontWeightOverride(tag, fontFamily);
  // כותרת שאיבדה את ההדגשה מקבלת גודל שמבדיל אותה מהטקסט.
  final size = AppFonts.headingFontSizeOverride(tag, fontFamily);
  return {'font-weight': ?weight, 'font-size': ?size};
}
