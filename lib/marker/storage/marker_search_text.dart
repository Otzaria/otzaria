/// נרמול לחיפוש: בלי ניקוד, טעמים, כיווניות ורישיות; גרש וגרשיים (גם
/// טיפוגרפיים) כ-' ו-", מקפים כרווח, ושלוש צורות השם — יהוה, יקוק, ה' — כאחת.
/// אותו נרמול חל על הנשמר ועל המבוקש.
String normalizeMarkerSearchText(String text) => text
    .replaceAll(RegExp('[\u05BE\u2010\u2013-]'), ' ')
    .replaceAll(RegExp('[\u05F3\u2018\u2019]'), "'")
    .replaceAll(RegExp('[\u05F4\u201C\u201D]'), '"')
    .replaceAll(RegExp('[\u0591-\u05C7\u200E\u200F\u202A-\u202E]'), '')
    .replaceAll(_kufName, _name)
    .replaceAll(_hehName, _name)
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

const String _name = '\u05D9\u05D4\u05D5\u05D4';
final RegExp _kufName = RegExp('\u05D9\u05E7\u05D5\u05E7');

/// ה' כמילה, גם אחרי אותיות שימוש בתחילת המילה (לה', וּבה'), ולא בסוף
/// מילה כמו "רבה'". גם ה' כמספר (פרק ה') מתאחד כך — החיפוש סימטרי, ולכן
/// הוא רק מוצא יותר.
final RegExp _hehName = RegExp(
  "(?<=(?:^|[^\u05D0-\u05EA])[\u05D5\u05D1\u05DB\u05DC\u05DE\u05E9\u05D4]{0,2})"
  "\u05D4'(?![\u05D0-\u05EA])",
);

/// מילות החיפוש, כל אחת כתבנית LIKE מוגנת. כל המילים נדרשות.
List<String> markerSearchPatterns(String query) => [
  for (final term in normalizeMarkerSearchText(query).split(' '))
    if (term.isNotEmpty)
      '%${term.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%',
];
