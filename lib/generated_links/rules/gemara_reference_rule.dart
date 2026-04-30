import 'package:otzaria/generated_links/rules/generated_link_rule.dart';

/// כלל לזיהוי מראי מקומות לגמרא בבלית בתוך שורות טקסט.
///
/// תומך בתבניות:
/// - ברכות ב.
/// - ברכות ב:
/// - ברכות ב א / ברכות ב ב
/// - ברכות דף ב ע"א
/// - בברכות / דברכות / מברכות / לברכות / כברכות / שברכות + דף + עמוד
class GemaraReferenceRule implements GeneratedLinkRule {
  @override
  String get id => 'gemara.reference.v1';

  @override
  int get version => 3;

  /// שם מסכת קנוני → מספר הדף האחרון שלה.
  static const Map<String, int> _tractateMaxDaf = {
    'ברכות': 64,
    'שבת': 157,
    'עירובין': 105,
    'פסחים': 121,
    'שקלים': 22,
    'יומא': 88,
    'סוכה': 56,
    'ביצה': 40,
    'ראש השנה': 35,
    'תענית': 31,
    'מגילה': 32,
    'מועד קטן': 29,
    'חגיגה': 27,
    'יבמות': 122,
    'כתובות': 112,
    'נדרים': 91,
    'נזיר': 66,
    'סוטה': 49,
    'גיטין': 90,
    'קידושין': 82,
    'בבא קמא': 119,
    'בבא מציעא': 119,
    'בבא בתרא': 176,
    'סנהדרין': 113,
    'מכות': 24,
    'שבועות': 49,
    'עבודה זרה': 76,
    'הוריות': 14,
    'זבחים': 120,
    'מנחות': 110,
    'חולין': 142,
    'בכורות': 61,
    'ערכין': 34,
    'תמורה': 34,
    'כריתות': 28,
    'מעילה': 22,
    'תמיד': 10,
    'נדה': 73,
  };

  /// כינוי אורתוגרפי → שם קנוני (כפי שמופיע בקטלוג).
  ///
  /// כינויים כלולים בביטוי הרגולרי לצורך זיהוי, אך [_resolveTractateName]
  /// מנרמל את השם שיצא ל-[DetectedReference.targetBookTitle].
  static const Map<String, String> _tractateAliases = {
    'נידה': 'נדה',
  };

  /// מחזיר שם קנוני של מסכת; אם לא כינוי — מחזיר כפי שהוכנס.
  static String _resolveTractateName(String raw) =>
      _tractateAliases[raw] ?? raw;

  static const Map<String, int> _letterValues = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ל': 30,
    'מ': 40,
    'נ': 50,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'צ': 90,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };

  /// ממיר מחרוזת אותיות עבריות למספר שלם.
  ///
  /// מחזיר null אם יש אות לא מוכרת או אם מבנה הגימטריה אינו תקין. זה מונע
  /// false positives כמו "תענית בהב" או "ברכות גכ".
  static int? hebrewToInt(String s) {
    final cleaned = removeGershayim(s);

    var result = 0;
    int? previousCategory;
    final seenLetters = <String>{};

    for (var i = 0; i < cleaned.length; i++) {
      final suffix = cleaned.substring(i);
      if ((suffix == 'טו' || suffix == 'טז') &&
          (previousCategory == null || previousCategory == 100)) {
        result += suffix == 'טו' ? 15 : 16;
        return result;
      }

      final char = cleaned[i];
      final val = _letterValues[char];
      if (val == null) return null;

      if (!seenLetters.add(char)) return null;

      final category = val >= 100
          ? 100
          : val >= 10
              ? 10
              : 1;
      if (previousCategory != null && category >= previousCategory) {
        return null;
      }

      previousCategory = category;
      result += val;
    }
    return result > 0 ? result : null;
  }

  /// מחזיר מספר דף מקסימלי למסכת, או null אם המסכת לא מוכרת.
  static int? maxDafForTractate(String tractate) => _tractateMaxDaf[tractate];

  /// מנרמל את סימן העמוד לאחת מהאפשרויות: 'א', 'ב', או null.
  static String? normalizeAmud(String? raw) {
    if (raw == null) return null;
    final t = raw
        .replaceAll(RegExp(r'(?:סוף|ריש|ראש|תחילת)'), '')
        .replaceAll(RegExp(r'[\s,;]'), '')
        .trim();
    if (t == '.' || t == 'א' || t == 'ע"א' || t == 'ע״א') return 'א';
    if (t == ':' || t == 'ב' || t == 'ע"ב' || t == 'ע״ב') return 'ב';
    return null;
  }

  /// מסיר גרשיים/גרש ממספר דף עברי.
  static String removeGershayim(String s) => s
      .replaceAll('"', '')
      .replaceAll('״', '')
      .replaceAll('׳', '')
      .replaceAll("'", '');

  static final RegExp _pattern = _buildPattern();
  static final RegExp _relativePattern = _buildRelativePattern();

  static RegExp _buildPattern() {
    // שמות קנוניים + כינויים, ממוינים לפי אורך יורד (longest-first)
    final allNames = <String>{
      ..._tractateMaxDaf.keys,
      ..._tractateAliases.keys,
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final tractateAlt = allNames.map(RegExp.escape).join('|');

    // טווח אותיות עבריות: א-ת
    const hb = 'א-ת';
    // אותיות שימוש: ב, ד, מ, ל, כ, ש
    const pfx = 'בדמלכש';
    const gersh = '"״';
    const brackets = r'[(\[]';
    const closeBrackets = r'[)\]]';

    return RegExp(
      '(?<![$hb])' // גבול תחילה: לא קדמה אות עברית
      '(?:$brackets)?' // סוגר פותח אופציונלי
      '(?:[$pfx])?' // תחילית אות שימוש (לא-לוכדת)
      '(?:מסכת\\s+)?' // מסכת (אופציונלי, לא-לוכד)
      '($tractateAlt)' // קבוצה 1: שם מסכת
      '(?=\\s|$brackets)'
      '\\s*'
      '(?:$brackets)?' // סוגר לפני "דף", למשל: שבת (דף מז)
      '\\s*'
      '(?:דף\\s+)?' // דף (אופציונלי, לא-לוכד)
      '([$hb]{1,3}(?:[$gersh][$hb]{1,3})?)' // קבוצה 2: דף, כולל כ"ב/קנ"ז
      // לא להמשיך אם יש אחריו אות עברית או גרש
      "(?![$hb'׳\"״])"
      '(' // קבוצה 3: עמוד (אופציונלי)
      '[.:]' //   נקודה או נקודתיים צמודות לדף
      '|\\s*[,;]\\s*(?:' //   פסיק/נקודה-פסיק + עמוד
      'ע[$gersh][אב]'
      '|[אב](?![$hb])'
      ')'
      '|\\s+(?:' //   או רווח +
      'ע[$gersh][אב]' //   ע"א / ע"ב / ע״א / ע״ב
      '|[אב](?![$hb])' //   א/ב שאחריהם לא אות עברית
      ')'
      ')?'
      '(?:$closeBrackets)?',
      unicode: true,
    );
  }

  static RegExp _buildRelativePattern() {
    const hb = 'א-ת';
    const gersh = '"״';
    const brackets = r'[(\[]';
    const closeBrackets = r'[)\]]';

    return RegExp(
      '(?<![$hb])'
      '(לעיל|לקמן)'
      '\\s*'
      '(?:$brackets)?'
      '\\s*'
      '(?:דף\\s+)?'
      '([$hb]{1,3}(?:[$gersh][$hb]{1,3})?)'
      "(?![$hb'׳\"״])"
      '('
      '[.:]'
      '|\\s*[,;]\\s*(?:'
      'ע[$gersh][אב]'
      '|[אב](?![$hb])'
      ')'
      '|\\s+(?:(?:סוף|ריש|ראש|תחילת)\\s+)?(?:'
      'ע[$gersh][אב]'
      '|[אב](?![$hb])'
      ')'
      ')?'
      '(?:$closeBrackets)?',
      unicode: true,
    );
  }

  @override
  Future<List<DetectedReference>> detect(
    GeneratedLinkRuleContext context,
    List<String> lines,
    LineRange lineRange,
  ) async {
    final results = <DetectedReference>[];

    for (var i = lineRange.start; i <= lineRange.end && i < lines.length; i++) {
      for (final match in _pattern.allMatches(lines[i])) {
        final rawTractate = match.group(1)!;
        final tractate = _resolveTractateName(rawTractate); // שם קנוני
        final dafStr = removeGershayim(match.group(2)!);
        final amudRaw = match.group(3);

        // אימות מספר הדף לפי השם הקנוני
        final dafNum = hebrewToInt(dafStr);
        if (dafNum == null || dafNum < 2) continue;
        final maxDaf = _tractateMaxDaf[tractate];
        if (maxDaf == null || dafNum > maxDaf) continue;

        final amud = normalizeAmud(amudRaw);
        final targetRefText = amud != null ? '$dafStr $amud' : dafStr;

        results.add(DetectedReference(
          sourceLineIndex: i,
          start: match.start,
          end: match.end,
          matchedText: match.group(0)!,
          targetBookTitle: tractate, // תמיד שם קנוני
          targetRefText: targetRefText,
          ruleId: id,
          confidence: 0.9,
        ));
      }

      for (final match in _relativePattern.allMatches(lines[i])) {
        final dafStr = removeGershayim(match.group(2)!);
        final amudRaw = match.group(3);

        final dafNum = hebrewToInt(dafStr);
        if (dafNum == null || dafNum < 2) continue;

        final maxDaf = _tractateMaxDaf[context.sourceBookTitle];
        if (maxDaf != null && dafNum > maxDaf) continue;

        final amud = normalizeAmud(amudRaw);
        final targetRefText = amud != null ? '$dafStr $amud' : dafStr;

        results.add(DetectedReference(
          sourceLineIndex: i,
          start: match.start,
          end: match.end,
          matchedText: match.group(0)!,
          targetBookTitle: context.sourceBookTitle,
          targetRefText: targetRefText,
          ruleId: id,
          confidence: 0.78,
        ));
      }
    }

    return results;
  }
}
