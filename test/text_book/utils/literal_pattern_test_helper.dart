import 'package:otzaria/search/utils/literal_search_pattern.dart';

/// בונה תבנית ליטרלית שקולה בדיוק לזו של המנוע (`build_literal_pattern`),
/// ב-Dart טהור — הבדיקות אינן יכולות לקרוא למנוע (flutter_rust_bridge לא
/// מאותחל), ולכן מזריקות תבנית זו דרך ה-seam.
///
/// מחלקות התווים לקוחות מ-display_highlight.rs ונבנות מנקודות-קוד (מספרים)
/// ולא מתווים ממשיים — סימני שילוב/צורות מורכבות מסודרים-מחדש כשהם מופיעים
/// כתווים בקוד מקור, ולכן בונים אותם בזמן ריצה מ-`String.fromCharCode`.
String _r(int a, int b) =>
    '${String.fromCharCode(a)}-${String.fromCharCode(b)}';
String _c(int code) => String.fromCharCode(code);

// [̀-֑ͯ-ׇֽֿׁׂׅׄ]*
// מחלקת הסימנים הצמודים ללא כמת (ATTACHED_MARKS_SET במנוע).
final String _attachedMarksSet =
    '[${_r(0x0300, 0x036F)}${_r(0x0591, 0x05BD)}'
    '${_c(0x05BF)}${_c(0x05C1)}${_c(0x05C2)}${_c(0x05C4)}${_c(0x05C5)}'
    '${_c(0x05C7)}]';

final String _attachedMarks = '$_attachedMarksSet*';

// א-תװ-ײיִ-ﭏ  (U+05D0-05EA, U+05F0-05F2, U+FB1D-FB4F)
final String _hebrewLetterClass =
    '${_r(0x05D0, 0x05EA)}${_r(0x05F0, 0x05F2)}${_r(0xFB1D, 0xFB4F)}';

// ['׳‘’]
final String _gereshClass =
    '[${_c(0x27)}${_c(0x05F3)}${_c(0x2018)}${_c(0x2019)}]';

// (?:["״“”]|['׳‘’]{2})
final String _gershayimClass =
    '(?:[${_c(0x22)}${_c(0x05F4)}${_c(0x201C)}${_c(0x201D)}]|'
    '[${_c(0x27)}${_c(0x05F3)}${_c(0x2018)}${_c(0x2019)}]{2})';

const String _regexMetaChars = r'\.+*?()|[]{}^$';

// מפריד מילים [\s־׀|]+ — סובל גם מקף/פסק, כמו במנוע.
final String _wordSeparator = '[\\s${_c(0x05BE)}${_c(0x05C0)}|]+';

bool _isQuoteCode(int code) =>
    code == 0x22 ||
    code == 0x05F4 ||
    code == 0x201C ||
    code == 0x201D ||
    code == 0x27 ||
    code == 0x05F3 ||
    code == 0x2018 ||
    code == 0x2019;

bool _isGershayimCode(int code) =>
    code == 0x22 || code == 0x05F4 || code == 0x201C || code == 0x201D;

// fragment גרש/גרשיים לגבול (quote_boundary_fragment במנוע): רצף-ציטוט
// חוקי הוא Q = גרשיים | גרש אחד/שניים, ורצפים חוקיים המופרדים בסימנים
// צמודים משתרשרים — Q (סימן+ Q)*. רצפים צמודים לא-חוקיים ("", ''', '")
// נשארים גבול.
final String _quoteBoundaryFragment = () {
  final g2 = '"${_c(0x05F4)}${_c(0x201C)}${_c(0x201D)}';
  final g1 = "'${_c(0x05F3)}${_c(0x2018)}${_c(0x2019)}";
  final q = '(?:[$g2]|[$g1]{1,2})';
  return '(?:$q(?:$_attachedMarksSet+$q)*)';
}();

void _writeQuoteClass(StringBuffer buf, int code) {
  if (code == 0x22 || code == 0x05F4 || code == 0x201C || code == 0x201D) {
    buf.write(_gershayimClass);
  } else {
    buf.write(_gereshClass);
  }
}

String _charwisePattern(String word, bool isLast) {
  final len = word.length;
  // רק במילה האחרונה, ורק גרשיים (לא גרש): נגרר הופך ל-lookahead.
  var coreLen = len;
  if (isLast) {
    while (coreLen > 0 && _isGershayimCode(word.codeUnitAt(coreLen - 1))) {
      coreLen--;
    }
    if (coreLen == 0) coreLen = len;
  }

  final buf = StringBuffer();
  for (var i = 0; i < coreLen; i++) {
    final code = word.codeUnitAt(i);
    if (_isQuoteCode(code)) {
      _writeQuoteClass(buf, code);
    } else {
      final ch = word[i];
      if (_regexMetaChars.contains(ch)) buf.write('\\');
      buf.write(ch);
    }
    buf.write(_attachedMarks);
  }
  if (coreLen < len) {
    buf.write('(?=');
    for (var i = coreLen; i < len; i++) {
      _writeQuoteClass(buf, word.codeUnitAt(i));
    }
    buf.write(')');
  }
  return buf.toString();
}

/// מקור מחרוזת התבנית הליטרלית לשאילתה [query] (מנורמלת קודם).
String literalPatternSource(String query) {
  final normalized = normalizeLiteralQuery(query);
  final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();
  final last = words.length - 1;
  final phrase = [
    for (var i = 0; i < words.length; i++)
      _charwisePattern(words[i], i == last),
  ].join(_wordSeparator);
  // גבול תלוי-הקשר כמו במנוע: גרש/גרשיים בין אותיות (רש״י) אינו גבול,
  // וה-lookahead מדלג בעצמו על ניקוד שנותר מ-backtracking של [ניקוד]*.
  return '(?<![$_hebrewLetterClass]$_attachedMarks'
      '$_quoteBoundaryFragment?$_attachedMarks)'
      '(?:$phrase)'
      '(?!$_attachedMarks$_quoteBoundaryFragment?$_attachedMarks'
      '[$_hebrewLetterClass])';
}

/// תבנית ליטרלית מקומפלת לשאילתה [query].
RegExp literalPattern(String query) =>
    compileLiteralPattern(literalPatternSource(query));
