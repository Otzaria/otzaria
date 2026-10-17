/// חוזה ה-markup של טקסט אוצריא (§24) — **מקור יחיד**.
///
/// כל ממיר (Word, EPUB, ODT, RTF) מייצר את אותן תגיות בדיוק, ושכבת התצוגה,
/// תוכן העניינים והחיפוש מזהים אותן בלי לדעת מאיזה פורמט הגיעו. תבנית
/// שנכתבת פעמיים נוטה להיסתר בין הממירים, ואז אותו מסמך נראה אחרת לפי
/// הסיומת שלו.
library;

/// טקסט מסמך כשורת פלט אחת.
///
/// פלט אוצריא מופרד ב-`\n`, ולכן שורה-חדשה **בתוך** תוכן המסמך (מפיק שכותב
/// את ה-XML עם הזחה) הייתה מפצלת פסקה לכמה "שורות" ומסיטה את אינדקסי תוכן
/// העניינים ואת עוגני ההערות האישיות מול מה שהקורא רואה.
String otzariaInlineText(String text) =>
    text.contains('\n') || text.contains('\r')
    ? text.replaceAll(_lineBreaks, ' ')
    : text;

final RegExp _lineBreaks = RegExp(r'[\r\n]+');

/// תמונה מוטמעת. [src] ריק משאיר את התג במקומו — כך מבנה השורות, ועמו
/// מיקומי ההערות והסימניות, נשמר גם בהמרה חסרת-תמונות.
///
/// המאפיינים האופציונליים קיימים עבור פורמט שהמסמך שלו מצהיר עליהם (HTML);
/// הקוראים האחרים אינם מעבירים אותם, ולכן הפלט שלהם אינו משתנה. **הערכים
/// חייבים להגיע מאומתים** — הם נכנסים ישירות לתגית.
String otzariaImage(
  String src, {
  String? width,
  String? height,
  String? alt,
  String? title,
}) {
  final attributes = StringBuffer();
  if (width != null) attributes.write(' width="$width"');
  if (height != null) attributes.write(' height="$height"');
  if (alt != null) attributes.write(' alt="$alt"');
  if (title != null) attributes.write(' title="$title"');
  return '<img src="$src"$attributes style="max-width: 100%;"/>';
}

/// סימן הערת שוליים. נכתב בנפרד מהגוף עבור ממיר שמרכיב אותם בשלבים.
///
/// [marker] הוא טקסט תצוגה ולא מספר: ב-EPUB הסימן נלקח מהעוגן שבמסמך
/// (`*`, `[1]`), ורק כשאין לו טקסט נופלים למונה רץ.
String otzariaFootnoteMarker(String marker) =>
    '<sup class="footnote-marker">$marker</sup>';

/// סימן הערת שוליים וגופה, צמודים — הצמידות היא מה ששכבת התצוגה מזהה.
String otzariaFootnote(String marker, String body) =>
    '${otzariaFootnoteMarker(marker)}<i class="footnote">$body</i>';

/// פתיחת טבלה. [attributes] מיועד ל-`dir="rtl"` בטבלה שהמסמך סימן כ-RTL.
String otzariaTableOpen({String attributes = ''}) =>
    '<table$attributes style="border-collapse: collapse; '
    'border: 1px solid #999;">';

/// סגנון תא בטבלה.
const String otzariaTableCellStyle = 'border: 1px solid #999; padding: 4px 8px';

/// הסכימות שמותר לממיר לכתוב ב-`href`.
///
/// זו **רשימת היתר** ולא רשימת חסימה: `javascript:`, `data:text/html`,
/// `file:` ו-`otzaria://` נופלות מחוצה לה מאליהן, וכך גם כל סכימה שתיווסף
/// לעולם.
const Set<String> kAllowedLinkSchemes = {'http', 'https', 'mailto'};

/// `book://שם הספר#כותרת` — קישור לספר אחר בספרייה. סכימה מתועדת לכותבי
/// ספרים, והקורא פותח בה ספר בלשונית חדשה.
const String kBookLinkScheme = 'book';

/// האם [href] הוא קישור "העתק קישור ישיר" שפותח ספר (`otzaria://open/book/…`
/// או `otzaria://open/pdf/…`). שאר פעולות `otzaria://` אינן נגישות מתוכן ספר.
bool isOtzariaBookLink(String href) {
  // userInfo נפסל: `otzaria://note@open/…` היה עובר כאן ונתפס בקורא כ-`otzaria://note`.
  final uri = Uri.tryParse(href.trim());
  if (uri == null ||
      uri.scheme != 'otzaria' ||
      uri.host != 'open' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return false;
  }
  final segments = uri.pathSegments;
  return segments.length == 2 &&
      (segments.first == 'book' || segments.first == 'pdf') &&
      segments.last.isNotEmpty;
}

/// מסנן יעד קישור שהגיע מתוך המסמך, או `null` כשאין לכתוב `<a>` כלל.
///
/// escape של המאפיין מונע שבירה של `href="…"` אבל אינו מונע `javascript:` —
/// ולכן הסכימה נבדקת בנפרד. קישור שנפסל מוצג כטקסט בלבד, בלי לאבד את תוכנו.
///
/// [allowBookLinks] מתיר גם קישורים לספרי הספרייה (`book://` ו-
/// [isOtzariaBookLink]) — רק ל-HTML, שבו משתמשים מדביקים קישורים כאלה.
String? safeLinkTarget(String href, {bool allowBookLinks = false}) {
  final trimmed = href.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('#')) return trimmed; // עוגן פנימי
  if (trimmed.startsWith('//')) return null;
  final colon = trimmed.indexOf(':');
  if (colon < 0) return trimmed; // נתיב יחסי
  final scheme = trimmed.substring(0, colon).toLowerCase();
  if (allowBookLinks &&
      (scheme == kBookLinkScheme || isOtzariaBookLink(trimmed))) {
    return trimmed;
  }
  return kAllowedLinkSchemes.contains(scheme) ? trimmed : null;
}
