import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

/// מקור-אמת יחיד לתבנית ההתאמה הליטרלית של החיפוש בתוך ספר.
///
/// גם מציאת התוצאות (`section_search_utils`), גם ההדגשה בסרגל התוצאות
/// (`SnippetBuilder.highlightLiteral`) וגם חישוב מיקום ההתאמה משתמשים באותה
/// תבנית מהמנוע (`generateLiteralHighlightPattern`), כך שלא ייתכן פער ביניהם.

final RegExp _whitespaceRun = RegExp(r'\s+');

/// תבנית ליטרלית: מקור המחרוזת (לשליחה ל-isolate worker) והרגקס המקומפל
/// (לשימוש ב-isolate הראשי).
class LiteralSearchPattern {
  const LiteralSearchPattern(this.source, this.regExp);

  /// מחרוזת התבנית כפי שבנה אותה המנוע — ניתנת לשליחה בין isolate-ים.
  final String source;

  /// הרגקס המקומפל מ-[source].
  final RegExp regExp;
}

/// מנרמל שאילתה זהה ל-[cleanLineForSearch] של התוכן: מסיר ניקוד וממיר
/// מפרידים (מקף עברי/פסק) לרווח, ואז מכווץ רצפי רווח. חובה שיהיה זהה
/// לניקוי התוכן — אחרת שאילתה עם מקף ("אשר־שמע") לא תתאים לתוכן הנקי
/// ("אשר שמע"), וגם שאילתה מנוקדת ("הֲרֵעֹתִי") לא תתאים לטקסט ללא ניקוד.
String normalizeLiteralQuery(String query) => _collapse(query).trim();

String _collapse(String query) =>
    utils.removeVolwels(query).replaceAll(_whitespaceRun, ' ');

/// רווח בתחילת/בסוף [query]: בהתאמה חלקית הוא מעגן את ההתאמה לתחילת/סוף מילה.
({bool start, bool end}) literalQueryWordEdges(String query) {
  final collapsed = _collapse(query);
  if (collapsed.trim().isEmpty) return (start: false, end: false);
  return (start: collapsed.startsWith(' '), end: collapsed.endsWith(' '));
}

/// עטיפת גבול-המילה שהמנוע מוסיף סביב הביטוי:
/// `(?<!גבול לפני)(?:ביטוי)(?!גבול אחרי)`. מחזירה את הביטוי בלבד, או `null`
/// אם המבנה אינו מזוהה — ואז החיפוש נשאר בהתאמת מילה שלמה במקום לסרוק
/// בתבנית חתוכה שגויה.
String? stripWordBoundaryWrapper(String source) =>
    _splitWordBoundaryWrapper(source)?.phrase;

({String before, String phrase, String after})? _splitWordBoundaryWrapper(
  String source,
) {
  if (!source.startsWith('(?<!')) return null;

  // מחלקות התווים שבעטיפה אינן מכילות סוגריים, ולכן הסוגר המאזן את הפותח
  // נמצא בספירת עומק פשוטה.
  var depth = 0;
  var lookbehindEnd = -1;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
      if (depth == 0) {
        lookbehindEnd = i;
        break;
      }
    }
  }
  if (lookbehindEnd < 0) return null;

  // הגבול הסוגר הוא ה-`(?!` האחרון: `(?!` נוסף מופיע בתוך תבנית תג ה-HTML
  // שבמפריד בין מילות השאילתה, והוא תמיד לפניו.
  final lookaheadStart = source.lastIndexOf('(?!');
  if (lookaheadStart <= lookbehindEnd) return null;

  final phrase = source.substring(lookbehindEnd + 1, lookaheadStart);
  if (phrase.isEmpty) return null;
  return (
    before: source.substring(0, lookbehindEnd + 1),
    phrase: phrase,
    after: source.substring(lookaheadStart),
  );
}

/// [source] שבודקת את הביטוי לפני גבול-המילה שלפניו. ה-lookbehind באורך משתנה
/// יקר בכל מיקום, והביטוי נכשל מהר ברובם; ההתאמות זהות.
String _phraseFirst(String source) {
  final phrase = stripWordBoundaryWrapper(source);
  return phrase == null ? source : '(?=$phrase)$source';
}

final Map<String, LiteralSearchPattern?> _cache = {};

/// אורך השאילתה המינימלי להתאמה בתוך מילה.
const int _minPartialMatchChars = 2;

/// האם החיפוש הליטרלי ל-[query] מתאים גם בתוך מילה. ההדגשה בגוף הספר חייבת
/// לקבל אותו ערך, אחרת אות בודדת מודגשת בתוך מילים שהחיפוש לא מצא.
bool literalPartialWordMatch(String query, {required bool wholeWord}) =>
    !wholeWord && normalizeLiteralQuery(query).length >= _minPartialMatchChars;

const Map<String, String> _finalToRegularLetter = {
  'ך': 'כ',
  'ם': 'מ',
  'ן': 'נ',
  'ף': 'פ',
  'ץ': 'צ',
};

/// הביטוי בלי גבולות המילה, חוץ מהקצוות שב-[edges]. אות סופית בסוף שאילתה
/// שסופה פתוח מתאימה גם לצורה הרגילה: "מלך" מוצא את "המלכים".
String? _partialPhrase(
  String q,
  String source,
  ({bool start, bool end}) edges,
) {
  final parts = _splitWordBoundaryWrapper(source);
  if (parts == null) return null;
  var phrase = parts.phrase;
  final regular = edges.end ? null : _finalToRegularLetter[q[q.length - 1]];
  if (regular != null) {
    final altSource = _literalSource('${q.substring(0, q.length - 1)}$regular');
    final altPhrase = altSource == null
        ? null
        : stripWordBoundaryWrapper(altSource);
    if (altPhrase != null) phrase = '(?:$phrase|$altPhrase)';
  }
  if (!edges.start) return edges.end ? '$phrase${parts.after}' : phrase;
  return '(?=$phrase)${parts.before}$phrase${edges.end ? parts.after : ''}';
}

/// תבנית המנוע ל-[query], שבה כל מופע של מילת "יקוק" (או "ידוד") מתאים גם
/// לשם הוי"ה שבתוכן המקורי — כל מופע בנפרד, לפי אותו זיהוי של החיפוש הכללי.
String? _literalSource(String query) {
  var source = engine.generateLiteralHighlightPattern(query: query);
  for (final placeholderWord in utils.holyNamePlaceholders) {
    if (source == null) return null;
    source = _withHolyNameFor(query, source, placeholderWord);
  }
  return source;
}

/// [source] שבה כל מופע של [placeholderWord] שהוא מילה בפני עצמה מתאים גם
/// לשם הוי"ה.
String _withHolyNameFor(String query, String source, String placeholderWord) {
  if (!query.contains(placeholderWord)) return source;
  // מיקומי המקור משמרים את המיפוי גם כשהטוקנייזר משמיט כתיב שבסוגריים.
  final expandableOffsets = {
    for (final span in engine.queryWordSpans(query: query))
      if (utils.holyNameForPlaceholderWord(span.word) != null)
        for (final match in placeholderWord.allMatches(
          query.substring(span.start, span.end),
        ))
          span.start + match.start,
  };
  final isPlaceholderWord = [
    for (final match in placeholderWord.allMatches(query))
      expandableOffsets.contains(match.start),
  ];
  final placeholder = _wordPhrase(placeholderWord);
  final name = _wordPhrase(utils.holyNameForPlaceholderWord(placeholderWord)!);
  final parts = placeholder == null
      ? const <String>[]
      : source.split(placeholder);
  if (name == null || parts.length - 1 != isPlaceholderWord.length) {
    return source;
  }
  final buffer = StringBuffer(parts.first);
  for (var i = 0; i < isPlaceholderWord.length; i++) {
    buffer.write(isPlaceholderWord[i] ? '(?:$placeholder|$name)' : placeholder);
    buffer.write(parts[i + 1]);
  }
  return buffer.toString();
}

/// תבנית המילה בלי גבולות ובלי עטיפת `(?:…)` של הביטוי — כפי שהיא מופיעה
/// בתוך תבנית של שאילתה ארוכה יותר.
String? _wordPhrase(String word) {
  final source = engine.generateLiteralHighlightPattern(query: word);
  final phrase = source == null ? null : stripWordBoundaryWrapper(source);
  if (phrase == null || !phrase.startsWith('(?:') || !phrase.endsWith(')')) {
    return null;
  }
  return phrase.substring(3, phrase.length - 1);
}

/// בונה (עם קאש) תבנית ליטרלית לשאילתה, לאחר נרמול.
/// מחזיר `null` לשאילתה ריקה/רק-רווחים.
///
/// [wholeWord] `false` מסיר את גבולות המילה, כך ש"שמים" מתאים גם בתוך "השמים";
/// רווח בקצה השאילתה משאיר את הגבול שבאותו צד (ראו [literalQueryWordEdges]).
/// שאילתה של תו אחד נשארת במילים שלמות: בתוך מילה היא מתאימה כמעט לכל דבר.
///
/// חובה להיקרא ב-isolate הראשי בלבד — קורא למנוע (flutter_rust_bridge)
/// שקשור אליו. ב-isolate worker יש לקמפל דרך [compileLiteralPattern].
LiteralSearchPattern? buildLiteralPattern(
  String query, {
  bool wholeWord = true,
}) {
  final q = normalizeLiteralQuery(query);
  final partial = literalPartialWordMatch(query, wholeWord: wholeWord);
  final edges = partial
      ? literalQueryWordEdges(query)
      : (start: false, end: false);
  final cacheKey =
      '${partial ? 'p' : 'w'}${edges.start ? '<' : ''}${edges.end ? '>' : ''}|$q';
  if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

  // בונים לפני עדכון ה-cache: אם המנוע זורק, ה-cache נשאר עקבי ולא מקבל
  // רשומה חלקית לשאילתה החדשה.
  LiteralSearchPattern? result;
  if (q.isNotEmpty) {
    final source = _literalSource(q);
    if (source != null) {
      final effective = partial
          ? (_partialPhrase(q, source, edges) ?? source)
          : _phraseFirst(source);
      try {
        result = LiteralSearchPattern(
          effective,
          compileLiteralPattern(effective),
        );
      } on FormatException {
        // תבנית חתוכה שאינה מתקמפלת — נסיגה לתבנית המלאה של המנוע.
        result = LiteralSearchPattern(source, compileLiteralPattern(source));
      }
    }
  }

  if (_cache.length >= 16) _cache.clear();
  _cache[cacheKey] = result;
  return result;
}

/// מקמפל תבנית ליטרלית ממקור מחרוזת. בטוח ל-isolate worker — אינו קורא למנוע.
RegExp compileLiteralPattern(String source) =>
    RegExp(source, caseSensitive: false, unicode: true);
