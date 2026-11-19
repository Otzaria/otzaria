/// צורת ההשוואה של שמות ספרים וכינויים באיתור מקורות, מעל [normalizeForFindRefMatch].
///
/// חלה רק בהחלטה אם יש התאמה; התוצאה נושאת את הצורה הרגילה, כי בחיפוש הכותרות
/// הפנימיות "דיינים" אינו "דינים". כינויים מושווים ב-[bookNameAcronymForm] בלבד.
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

/// צורת ההשוואה בין שאילתה לכינוי: [bookNameSpellingForm] בלי "על" שבין שתי
/// מילים — כינויים נשמרו פעם "רשבא על בק" ופעם "רשבא בב" (#5599).
String bookNameAcronymForm(String text) {
  final t = bookNameSpellingForm(text);
  return t.contains(' על ') ? t.replaceAll(' על ', ' ') : t;
}

const int _vav = 0x05D5;
const int _yod = 0x05D9;

/// כתיב מלא וחסר של מילה בשם ספר (שרש/שורש, תפלה/תפילה, עוקצים/עוקצין): ו או
/// י אחת נוספת בפנים המילה. לכותרות בלבד — בכותרות הפנימיות "דיינים" אינו "דינים".
bool isBookTitleSpellingVariant(String a, String b) {
  final bool variant;
  if (a.length == b.length + 1) {
    variant = _hasInsertedVowelLetter(a, 0, b, 0);
  } else if (b.length == a.length + 1) {
    variant = _hasInsertedVowelLetter(b, 0, a, 0);
  } else {
    variant = a.length == b.length && _isFinalYinYimVariant(a, b);
  }
  return variant && !_isSageAcronym(a) && !_isSageAcronym(b);
}

/// ראשי-תיבות של חכם (מהרל/מהריל, רדבז/רידבז) — אנשים שונים, לא כתיב.
bool _isSageAcronym(String word) =>
    sagesTakingDefiniteArticle.contains(word) ||
    (word.length > 2 &&
        word.codeUnitAt(0) == 0x05D4 &&
        sagesTakingDefiniteArticle.contains(word.substring(1)));

/// האם [text] פותחת ב-[word] בכתיב מלא או חסר ([isBookTitleSpellingVariant]),
/// אולי אחרי אות שימוש אחת (שורש ב"השרשים"). לא באמצע מילה: שבות אינו "תשובות".
bool startsWithBookTitleSpellingVariant(String text, String word) {
  final n = word.length;
  if (n < 3 || text.isEmpty) return false;
  final maxStart = _isPrefixLetter(text.codeUnitAt(0)) ? 1 : 0;
  for (var s = 0; s <= maxStart; s++) {
    if ((s + n + 1 <= text.length &&
            _hasInsertedVowelLetter(text, s, word, 0, n)) ||
        (n >= 4 &&
            s + n - 1 <= text.length &&
            _hasInsertedVowelLetter(word, 0, text, s, n - 1))) {
      return !_isSageAcronym(word) && !_isSageAcronym(text);
    }
  }
  return false;
}

/// ו, ה, ב, כ, ל, מ, ש.
bool _isPrefixLetter(int c) =>
    c == _vav ||
    c == 0x05D4 ||
    c == 0x05D1 ||
    c == 0x05DB ||
    c == 0x05DC ||
    c == 0x05DE ||
    c == 0x05E9;

/// האם [longer] (מ-[ls], באורך n+1) הוא [shorter] (מ-[ss], באורך n) בתוספת
/// ו/י אחת בפנים המילה, בהגבלות שלהלן.
bool _hasInsertedVowelLetter(
  String longer,
  int ls,
  String shorter,
  int ss, [
  int? shorterLength,
]) {
  final n = shorterLength ?? shorter.length;
  if (n < 3) return false;
  var k = 0;
  while (k < n && longer.codeUnitAt(ls + k) == shorter.codeUnitAt(ss + k)) {
    k++;
  }
  for (var j = k; j < n; j++) {
    if (longer.codeUnitAt(ls + j + 1) != shorter.codeUnitAt(ss + j)) {
      return false;
    }
  }
  final c = longer.codeUnitAt(ls + k);
  if (c != _vav && c != _yod) return false;
  final last = longer.codeUnitAt(ls + n);
  // ברצף אותיות זהות (מצות/מצוות) כל אחת מהן יכולה להיות הנוספת.
  for (var p = k; p >= 1 && longer.codeUnitAt(ls + p) == c; p--) {
    if (p == n) continue;
    // ו/י לפני ה סופית עיצורית (מצה/מצוה), ו לפני ת סופית — יחיד/רבים (ברכת/ברכות).
    if (p == n - 1 && (last == 0x05D4 || (c == _vav && last == 0x05EA))) {
      continue;
    }
    // במילה בת שלוש רק ו אחרי האות הראשונה (כהן/כוהן; שבת/שבות, חות/חיות).
    if (n == 3 && (p != 1 || c != _vav)) continue;
    return true;
  }
  return false;
}

/// ־ים/־ין בסוף מילה (עוקצים/עוקצין).
bool _isFinalYinYimVariant(String a, String b) {
  final n = a.length;
  if (n < 5 || a.codeUnitAt(n - 2) != _yod) return false;
  final x = a.codeUnitAt(n - 1);
  final y = b.codeUnitAt(n - 1);
  if (!((x == 0x05DD && y == 0x05DF) || (x == 0x05DF && y == 0x05DD))) {
    return false;
  }
  for (var i = 0; i < n - 2; i++) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) return false;
  }
  return b.codeUnitAt(n - 2) == _yod;
}

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
  var start = 0;
  for (var i = 0; i <= raw.length; i++) {
    if (i < raw.length && !_isWordSeparator(raw.codeUnitAt(i))) continue;
    if (_hasInnerQuote(raw, start, i)) {
      final n = normalize(raw.substring(start, i));
      if (n.isNotEmpty && !n.contains(' ')) out.add(n);
    }
    start = i + 1;
  }
  return out;
}

bool _hasInnerQuote(String text, int start, int end) {
  for (var i = start + 1; i < end - 1; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x22 || c == 0x27 || c == 0x05F3 || c == 0x05F4) return true;
  }
  return false;
}

/// `[\s,.:;()\[\]־-]` של RegExp, בלי לפצל כל כינוי בטעינה.
bool _isWordSeparator(int c) => switch (c) {
  0x09 || 0x0A || 0x0B || 0x0C || 0x0D || 0x20 => true,
  0x2C || 0x2E || 0x3A || 0x3B || 0x28 || 0x29 || 0x5B || 0x5D => true,
  0x2D || 0x05BE || 0xA0 || 0x1680 || 0x2028 || 0x2029 || 0x202F => true,
  0x205F || 0x3000 || 0xFEFF => true,
  _ => c >= 0x2000 && c <= 0x200A,
};
