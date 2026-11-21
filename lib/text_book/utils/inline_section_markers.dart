/// סמני חלוקה וכותרות מוזרקים לתצוגה אחרי ציוני העוגנים,
/// כדי לשמור על אופסטי המקור שלהם.
library;

import 'package:otzaria/tools/tikkun_korim/data/parasha_index.g.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';

/// מקדים לשורה את סמן החלוקה שלה, בסוגריים מרובעים ובהדגשה —
/// כמוסכמת `[אות ב]` המודפסת בתוספות רבי עקיבא איגר.
///
/// [label] הוא האות ("א") או הסעיף ("סעיף ג"), או `null` לשורה שאינה
/// פתיחת חלוקה — ואז השורה חוזרת כמות שהיא.
String prependSectionMarker(String html, String? label) {
  if (label == null || label.isEmpty || html.isEmpty) {
    return html;
  }
  return '<b class="section-marker">[$label]</b> $html';
}

/// מחלקת ה-CSS של כותרת נושא מוזרקת (מבנה `Topic`), לעיצובה ברנדרר.
const String kSectionHeadingClass = 'section-heading';

/// כותרות הנושא שנפתחות בשורה, כל אחת כבלוק `<h3>`.
String sectionHeadingsHtml(List<String> headings) =>
    headings.map((h) => '<h3 class="$kSectionHeadingClass">$h</h3>').join();

final RegExp _bracketPrefix = RegExp(r'^\s*\[[^\]]*\]\s*');

/// תווית כותרת נושא לתצוגה: בלי BOM ובלי קידומת בסוגריים ("[סימן א] ")
/// שמשכפלת את כותרת הסימן הגלויה.
String cleanSectionHeadingLabel(String label) =>
    label.replaceAll('\ufeff', '').replaceFirst(_bracketPrefix, '').trim();

final Set<String> _parashaKeys = {
  for (final parasha in kAllParashotOrder) _normalizeForMatch(parasha),
};

/// תווית כותרת פרשה: "נח" ← "פרשת נח". תווית שאינה שם פרשה ("הקדמה",
/// "ספר בראשית") מחזירה null — היא לא פרשה ולא מוזרקת.
String? parashaHeadingLabel(String label) {
  final key = _normalizeForMatch(label);
  if (key.startsWith('פרשת ')) return label.trim();
  final isParashaName = _parashaKeys.any(
    (parasha) => key == parasha || key.startsWith('$parasha '),
  );
  return isParashaName ? 'פרשת ${label.trim()}' : null;
}

/// מבנה החלוקה החודשית של תהלים (מספריא): עלה אחד לכל יום בחודש.
const String kMonthlyCycleStructureKey = '30 Day Cycle';

/// מבני הכותרות החלופיות שכותרותיהם מוזרקות לגוף הטקסט
/// ([buildSectionHeadings]).
bool injectsSectionHeadings(String structureKey) =>
    structureKey == 'Topic' ||
    structureKey == 'Parasha' ||
    structureKey == kMonthlyCycleStructureKey;

final RegExp _dayDigits = RegExp(r'^(?:day\s*)?(\d+)$', caseSensitive: false);
final RegExp _dayLetters = RegExp('^(?:יום\\s+)?([א-ת]{1,2})(?:\\s+לחודש)?\$');

/// תווית יום בחלוקה החודשית: "יום ד׳" / "Day 4" ← "יום ד׳ לחודש".
/// תווית שאינה יום 1–30 חוזרת כמות שהיא.
String monthlyCycleHeadingLabel(String label) {
  final trimmed = label.trim();
  final plain = trimmed.replaceAll(RegExp('[\'"׳״]'), '');
  final digits = _dayDigits.firstMatch(plain)?.group(1);
  final letters = _dayLetters.firstMatch(plain)?.group(1);
  final day = digits != null
      ? int.parse(digits)
      : gematriaToNumber(letters ?? '');
  if (day < 1 || day > 30) return trimmed;
  final numeral = toHebrewNumeral(day);
  final marked = numeral.length == 1
      ? '$numeral׳'
      : '${numeral.substring(0, numeral.length - 1)}״${numeral.substring(numeral.length - 1)}';
  return 'יום $marked לחודש';
}

final RegExp _regularHeadingLine = RegExp(r'^\s*<h[2-6]\b');

/// כמה שורות כותרת רגילות (h2–h6) צמודות מעל שורת היעד ([linesAbove],
/// מהקרובה לרחוקה). הן תת-חלוקה של הנושא, ולכן כותרת הנושא מוצגת לפניהן.
int sectionHeadingLinesAbove(Iterable<String?> linesAbove) {
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

/// תחילית של [_normalizeForMatch] באורך [length] לפחות, או השורה כולה.
/// חותכים לפני תגית פתוחה: אחרת תוכן התגית היה נשאר בנרמול.
String _normalizedPrefix(String line, int length) {
  for (var end = length * 2; end < line.length; end *= 2) {
    final open = line.indexOf('<', line.lastIndexOf('>', end - 1) + 1);
    final prefix = _normalizeForMatch(
      line.substring(0, open >= 0 && open < end ? open : end),
    );
    if (prefix.length >= length) return prefix;
  }
  return _normalizeForMatch(line);
}

/// כותרות הנושא להזרקה, לפי שורת העוגן שלהן. [rows] ממוינות לפי שורה ורמה;
/// [lineAt] מחזיר את תוכן השורה, או null מחוץ לספר; נקרא רק לשורות שהבדיקה
/// מגיעה אליהן, כדי שקורא עצל יפענח מעט שורות.
Map<int, List<String>> buildSectionHeadings(
  Iterable<({int lineIndex, String label})> rows,
  String? Function(int lineIndex) lineAt,
) {
  final headings = <int, List<String>>{};
  for (final row in rows) {
    final label = cleanSectionHeadingLabel(row.label);
    if (label.isEmpty) continue;
    String? above(int offset) => lineAt(row.lineIndex - offset);
    if (isSectionHeadingVisible(label, [0, 1, 2].map(above))) continue;
    final anchor = row.lineIndex - sectionHeadingLinesAbove([1, 2].map(above));
    headings.putIfAbsent(anchor, () => []).add(label);
  }
  return headings;
}

/// האם הכותרת כבר גלויה בפתיחת שורת היעד או באחת השורות שלפניה
/// ([windowLines]) — שלוש מילותיה הראשונות בראש אחת מהן.
bool isSectionHeadingVisible(String label, Iterable<String?> windowLines) {
  final key = _normalizeForMatch(label).split(' ').take(3).join(' ');
  if (key.isEmpty) return true;
  for (final line in windowLines) {
    if (line == null) continue;
    final index = _normalizedPrefix(line, key.length + 9).indexOf(key);
    // מעט תווים לפני — מספור כמו "(א)" בראש השורה.
    if (index >= 0 && index <= 8) return true;
  }
  return false;
}
