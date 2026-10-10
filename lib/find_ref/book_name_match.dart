/// צורת ההשוואה של שמות ספרים וכינויים באיתור מקורות, מעל [normalizeForFindRefMatch].
///
/// חלה רק בהחלטה אם יש התאמה; התוצאה נושאת את הצורה הרגילה, כי בחיפוש הכותרות
/// הפנימיות "דיינים" אינו "דינים". כינויים מושווים ב-[bookNameSpellingForm] בלבד.
library;

/// ראשי-תיבות שה"א הידיעה באה לפניהם ("הרמב"ם"), כפי שהכריע מחקר השמות של הספרייה.
/// רשימת היתר ולא דגם: רש"י, חז"ל, שו"ת ושו"ע אינם מקבלים ה"א.
const Set<String> sagesTakingDefiniteArticle = {
  // ראשונים
  'רמבם', 'רמבן', 'ראש', 'רשבא', 'רשבם', 'ריטבא', 'רדק', 'רלבג', 'ריף',
  'ראבד', 'ראבע', 'רן', 'רש', 'רי', 'רסג', 'ראה', 'ריבא', 'ריד', 'רדבז',
  'רמה', 'רמך', 'רזה', 'ריאז', 'ריץ',
  // אחרונים ומקובלים
  'רמא', 'טז', 'שך', 'בח', 'סמע', 'רעב', 'מביט', 'חידא', 'יעבץ', 'תשבץ',
  'מלבים', 'רמק', 'רמחל', 'רשש', 'רידבז', 'אדרת', 'נציב', 'רדל', 'רימ',
  'ראיה', 'ארי', 'אריזל', 'מב', 'רשז',
  // מהר"X
  'מהרם', 'מהרל', 'מהרי', 'מהרץ', 'מהרש', 'מהרשא', 'מהרשל', 'מהרשך',
  'מהרשם', 'מהריל', 'מהריק', 'מהריט', 'מהרחו', 'מהראל', 'מהרזו', 'מהריו',
  // הג"ר
  'גרא', 'גרעא', 'גרח', 'גרשז', 'גריז', 'גרישא', 'גרשש', 'גריד', 'גראל',
  'גרש', 'גרנט', 'גרמפ', 'גריב', 'גרמ', 'גריש', 'גרעקא', 'גרשזא',
  // הקורפוס
  'שס', 'תנך', 'נך', 'קבה',
};

/// וו/יי כפולות כיחידה — כתיב מלא וחסר (מקוואות/מקואות).
String bookNameSpellingForm(String text) =>
    text.contains('וו') || text.contains('יי')
    ? text.replaceAll('וו', 'ו').replaceAll('יי', 'י')
    : text;

/// טוקן אחד בצורת ההשוואה: [bookNameSpellingForm], ובלי ה"א הידיעה שלפני
/// ראשי-תיבות מ-[sagesTakingDefiniteArticle].
String bookNameMatchToken(String token) {
  final t = bookNameSpellingForm(token);
  if (t.length > 2 &&
      t.codeUnitAt(0) == 0x05D4 &&
      sagesTakingDefiniteArticle.contains(t.substring(1))) {
    return t.substring(1);
  }
  return t;
}

/// [text] כבר מנורמל ומופרד ברווחים יחידים. לשאילתות ולכותרות — לא לכינויים: כינוי
/// שגוי "הרמב"ם הלכות X" על מפרש היה נעשה זהה ל"רמב"ם הלכות X" של משנה תורה.
String bookNameMatchForm(String text) {
  if (!text.contains('וו') && !text.contains('יי') && !text.contains('ה')) {
    return text;
  }
  return text.split(' ').map(bookNameMatchToken).join(' ');
}

/// מילות השאילתה שנכתבו בגרשיים ("רמב"ם"), בצורתן המנורמלת. ספר שגם אצלו
/// המילה כתובה כך מועדף בשוויון — הנרמול לבדו אינו מבחין בגרשיים.
Set<String> quotedWordsOf(String raw, String Function(String) normalize) {
  final out = <String>{};
  for (final word in raw.split(RegExp(r'[\s,.:;()\[\]־-]+'))) {
    if (!_hasInnerQuote(word)) continue;
    final n = normalize(word);
    if (n.isNotEmpty && !n.contains(' ')) out.add(n);
  }
  return out;
}

bool _hasInnerQuote(String word) {
  for (var i = 1; i < word.length - 1; i++) {
    final c = word.codeUnitAt(i);
    if (c == 0x22 || c == 0x27 || c == 0x05F3 || c == 0x05F4) return true;
  }
  return false;
}
