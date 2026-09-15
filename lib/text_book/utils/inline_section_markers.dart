/// סמני חלוקה בגוף הטקסט — אותיות פסקה במדרש רבה, סעיפים בנושאי-כלים.
///
/// במהדורות הדפוס כל פסקה במדרש רבה נפתחת באות (א, ב, ג...), ובנושאי
/// הכלים על השולחן ערוך הסעיפים הקטנים מקובצים לפי הסעיף שהם מפרשים.
/// בטקסט השמור במסד הסימונים האלה אינם קיימים — האותיות זמינות רק כמבנה
/// alt-TOC מסוג `Simanim`, והשיוך לסעיף רק בקישורי ה-COMMENTARY — ולכן
/// הם מוזרקים כאן לתצוגה בלבד, בראש השורה.
///
/// כך גם כותרות נושא ממבנה `Topic` ("הלכות ציצית") שקיימות רק בעץ הניווט.
///
/// ההזרקה מוסיפה תוכן גלוי, ולכן חייבת לרוץ *אחרי* הזרקת סמני עוגן-מילה
/// ([injectLinkAnchorMarkers]) שמסתמכת על אופסטי התווים של הטקסט השמור.
library;

/// מקדים לשורה את סמן החלוקה שלה, בסוגריים מרובעים ובהדגשה —
/// כמוסכמת `[אות ב]` המודפסת בתוספות רבי עקיבא איגר.
///
/// [label] הוא האות ("א") או הסעיף ("סעיף ג"), או `null` לשורה שאינה
/// פתיחת חלוקה — ואז השורה חוזרת כמות שהיא.
String prependSectionMarker(String html, String? label) {
  if (label == null || label.isEmpty || html.isEmpty) {
    return html;
  }
  return '<b>[$label]</b> $html';
}

/// מחלקת ה-CSS של כותרת נושא מוזרקת (מבנה `Topic`), לעיצובה ברנדרר.
const String kSectionHeadingClass = 'section-heading';

/// מקדים לשורה את כותרות הנושא שנפתחות בה, כל אחת כבלוק `<h3>`.
String prependSectionHeadings(String html, List<String>? headings) {
  if (headings == null || headings.isEmpty || html.isEmpty) {
    return html;
  }
  final prefix = headings
      .map((h) => '<h3 class="$kSectionHeadingClass">$h</h3>')
      .join();
  return '$prefix$html';
}

final RegExp _bracketPrefix = RegExp(r'^\s*\[[^\]]*\]\s*');

/// תווית כותרת נושא לתצוגה: בלי BOM ובלי קידומת בסוגריים ("[סימן א] ")
/// שמשכפלת את כותרת הסימן הגלויה.
String cleanSectionHeadingLabel(String label) =>
    label.replaceAll('﻿', '').replaceFirst(_bracketPrefix, '').trim();

final RegExp _regularHeadingLine = RegExp(r'^\s*<h[2-6]\b');

/// כמה שורות כותרת רגילות (h2–h6) צמודות מעל שורת היעד ([linesAbove],
/// מהקרובה לרחוקה). הן תת-חלוקה של הנושא, ולכן כותרת הנושא מוצגת לפניהן.
int sectionHeadingLinesAbove(List<String?> linesAbove) {
  var count = 0;
  for (final line in linesAbove) {
    if (line == null || !_regularHeadingLine.hasMatch(line)) break;
    count++;
  }
  return count;
}

final RegExp _htmlTag = RegExp(r'<[^>]+>');
final RegExp _nikudAndMatres = RegExp(r'[֑-ׇוי]');
final RegExp _nonLetters = RegExp(r'[^א-ת0-9 ]');
final RegExp _spaces = RegExp(r'\s+');

// בלי ו/י: הכותרת בעץ ובגוף הספר כתובות לעיתים בכתיב שונה (בביאור/בְּבֵאוּר).
String _normalizeForMatch(String text) => text
    .replaceAll(_htmlTag, ' ')
    .replaceAll(_nikudAndMatres, '')
    .replaceAll(_nonLetters, ' ')
    .replaceAll(_spaces, ' ')
    .trim();

/// האם הכותרת כבר גלויה בפתיחת שורת היעד או באחת השורות שלפניה
/// ([windowLines]) — שלוש מילותיה הראשונות בראש אחת מהן.
bool isSectionHeadingVisible(String label, List<String?> windowLines) {
  final key = _normalizeForMatch(label).split(' ').take(3).join(' ');
  if (key.isEmpty) return true;
  for (final line in windowLines) {
    if (line == null) continue;
    final index = _normalizeForMatch(line).indexOf(key);
    // מעט תווים לפני — מספור כמו "(א)" בראש השורה.
    if (index >= 0 && index <= 8) return true;
  }
  return false;
}
