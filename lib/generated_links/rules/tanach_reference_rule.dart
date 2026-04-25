import 'package:otzaria/generated_links/rules/generated_link_rule.dart';

/// כלל לזיהוי מראי מקומות לתנ"ך בתוך שורות טקסט.
///
/// תבניות נתמכות:
/// - `(בראשית א, א)` / `(בראשית א א)` / `[בראשית א, א]`
/// - `בראשית פרק א פסוק א`
/// - ראשי תיבות: שמ"א, שמ"ב, מל"א, מל"ב, דה"א, דה"ב
///
/// הפניות חופשיות ללא סוגריים (`בראשית א א`) לא נתמכות בשלב ראשון
/// למניעת false positives.
class TanachReferenceRule implements GeneratedLinkRule {
  @override
  String get id => 'tanach.reference.v1';

  @override
  int get version => 1;

  /// שם ספר → מספר פרקים מרבי.
  static const Map<String, int> _bookMaxChapters = {
    'בראשית': 50, 'שמות': 40, 'ויקרא': 27, 'במדבר': 36, 'דברים': 34,
    'יהושע': 24, 'שופטים': 21, 'רות': 4,
    'שמואל א': 31, 'שמואל ב': 24,
    'מלכים א': 22, 'מלכים ב': 25,
    'ישעיהו': 66, 'ירמיהו': 52, 'יחזקאל': 48,
    'הושע': 14, 'יואל': 4, 'עמוס': 9, 'עובדיה': 1,
    'יונה': 4, 'מיכה': 7, 'נחום': 3, 'חבקוק': 3,
    'צפניה': 3, 'חגי': 2, 'זכריה': 14, 'מלאכי': 3,
    'תהלים': 150, 'משלי': 31, 'איוב': 42,
    'שיר השירים': 8, 'קהלת': 12, 'איכה': 5,
    'אסתר': 10, 'דניאל': 12, 'עזרא': 10, 'נחמיה': 13,
    'דברי הימים א': 29, 'דברי הימים ב': 36,
  };

  /// ראשי תיבות → שם מלא.
  static const Map<String, String> _abbreviations = {
    'שמ"א': 'שמואל א', 'שמ״א': 'שמואל א',
    'שמ"ב': 'שמואל ב', 'שמ״ב': 'שמואל ב',
    'מל"א': 'מלכים א', 'מל״א': 'מלכים א',
    'מל"ב': 'מלכים ב', 'מל״ב': 'מלכים ב',
    'דה"א': 'דברי הימים א', 'דה״א': 'דברי הימים א',
    'דה"ב': 'דברי הימים ב', 'דה״ב': 'דברי הימים ב',
  };

  /// כינויי כתיב חלופי → שם קנוני (כפי שמופיע ב-[_bookMaxChapters]).
  static const Map<String, String> _spellingAliases = {
    'עבדיה': 'עובדיה',    // כתיב ללא ו' (נפוץ בטקסטים ישנים)
    'שה"ש': 'שיר השירים',
    'שה״ש': 'שיר השירים',
  };

  static final RegExp _bracketedPattern = _buildBracketedPattern();
  static final RegExp _explicitPattern = _buildExplicitPattern();

  static RegExp _buildBracketedPattern() {
    final bookAlt = _buildBookAlternation();
    const numPat = r'(?:\d+|[א-ת]{1,3})';
    // raw strings לסביבת הסוגריים כדי לא לבלבל Dart עם escape sequences
    return RegExp(
      r'([([])'    // קבוצה 1: ( או [
      '($bookAlt)'
      r'\s+'
      '($numPat)'  // קבוצה 3: פרק
      r'(?:,\s*|\s+)'
      '($numPat)'  // קבוצה 4: פסוק
      r'([)\]])',  // קבוצה 5: ) או ]
      unicode: true,
    );
  }

  static RegExp _buildExplicitPattern() {
    final bookAlt = _buildBookAlternation();
    const numPat = r'(?:\d+|[א-ת]{1,3})';
    return RegExp(
      r'(?<![א-ת])'
      '($bookAlt)'
      r'\s+פרק\s+'
      '($numPat)'
      r'\s+פסוק\s+'
      '($numPat)',
      unicode: true,
    );
  }

  static String _buildBookAlternation() {
    final all = <String>{
      ..._bookMaxChapters.keys,
      ..._abbreviations.keys,
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return all.map(RegExp.escape).join('|');
  }

  /// ממיר מחרוזת מספר (ספרות ערביות או אותיות עבריות) למספר שלם.
  static int? parseNumber(String s) {
    final arabic = int.tryParse(s);
    if (arabic != null) return arabic;
    return _hebrewToInt(s);
  }

  /// מחזיר מספר פרקים מרבי לספר, או null אם הספר לא מוכר.
  static int? maxChaptersForBook(String book) => _bookMaxChapters[book];

  static const Map<String, int> _letterValues = {
    'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6,
    'ז': 7, 'ח': 8, 'ט': 9, 'י': 10, 'כ': 20, 'ל': 30,
    'מ': 40, 'נ': 50, 'ס': 60, 'ע': 70, 'פ': 80, 'צ': 90,
    'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
  };

  static int? _hebrewToInt(String s) {
    var result = 0;
    for (var i = 0; i < s.length; i++) {
      final val = _letterValues[s[i]];
      if (val == null) return null;
      result += val;
    }
    return result > 0 ? result : null;
  }

  /// פותר ראשי תיבות וכינויי כתיב לשם ספר קנוני.
  static String _resolveBookName(String raw) =>
      _abbreviations[raw] ?? _spellingAliases[raw] ?? raw;

  /// בונה targetRefText בפורמט אחיד: `{ספר} {פרק} {פסוק}`.
  static String _buildRefText(String book, String chapter, String verse) =>
      '$book $chapter $verse';

  /// בודק תקינות פרק (פסוקים אינם מוגבלים בשלב ראשון).
  static bool _isValidRef(String book, int chapter) {
    final maxCh = _bookMaxChapters[book];
    if (maxCh == null) return false;
    return chapter >= 1 && chapter <= maxCh;
  }

  @override
  Future<List<DetectedReference>> detect(
    GeneratedLinkRuleContext context,
    List<String> lines,
    LineRange lineRange,
  ) async {
    final results = <DetectedReference>[];

    for (var i = lineRange.start; i <= lineRange.end && i < lines.length; i++) {
      final line = lines[i];

      // תבנית סוגריים: (ספר פרק, פסוק) / [ספר פרק פסוק]
      for (final match in _bracketedPattern.allMatches(line)) {
        final open = match.group(1)!;
        final close = match.group(5)!;
        if (!_bracketsMatch(open, close)) continue;

        final rawBook = match.group(2)!;
        final chStr = match.group(3)!;
        final vsStr = match.group(4)!;

        final book = _resolveBookName(rawBook);
        final chapter = parseNumber(chStr);
        if (chapter == null || !_isValidRef(book, chapter)) continue;

        results.add(DetectedReference(
          sourceLineIndex: i,
          start: match.start,
          end: match.end,
          matchedText: match.group(0)!,
          targetBookTitle: book,
          targetRefText: _buildRefText(book, chStr, vsStr),
          ruleId: id,
          confidence: 0.92,
        ));
      }

      // תבנית מפורשת: ספר פרק X פסוק Y
      for (final match in _explicitPattern.allMatches(line)) {
        final rawBook = match.group(1)!;
        final chStr = match.group(2)!;
        final vsStr = match.group(3)!;

        final book = _resolveBookName(rawBook);
        final chapter = parseNumber(chStr);
        if (chapter == null || !_isValidRef(book, chapter)) continue;

        results.add(DetectedReference(
          sourceLineIndex: i,
          start: match.start,
          end: match.end,
          matchedText: match.group(0)!,
          targetBookTitle: book,
          targetRefText: _buildRefText(book, chStr, vsStr),
          ruleId: id,
          confidence: 0.95,
        ));
      }
    }

    return results;
  }

  static bool _bracketsMatch(String open, String close) =>
      (open == '(' && close == ')') || (open == '[' && close == ']');
}
