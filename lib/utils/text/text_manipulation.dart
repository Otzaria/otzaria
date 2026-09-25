import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/search/models/search_match_policy.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show HighlightPattern, generateHighlightPattern;

/// רגקס להסרת תגי HTML.
final RegExp _htmlStripper = RegExp(r'<[^>]*>');

/// תגי שבירה — מוצגים כמעבר שורה/גבול בלוק ולכן הופכים לרווח ולא נמחקים,
/// אחרת מילים משני צדי `<br>` נדבקות (כמו strip_html_for_indexing במנוע).
final RegExp _breakingTagStripper = RegExp(
  r'</?(?:address|article|aside|blockquote|br|caption|center|dd|div|dl|dt'
  r'|figcaption|figure|footer|h[1-6]|header|hr|li|main|nav|ol|p|pre|section'
  r'|table|tbody|td|tfoot|th|thead|tr|ul)(?:[^>a-zA-Z0-9][^>]*)?>',
  caseSensitive: false,
);

/// ישות HTML — שמית או מספרית (עשרונית/הקסדצימלית).
final RegExp _htmlEntity = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

/// ישויות רווח מפוענחות לרווח רגיל ולא ל-NBSP, כדי שיכווצו ככל רווח אחר.
const Map<String, String> _namedEntities = {
  'nbsp': ' ',
  'thinsp': ' ',
  'ensp': ' ',
  'emsp': ' ',
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'laquo': '«',
  'raquo': '»',
  'middot': '·',
};

/// מפענח ישויות HTML כפי שמנוע ה-HTML מציג אותן; ישות לא מוכרת נמחקת.
String decodeHtmlEntities(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(_htmlEntity, (match) {
    final body = match[1]!;
    if (body.startsWith('#')) {
      final isHex = body[1] == 'x' || body[1] == 'X';
      final code = int.tryParse(
        body.substring(isHex ? 2 : 1),
        radix: isHex ? 16 : 10,
      );
      if (code == null || code < 0x20 || code > 0x10FFFF) return '';
      return String.fromCharCode(code);
    }
    return _namedEntities[body.toLowerCase()] ?? '';
  });
}

/// ממיר ישויות רווח לצורה שההדגשה מזהה, בלי לשנות תגיות או ישויות תוכן.
String normalizeHtmlWhitespaceEntities(String text) {
  return text.replaceAll(
    RegExp(r'&(nbsp|thinsp|ensp|emsp);', caseSensitive: false),
    ' ',
  );
}

/// רגקס להסרת ניקוד וטעמים.
final RegExp _vowelsAndCantillation = RegExp(r'[֑-ׇ]');

/// רגקס להסרת טעמים בלבד.
final RegExp _cantillationOnly = RegExp(r'[֑-֯]');

/// רגקס בסיסי לזיהוי שם הקודש (יהוה) עם ניקוד.
///
/// הסינון של מקרים כמו "ויגביהוהו" מתבצע בקוד, כדי שנוכל להתעלם מסימני
/// ניקוד וטעמים שלפני השם בלי לפספס מקרים כמו "לַֽיהֹוָֽה".
final RegExp _holyName = RegExp(
  r"י([\p{Mn}]*)ה([\p{Mn}]*)ו([\p{Mn}]*)ה([\p{Mn}]*)",
  unicode: true,
);

/// הפענוח אחרי הסרת התגים — אחרת `&lt;b&gt;` היה הופך ל-`<b>` ונמחק כתגית.
/// תגי שבירה הופכים לרווח; תגי inline נמחקים נטו (`מי<b>לה` — מילה אחת).
String stripHtmlIfNeeded(String text) {
  return decodeHtmlEntities(
    text.replaceAll(_breakingTagStripper, ' ').replaceAll(_htmlStripper, ''),
  );
}

/// כמו [stripHtmlIfNeeded], אך ממיר תגי <br> למעבר שורה אמיתי לפני הסרת התגים,
/// כדי שטקסט המוצג ב-Text רגיל ישמור על מבנה השורות במקום להידחס לרצף.
String stripHtmlPreservingBreaks(String text) {
  final withBreaks = text.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  return stripHtmlIfNeeded(withBreaks);
}

String truncate(String text, int length) {
  return text.length > length ? '${text.substring(0, length)}...' : text;
}

String removeVolwels(String s) {
  s = s.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
  return s.replaceAll(_vowelsAndCantillation, '');
}

/// סימני ניקוד בלבד, בלי טעמים: נקודות התנועה, דגש, רפה, נקודות שי"ן/שי"ן
/// ו-U+05C7. מקף, פסק, מתג וסוף פסוק נשארים — הם שייכים לטעמים.
final RegExp _vowelsOnly = RegExp(
  r'[ְ-ׇּֿׁׂׅׄ]',
);

/// מסיר ניקוד בלבד ומשאיר את הטעמים במקומם.
String removeNikudOnly(String s) => s.replaceAll(_vowelsOnly, '');

/// מסיר ניקוד ו/או טעמים לפי שני הדגלים — הכניסה האחידה של כל המסלולים
/// (תצוגה, העתקה, ייצוא). שניהם יחד = [removeVolwels], כדי לשמור על
/// ההתנהגות המוכרת של "הסר הכול".
String removeMarks(String s, {required bool nikud, required bool teamim}) {
  if (nikud && teamim) return removeVolwels(s);
  if (teamim) return removeTeamim(s);
  if (nikud) return removeNikudOnly(s);
  return s;
}

/// הסרת סימני פיסוק מטקסט
/// מסיר !:;.,?-— חוץ מ . או : בסוף הקטע
/// מסיר " ״ אלא כשזה ראשי תיבות (אות אחת אחרי הגרשיים עד גבול מילה)
/// מסיר מעבר שורה אם אין . או : בסוף השורה המקורית
String removePunctuation(String text) {
  if (text.isEmpty) return text;

  final hadHtmlBreaks = RegExp(
    r'<br\s*/?>',
    caseSensitive: false,
  ).hasMatch(text);
  final normalizedText = text
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

  final lines = normalizedText.split('\n');
  final processedLines = <String>[];
  final originalEndsWithAllowed = <bool>[];

  for (final line in lines) {
    if (line.trim().isEmpty) {
      processedLines.add(line);
      originalEndsWithAllowed.add(true);
      continue;
    }

    final endsWithAllowed = RegExp(r'[.:](\s*)$').hasMatch(line);
    originalEndsWithAllowed.add(endsWithAllowed);

    if (isHeadingLine(line.trim())) {
      processedLines.add(line);
      continue;
    }

    // הגרשיים מוכרעים לפני הסרת הפיסוק — אחרת ב-'רש"י,ובגמ' הפסיק נמחק,
    // ראשי התיבות נדבקים למילה הבאה ונראים כמירכאות ציטוט.
    String processed = _stripQuotesOutsideTags(line);

    final lastAllowedPunctuationMatch = RegExp(
      r'[.:](\s*)$',
    ).firstMatch(processed);
    final lastAllowedPunctuationIndex = lastAllowedPunctuationMatch?.start;

    // הסרה לינארית של פיסוק, עם תמיכה בסוגריים מקוננים.
    // בתוך סוגריים שומרים רק . ו- :
    // תגי HTML (למשל <a href="otzaria://...">) נשארים מחוץ לעיבוד - אחרת
    // ה-":" וה-"-" בתוך ה-href נמחקים והקישור נשבר.
    final buffer = StringBuffer();
    var parenDepth = 0;
    var inTag = false;
    for (var i = 0; i < processed.length; i++) {
      final ch = processed[i];

      if (inTag) {
        buffer.write(ch);
        if (ch == '>') inTag = false;
        continue;
      }

      if (ch == '<') {
        inTag = true;
        buffer.write(ch);
        continue;
      }

      // ישות HTML עוברת כמכלול - אחרת ה-";" שלה נמחק כפיסוק והישות מוצגת
      // כטקסט גלוי (למשל "&thinsp" סביב פסק בתנ"ך).
      if (ch == '&') {
        final entity = _htmlEntity.matchAsPrefix(processed, i);
        if (entity != null) {
          buffer.write(entity.group(0));
          i = entity.end - 1;
          continue;
        }
      }

      if (ch == '(') {
        parenDepth++;
        buffer.write(ch);
        continue;
      }

      if (ch == ')') {
        if (parenDepth > 0) {
          parenDepth--;
        }
        buffer.write(ch);
        continue;
      }

      final isPunctuation =
          ch == '!' ||
          ch == ':' ||
          ch == ';' ||
          ch == '.' ||
          ch == ',' ||
          ch == '?' ||
          ch == '-' ||
          ch == '—' ||
          ch == '–';

      if (parenDepth > 0 && (ch == ':' || ch == '.')) {
        buffer.write(ch);
        continue;
      }

      if (isPunctuation) {
        if (lastAllowedPunctuationIndex != null &&
            i >= lastAllowedPunctuationIndex &&
            (ch == '.' || ch == ':')) {
          buffer.write(ch);
        }
        continue;
      }

      buffer.write(ch);
    }
    processed = buffer.toString();

    processedLines.add(processed);
  }

  final finalResult = StringBuffer();
  bool lastCharWasNewline = false;
  bool lastCharWasSpace = false;

  for (int i = 0; i < processedLines.length; i++) {
    final line = processedLines[i];
    final shouldKeepNewline =
        originalEndsWithAllowed[i] ||
        isHeadingLine(line) ||
        (i < processedLines.length - 1 && isHeadingLine(processedLines[i + 1]));

    if (line.trim().isEmpty) {
      if (finalResult.isNotEmpty) {
        finalResult.write('\n');
        lastCharWasNewline = true;
        lastCharWasSpace = false;
      }
      finalResult.write(line);
      if (i < processedLines.length - 1) {
        finalResult.write('\n');
        lastCharWasNewline = true;
        lastCharWasSpace = false;
      }
      continue;
    }

    if (finalResult.isNotEmpty && !lastCharWasNewline && !lastCharWasSpace) {
      finalResult.write(' ');
      lastCharWasSpace = true;
      lastCharWasNewline = false;
    }

    finalResult.write(line);
    lastCharWasNewline = false;
    lastCharWasSpace = false;

    if (shouldKeepNewline && i < processedLines.length - 1) {
      finalResult.write('\n');
      lastCharWasNewline = true;
    }
  }

  final result = finalResult.toString();
  if (!hadHtmlBreaks) {
    return result;
  }
  return result.replaceAll('\n', '<br>');
}

/// רגקס לאיתור תגי HTML (ומכאן טווחים שיש לדלג עליהם בניקוי גרשיים).
final RegExp _htmlTagSpan = RegExp(r'<[^>]*>');

/// מסיר גרשיים ומירכאות ציטוט (ראו [removePunctuation]) בכל הטקסט *חוץ*
/// מתוך תגי HTML - כדי לא לפגוע בגרשיים סביב attributes כמו href="...".
String _stripQuotesOutsideTags(String text) {
  final buffer = StringBuffer();
  var lastEnd = 0;
  for (final match in _htmlTagSpan.allMatches(text)) {
    buffer.write(_stripAcronymQuotes(text, lastEnd, match.start));
    buffer.write(match.group(0));
    lastEnd = match.end;
  }
  buffer.write(_stripAcronymQuotes(text, lastEnd, text.length));
  return buffer.toString();
}

// תגים ופיסוק שצמודים לגרשיים אינם חלק מההכרעה (גם שגיאת הקלדה כמו א,"א).
final RegExp _leadingSkippable = RegExp(r'^(?:<[^>]*>|[!:;.,?\-—–])+');
final RegExp _trailingSkippable = RegExp(r'(?:<[^>]*>|[!:;.,?\-—–])+$');

/// מסיר גרשיים/מירכאות מהטווח [start, end) של [text] (ללא תגי HTML), פרט
/// לראשי תיבות. ההקשר נבדק על כל השורה, כי תג יכול ליפול בתוך ראשי התיבות.
String _stripAcronymQuotes(String text, int start, int end) {
  final segment = text.substring(start, end);
  if (segment.isEmpty) return segment;
  return segment.replaceAllMapped(RegExp(r'["״]'), (match) {
    final index = start + match.start;
    final letter = RegExp(r'[א-תa-zA-Z]');
    // ראשי תיבות: הגרשיים לפני האות האחרונה, כלומר אות אחת בלבד אחריו
    // ואז גבול מילה. שתי אותיות אחריו = מירכאות ציטוט (כמו ב"כי יותן).
    // מנקים ניקוד משני הצדדים כדי שאות מנוקדת (רַשִׁ"י, ב"כִּי) לא תיחשב
    // בטעות כסימן ניקוד או כאות בודדת.
    final before = removeVolwels(
      text.substring(0, index).replaceFirst(_trailingSkippable, ''),
    );
    final hasBefore =
        before.isNotEmpty && letter.hasMatch(before[before.length - 1]);
    final rest = removeVolwels(
      text.substring(index + 1).replaceFirst(_leadingSkippable, ''),
    );
    final hasSingleLetterAfter =
        rest.isNotEmpty &&
        letter.hasMatch(rest[0]) &&
        (rest.length == 1 || !letter.hasMatch(rest[1]));
    if (hasBefore && hasSingleLetterAfter) {
      return match.group(0)!;
    }
    return '';
  });
}

bool isHeadingLine(String line) {
  final trimmedLine = line.trim();
  if (trimmedLine.isEmpty) return false;
  return RegExp(
        r'^<h[1-6][^>]*>.*?</h[1-6]>$',
        caseSensitive: false,
      ).hasMatch(trimmedLine) ||
      RegExp(r'^#{1,6}\s').hasMatch(trimmedLine);
}

/// בדיקה אם טקסט מכיל ניקוד או טעמים
bool hasNikud(String text) {
  return _vowelsAndCantillation.hasMatch(text);
}

/// תבנית הדגשה מקומפלת שמקורה במנוע החיפוש (Rust).
///
/// כל בניית הרג'קסים — וריאציות כתיב, מילים חילופיות, סובלנות ניקוד,
/// מפרידים ומרווחים — מתבצעת במנוע (`generateHighlightPattern`); צד ה-Dart
/// רק מקמפל את המחרוזות שהתקבלו ומחיל אותן.
class _CompiledHighlightPattern {
  /// רגקס שתופס את הביטוי השלם (כל המילים והמפרידים ביניהן).
  final RegExp combined;

  /// רגקס פר-מילה — לאיתור תת-הטווח של כל מילה בתוך התאמה משולבת.
  final List<RegExp> words;

  /// פר-מילה: האם מותר לדרוש גבולות מילה סביב ההתאמה (אין למילה
  /// אפשרות הרחבה מורפולוגית).
  final List<bool> boundaryEligible;

  const _CompiledHighlightPattern(
    this.combined,
    this.words,
    this.boundaryEligible,
  );
}

/// ההדגשה רצה פר-פסקה ברינדור, עם אותם פרמטרי חיפוש — לכן התבנית נבנית
/// פעם אחת לכל שינוי פרמטרים ונשמרת. `_highlightCacheValid` נדרש כי גם
/// `null` (שאילתה ללא מילים ברות-הדגשה) הוא תוצאה שנשמרת.
String? _highlightCacheKey;
_CompiledHighlightPattern? _highlightCacheValue;
bool _highlightCacheValid = false;

/// תבניות הדגשה מבוססות-אינדקס שהוזנו מראש, לפי מפתח פרמטרי החיפוש.
///
/// המנוע נסרק אסינכרונית בזמן ריצת החיפוש (ראה `search_engine_gateway`) —
/// שניות לפני שספר נפתח מהתוצאות — כך שהרינדור הסינכרוני מוצא כאן תבנית
/// שמדגישה את הווריאנטים שהחיפוש באמת התאים באינדקס (שגיאות כתיב, קידומות,
/// חלק ממילה), בזהות מלאה להדגשת ה-snippets. נשמרות רק תבניות שקומפלו
/// בהצלחה — fetch שהחזיר null אינו נכנס, אחרת היה גובר על ה-fallback
/// וחוסם גם ניסיון הזנה חוזר.
///
/// כשאין רשומה (חיפוש שלא עבר דרך ה-gateway, או שההזנה נכשלה/החזירה
/// null/טרם הסתיימה) ממשיכים ל-fallback הסינכרוני שמכיר רק את צורת
/// השאילתה — ההתנהגות הקודמת.
final LinkedHashMap<String, _CompiledHighlightPattern> _primedHighlightCache =
    LinkedHashMap();
const int _maxPrimedHighlightEntries = 8;
final Set<String> _primedHighlightInFlight = <String>{};

final ValueNotifier<int> _highlightPatternRevision = ValueNotifier<int>(0);

/// מתעדכן כשתבנית הדגשה מבוססת-אינדקס חדשה נכנסת למטמון. הרינדור שכבר צויר
/// עם ה-fallback (צורת-השאילתה בלבד) מאזין לזה ומתרנדר מחדש עם התבנית
/// המדויקת — אחרת התאמות קידומת/וריאנט נשארות ללא הדגשה עד גלילה.
ValueListenable<int> get highlightPatternRevision => _highlightPatternRevision;

/// מקמפל את תבניות ה-RegExp שהמנוע החזיר. כל הלוגיקה של בניית התבניות חיה
/// ב-Rust; כאן קומפילציה בלבד.
_CompiledHighlightPattern? _compileHighlightPattern(HighlightPattern? pattern) {
  if (pattern == null) return null;
  return _CompiledHighlightPattern(
    RegExp(pattern.combinedPattern, caseSensitive: false),
    [
      for (final wordPattern in pattern.wordPatterns)
        RegExp(wordPattern, caseSensitive: false),
    ],
    pattern.wordBoundaryEligible,
  );
}

/// מזין מראש תבנית הדגשה מבוססת-אינדקס לפרמטרי חיפוש נתונים.
///
/// `fetch` מביא את התבנית מהמנוע (סריקת FST של מילון האינדקס עם אוטומטי
/// החיפוש עצמם). שגיאה בהבאה נבלעת בכוונה — מסלול ה-fallback ממשיך לשרת.
Future<void> primeHighlightPattern({
  required String searchQuery,
  required Map<String, Map<String, bool>> searchOptions,
  required Map<int, List<String>> alternativeWords,
  required Map<String, String> spacingValues,
  required int searchDistance,
  required bool isFuzzy,
  required Future<HighlightPattern?> Function() fetch,
}) async {
  final key = _highlightRequestKey(
    searchQuery,
    searchOptions,
    alternativeWords,
    spacingValues,
    searchDistance,
    isFuzzy,
  );
  if (_primedHighlightCache.containsKey(key) ||
      !_primedHighlightInFlight.add(key)) {
    return;
  }
  try {
    final pattern = await fetch();
    final compiled = _compileHighlightPattern(pattern);
    // null אינו נשמר: רשומת null הייתה גוברת על ה-fallback (containsKey)
    // וחוסמת גם ניסיון הזנה חוזר — לשאילתה לא הייתה נשארת שום הדגשה.
    if (compiled != null) {
      _primedHighlightCache[key] = compiled;
      while (_primedHighlightCache.length > _maxPrimedHighlightEntries) {
        _primedHighlightCache.remove(_primedHighlightCache.keys.first);
      }
      // תבנית מדויקת חדשה זמינה — מאותת לרינדור להתרנן מחדש.
      _highlightPatternRevision.value++;
    }
  } catch (error) {
    debugPrint('primeHighlightPattern failed: $error');
  } finally {
    _primedHighlightInFlight.remove(key);
  }
}

String _highlightRequestKey(
  String searchQuery,
  Map<String, Map<String, bool>> searchOptions,
  Map<int, List<String>> alternativeWords,
  Map<String, String> spacingValues,
  int searchDistance,
  bool isFuzzy,
) {
  // מצב fuzzy מפיק תבנית שונה מהותית (וריאנטי מרחק-עריכה וצורות מילון) גם
  // עבור אותם query/distance — בלעדי הסמן, חיפוש advanced ו-fuzzy עם אותם
  // פרמטרים היו חולקים רשומת מטמון בטעות.
  final buffer = StringBuffer()
    ..write(isFuzzy ? 'f' : 'a')
    ..write(' ')
    ..write(searchDistance)
    ..write(' ')
    ..write(searchQuery)
    ..write(' ');
  for (final key in searchOptions.keys.toList()..sort()) {
    buffer
      ..write(key)
      ..write(':');
    final options = searchOptions[key]!;
    for (final option in options.keys.toList()..sort()) {
      if (options[option] == true) {
        buffer
          ..write(option)
          ..write(',');
      }
    }
    buffer.write(';');
  }
  buffer.write(' ');
  for (final key in alternativeWords.keys.toList()..sort()) {
    buffer
      ..write(key)
      ..write(':')
      ..write(alternativeWords[key]!.join(','))
      ..write(';');
  }
  buffer.write(' ');
  for (final key in spacingValues.keys.toList()..sort()) {
    buffer
      ..write(key)
      ..write(':')
      ..write(spacingValues[key])
      ..write(';');
  }
  return buffer.toString();
}

_CompiledHighlightPattern? _resolveHighlightPattern(
  String searchQuery,
  Map<String, Map<String, bool>> searchOptions,
  Map<int, List<String>> alternativeWords,
  Map<String, String> spacingValues,
  int searchDistance,
  bool isFuzzy,
) {
  final key = _highlightRequestKey(
    searchQuery,
    searchOptions,
    alternativeWords,
    spacingValues,
    searchDistance,
    isFuzzy,
  );
  // תבנית מבוססת-אינדקס שהוזנה מראש קודמת ל-fallback: היא מדגישה את
  // הווריאנטים שהחיפוש באמת התאים, לא רק את צורת השאילתה.
  final primed = _primedHighlightCache[key];
  if (primed != null) {
    return primed;
  }
  if (_highlightCacheValid && key == _highlightCacheKey) {
    return _highlightCacheValue;
  }

  final compiled = _compileHighlightPattern(
    generateHighlightPattern(
      query: searchQuery,
      distance: searchDistance < 0 ? 0 : searchDistance,
      customSpacing: spacingValues,
      alternativeWords: alternativeWords,
      searchOptions: searchOptions,
    ),
  );

  _highlightCacheKey = key;
  _highlightCacheValue = compiled;
  _highlightCacheValid = true;
  return compiled;
}

class _HighlightMatch {
  final Match match;
  final List<_HighlightRange> ranges;

  const _HighlightMatch(this.match, this.ranges);
}

class _HighlightRange {
  final int start;
  final int end;

  const _HighlightRange(this.start, this.end);
}

/// ניקוד/טעמים הצמודים לאות; מפרידי מילים שבטווח נשארים מחוץ לסט כדי
/// שבדיקת גבולות לא תדלג מעל מקף, פסק, סוף-פסוק או נו"ן הפוכה.
bool _isHebrewMark(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x0591 && code <= 0x05BD) ||
      code == 0x05BF ||
      code == 0x05C1 ||
      code == 0x05C2 ||
      code == 0x05C4 ||
      code == 0x05C5 ||
      code == 0x05C7;
}

/// תו שנחשב חלק ממילת חיפוש, כולל ליגטורות יידיש וצורות תצוגה עבריות.
bool _isSearchTokenChar(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x05D0 && code <= 0x05EA) ||
      (code >= 0x05F0 && code <= 0x05F2) ||
      (code >= 0xFB1D && code <= 0xFB4F) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x30 && code <= 0x39);
}

bool _hasTokenBoundaryBefore(String text, int start) {
  var index = start - 1;
  while (index >= 0 && _isHebrewMark(text[index])) {
    index--;
  }

  return index < 0 || !_isSearchTokenChar(text[index]);
}

bool _hasTokenBoundaryAfter(String text, int end) {
  var index = end;
  while (index < text.length && _isHebrewMark(text[index])) {
    index++;
  }

  return index >= text.length || !_isSearchTokenChar(text[index]);
}

List<_HighlightRange>? _collectMatchedSearchWordRanges(
  String fullText,
  String matchedText,
  int matchStart,
  List<RegExp> wordRegexes,
  List<bool> requireTokenBoundaries,
) {
  final ranges = <_HighlightRange>[];
  var searchOffset = 0;

  for (var i = 0; i < wordRegexes.length; i++) {
    final wordRegex = wordRegexes[i];
    final searchText = matchedText.substring(searchOffset);
    final wordMatch = wordRegex.firstMatch(searchText);
    if (wordMatch == null) {
      return null;
    }

    final wordStart = searchOffset + wordMatch.start;
    final wordEnd = searchOffset + wordMatch.end;

    // הגבול נבדק בקצוות ההתאמה כולה, לא בקצה טווח-המילה: קידומת/סיומת שבתוך
    // ההתאמה (כמו "ב" ב"במיעוט") היא חלק מהטוקן ואומתה בתבנית המנוע — אין
    // לפסול בגללה. גבולות פנימיים בין מילים מאומתים אף הם בתבנית.
    final isFirst = i == 0;
    final isLast = i == wordRegexes.length - 1;
    if (requireTokenBoundaries[i] &&
        ((isFirst && !_hasTokenBoundaryBefore(fullText, matchStart)) ||
            (isLast &&
                !_hasTokenBoundaryAfter(
                  fullText,
                  matchStart + matchedText.length,
                )))) {
      return null;
    }

    ranges.add(_HighlightRange(wordStart, wordEnd));
    searchOffset = wordEnd;
  }

  return ranges;
}

/// מדגיש את כל הטווח מהמילה הראשונה עד האחרונה ברצף (כולל רווחים ופיסוק).
/// תגי HTML פנימיים נשארים מחוץ ל-span כדי לא לשבור קינון תגים.
String _highlightContinuousMatch(
  String matchedText,
  List<_HighlightRange> ranges,
  String style,
) {
  final start = ranges.first.start;
  final end = ranges.last.end;
  final highlighted = matchedText
      .substring(start, end)
      .splitMapJoin(
        RegExp(r'<[^>]*>'),
        onNonMatch: (text) =>
            text.isEmpty ? text : '<span style="$style">$text</span>',
      );
  return matchedText.substring(0, start) +
      highlighted +
      matchedText.substring(end);
}

String _highlightMatchedSearchWords(
  String matchedText,
  List<_HighlightRange> ranges,
  String style,
) {
  final result = StringBuffer();
  var currentPosition = 0;

  for (final range in ranges) {
    if (range.start > currentPosition) {
      result.write(matchedText.substring(currentPosition, range.start));
    }
    result.write('<span style="$style">');
    result.write(matchedText.substring(range.start, range.end));
    result.write('</span>');

    currentPosition = range.end;
  }

  if (currentPosition < matchedText.length) {
    result.write(matchedText.substring(currentPosition));
  }

  return result.toString();
}

/// מאתר את התאמות ההדגשה בטקסט: התאמות התבנית המשולבת שעוברות גם את
/// בדיקת גבולות המילה פר-מילה. משותף ל-[highLight] ול-[countMatches], כך
/// שהמונה סופר בדיוק את מה שמודגש בפועל.
///
/// [matchPolicy] שאינה ברירת המחדל (טווח פסקה/כותרת, או התאמה חלקית של מילות
/// השאילתה) מתירה תוצאות שהמילים בהן מפוזרות או חסרות, ולכן ההתאמה המשולבת
/// פוסלת דווקא את מה שהמנוע מחזיר: במצב כזה מדגישים כל מילת שאילתה בנפרד,
/// ורק ב-[isSearchResultLine] — שורה שהמנוע החזיר. ב-[isFuzzy] המנוע מחפש כל
/// מילה בנפרד (AND), ולכן בשורת תוצאה בלי הביטוי הרציף מדגישים מילה-מילה.
///
/// אין לשחזר כאן את החלטת המנוע (למשל סף מילים פר-שורה): הסף שלו מחושב על
/// הסעיף בטווח "תחת אותה כותרת", והוא סופר מילים ייחודיות.
List<_HighlightMatch> _findHighlightMatches(
  String data,
  _CompiledHighlightPattern compiled,
  List<bool> requireTokenBoundaries, {
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  bool isSearchResultLine = false,
  bool isFuzzy = false,
}) {
  if (!matchPolicy.isStandard) {
    if (!isSearchResultLine) return const [];
    return _findPerWordHighlightMatches(
      data,
      compiled,
      requireTokenBoundaries,
    );
  }
  final phraseMatches = compiled.combined
      .allMatches(data)
      .map((match) {
        final matchedText = match.group(0)!;
        final ranges = _collectMatchedSearchWordRanges(
          data,
          matchedText,
          match.start,
          compiled.words,
          requireTokenBoundaries,
        );
        return ranges == null ? null : _HighlightMatch(match, ranges);
      })
      .whereType<_HighlightMatch>()
      .toList();
  if (!isFuzzy || phraseMatches.isNotEmpty || !isSearchResultLine) {
    return phraseMatches;
  }
  return _findPerWordHighlightMatches(data, compiled, requireTokenBoundaries);
}

/// התאמות של כל מילת שאילתה בנפרד בשורה שהמנוע החזיר, ממוינות ובלי חפיפות —
/// [highLight] משכתב את הטקסט לפי סדר ההתאמות ולכן חפיפה הייתה משבשת את
/// ההיסטים.
List<_HighlightMatch> _findPerWordHighlightMatches(
  String data,
  _CompiledHighlightPattern compiled,
  List<bool> requireTokenBoundaries,
) {
  final matches = <_HighlightMatch>[];
  for (var i = 0; i < compiled.words.length; i++) {
    final requireBoundary =
        i < requireTokenBoundaries.length && requireTokenBoundaries[i];
    for (final match in compiled.words[i].allMatches(data)) {
      if (match.end <= match.start) continue;
      if (requireBoundary &&
          (!_hasTokenBoundaryBefore(data, match.start) ||
              !_hasTokenBoundaryAfter(data, match.end))) {
        continue;
      }
      matches.add(
        _HighlightMatch(match, [_HighlightRange(0, match.end - match.start)]),
      );
    }
  }

  matches.sort((a, b) => a.match.start.compareTo(b.match.start));
  final result = <_HighlightMatch>[];
  var lastEnd = -1;
  for (final match in matches) {
    if (match.match.start < lastEnd) continue;
    result.add(match);
    lastEnd = match.match.end;
  }
  return result;
}

String highLight(
  String data,
  String searchQuery, {
  int currentIndex = -1,
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  bool isFuzzy = false,
  int searchDistance = 0,
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  bool isSearchResultLine = false,
  bool yellowBackground = false,
  bool partialWordMatch = false,
}) {
  if (searchQuery.isEmpty) return data;

  // בניית תבניות ההדגשה מתבצעת כולה במנוע החיפוש (Rust) — כולל וריאציות
  // כתיב, מילים חילופיות, סובלנות ניקוד ומרווחים בין מילים. כאן רק
  // מקמפלים את התבניות שהתקבלו ומחילים אותן על הטקסט.
  final compiled = _resolveHighlightPattern(
    searchQuery,
    searchOptions,
    alternativeWords,
    spacingValues,
    searchDistance,
    isFuzzy,
  );
  if (compiled == null) return data;

  // בהדגשת ציטוט (רקע צהוב) הטקסט הועתק מהמקטע עצמו ועשוי להיקטע
  // באמצע מילה — דרישת גבולות מילה תפסול אז את כל ההדגשה.
  final requireTokenBoundaries = [
    for (final eligible in compiled.boundaryEligible)
      eligible && !yellowBackground && !partialWordMatch,
  ];

  final matches = _findHighlightMatches(
    data,
    compiled,
    requireTokenBoundaries,
    matchPolicy: matchPolicy,
    isSearchResultLine: isSearchResultLine,
    isFuzzy: isFuzzy,
  );

  if (matches.isEmpty) return data;

  // מעבר אחד עם buffer: שרשור substring לכל התאמה מעתיק את כל השורה בכל פעם,
  // ושורה ארוכה עם התאמות רבות חורגת מתקציב הפריים.
  final buffer = StringBuffer();
  var position = 0;

  for (int i = 0; i < matches.length; i++) {
    final highlightMatch = matches[i];
    final match = highlightMatch.match;
    final matchedText = data.substring(match.start, match.end);

    final String replacement;
    if (currentIndex == -1) {
      final style = yellowBackground
          ? 'background-color: yellow; color: black'
          : 'color: red';
      // הדגשת קטע מקושר (רקע צהוב) צריכה להיות רציפה כמו מרקר,
      // בניגוד להדגשת חיפוש שמסמנת רק את מילות החיפוש עצמן.
      replacement = yellowBackground
          ? _highlightContinuousMatch(matchedText, highlightMatch.ranges, style)
          : _highlightMatchedSearchWords(
              matchedText,
              highlightMatch.ranges,
              style,
            );
    } else {
      // התוצאה הנוכחית בכחול, השאר באדום.
      final color = i == currentIndex ? 'blue' : 'red';
      final backgroundColor = i == currentIndex
          ? 'background-color: yellow;'
          : '';
      replacement = _highlightMatchedSearchWords(
        matchedText,
        highlightMatch.ranges,
        'color: $color; $backgroundColor',
      );
    }

    buffer.write(data.substring(position, match.start));
    buffer.write(replacement);
    position = match.end;
  }

  buffer.write(data.substring(position));
  return buffer.toString();
}

/// מחזיר את טווחי ההדגשה (offsets גולמיים) של מילות החיפוש ב-[data], באותה
/// התאמה בדיוק כמו [highLight] — לבניית InlineSpans (סרגל תוצאות) בעקביות
/// מלאה עם הדגשת פאנל הקריאה. כל טווח הוא זוג [start, end].
List<List<int>> computeHighlightRanges(
  String data,
  String searchQuery, {
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  bool isFuzzy = false,
  int searchDistance = 0,
  SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
  bool isSearchResultLine = false,
  bool partialWordMatch = false,
}) {
  if (searchQuery.isEmpty || data.isEmpty) return const [];
  final compiled = _resolveHighlightPattern(
    searchQuery,
    searchOptions,
    alternativeWords,
    spacingValues,
    searchDistance,
    isFuzzy,
  );
  if (compiled == null) return const [];
  final requireTokenBoundaries = [
    for (final eligible in compiled.boundaryEligible)
      eligible && !partialWordMatch,
  ];
  final matches = _findHighlightMatches(
    data,
    compiled,
    requireTokenBoundaries,
    matchPolicy: matchPolicy,
    isSearchResultLine: isSearchResultLine,
    isFuzzy: isFuzzy,
  );
  final ranges = <List<int>>[];
  for (final highlightMatch in matches) {
    final base = highlightMatch.match.start;
    for (final range in highlightMatch.ranges) {
      ranges.add([base + range.start, base + range.end]);
    }
  }
  return ranges;
}

String getTitleFromPath(String path) {
  path = path
      .replaceAll('/', Platform.pathSeparator)
      .replaceAll('\\', Platform.pathSeparator);
  final fileName = path.split(Platform.pathSeparator).last;

  // אם אין נקודה בשם הקובץ, נחזיר את השם כמו שהוא
  final lastDotIndex = fileName.lastIndexOf('.');
  if (lastDotIndex == -1) {
    return fileName;
  }

  // נסיר רק את הסיומת (החלק האחרון אחרי הנקודה האחרונה)
  return fileName.substring(0, lastDotIndex);
}

/// קידומת המזהה ספר "הערות על XX" — הערות הכתובות על ספר אחר.
const String kNotesOnBookPrefix = 'הערות על ';

/// אם [title] הוא "הערות על XX" מחזיר את שם הבסיס "XX", אחרת null.
/// משמש לעיגון ספרי-הערות מיד אחרי הספר שעליו נכתבו במיון המפרשים.
String? notesBookBaseTitle(String title) {
  if (!title.startsWith(kNotesOnBookPrefix)) return null;
  final base = title.substring(kNotesOnBookPrefix.length).trim();
  return base.isEmpty ? null : base;
}

// Cache for the CSV data to avoid reading the file multiple times
Map<String, String>? _csvCache;
// טעינת ה-cache שעדיין מתבצעת — מבטיח שקריאות מקבילות ימתינו לאותה טעינה
// במקום לראות cache ריק באמצע ה-await ולסווג מפרשים כ"שאר מפרשים".
Future<void>? _csvCacheLoading;
bool _csvCacheUnavailable = false;

// אחרי כשל טעינה מנסים שוב רק כשה-DB חזר להיות זמין. בלי התנאי הזה כל קריאה
// בנתיב תצוגה חם הייתה ממתינה מחדש ל-gate של עדכון ספרייה (עד 30 שניות).
bool _shouldLoadCsvCache() =>
    _csvCache == null &&
    (!_csvCacheUnavailable || SqliteDataProvider.instance.isInitialized);

// Era categories constant - used across multiple functions
const List<String> _eraCategories = [
  'תורה שבכתב',
  'חז"ל',
  'ראשונים',
  'אחרונים',
  'מחברי זמננו',
];
const String _defaultCategory = 'מפרשים נוספים';

/// סופר את הופעות השאילתה בטקסט — באותה התאמה בדיוק כמו [highLight]:
/// תבנית מהמנוע, סובלנות ניקוד, וגבולות מילה לפי [partialWordMatch] —
/// שחייב לקבל את אותו ערך שמגיע להדגשה, אחרת המונה סוטה מהצביעה בפועל.
int countMatches(
  String text,
  String searchQuery, {
  bool partialWordMatch = false,
}) {
  if (searchQuery.isEmpty) return 0;
  final compiled = _resolveHighlightPattern(
    searchQuery,
    const {},
    const {},
    const {},
    0,
    false,
  );
  if (compiled == null) return 0;
  final requireTokenBoundaries = [
    for (final eligible in compiled.boundaryEligible)
      eligible && !partialWordMatch,
  ];
  return _findHighlightMatches(text, compiled, requireTokenBoundaries).length;
}

Future<bool> hasTopic(
  String title,
  String topic, {
  BookSource source = BookSource.official,
}) async {
  // Load CSV data once and cache it (קריאות מקבילות חולקות את אותה טעינה)
  if (_shouldLoadCsvCache()) {
    await (_csvCacheLoading ??= _loadCsvCache());
  }
  final overlay = await _eraOverlayFor(source);

  // For non-era topics (like 'על ברכות'), check if the commentator title contains the topic.
  // e.g. "רש"י על ברכות".contains("על ברכות") == true
  if (!_eraCategories.contains(topic) && topic != _defaultCategory) {
    return title.contains(topic);
  }

  // הטבלה עשויה להיות null אם הטעינה נכשלה; אז אין סיווג ידוע.
  final generationRaw = overlay[title] ?? _csvCache?[title];
  if (generationRaw != null) {
    return generationRaw
        .split(',')
        .any((g) => _mapGenerationToCategory(g.trim()) == topic);
  }

  // ספר שאינו מתויג ב-DB משויך ל"מפרשים נוספים" בלבד
  return topic == _defaultCategory;
}

/// טוען את ה-cache של תקופות מפרשים מה-DB
Future<void> _loadCsvCache() async {
  // _csvCache מקבל ערך רק בהצלחה. קריאה מקבילה שתבדוק `_csvCache == null`
  // באמצע ה-await תמתין לאותה טעינה ולא תראה מפה ריקה.
  try {
    final provider = SqliteDataProvider.instance;
    if (!provider.isInitialized) {
      await provider.initialize();
    }
    final db = provider.repository?.database;
    if (db == null) {
      debugPrint('⚠️ SqliteDataProvider repository is null');
      _csvCacheUnavailable = true;
      _csvCacheLoading = null;
      return;
    }
    final map = await db.authorDao.getAllBookTitleToGeneration();
    // מיזוג דורות ספרי-משתמש (אם user_books.db פתוח) — כדי שמפרש-משתמש
    // ימוין לפי דורו. בהתנגשות כותרת נשמר הערך הרשמי.
    final userRepo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
    if (userRepo != null) {
      try {
        final userMap = await userRepo.database.authorDao
            .getAllBookTitleToGeneration();
        userMap.forEach((k, v) => map.putIfAbsent(k, () => v));
      } catch (e) {
        debugPrint('⚠️ user_books era cache skipped: $e');
      }
    }
    _csvCache = map;
    _csvCacheUnavailable = false;
  } catch (e) {
    debugPrint('⚠️ Failed to load era cache from DB: $e');
    // כשל זמני (DB נעול, עדכון ספרייה) — משאירים null כדי שניסיון חוזר יתאפשר
    // כשה-DB יחזור, במקום לקבע את כל הספרייה כ"מפרשים נוספים" עד הפעלה מחדש.
    _csvCacheUnavailable = true;
    _csvCacheLoading = null;
  }
}

/// דורות הספרים של מסד מצורף, לפי כותרת — נטען פעם אחת לכל מסד.
final Map<String, Future<Map<String, String>>> _attachedEraMaps = {};

/// מפת הדורות של המסד של [source] שגוברת על הרשמית: ספר ממסד מצורף מסווג
/// קודם לפי book_generation של המסד שלו. לספר רשמי/אישי — ריקה.
Future<Map<String, String>> _eraOverlayFor(BookSource source) {
  if (source is! AttachedBookSource) return Future.value(const {});
  return _attachedEraMaps[source.slug] ??= () async {
    try {
      final repo = await AttachedLibraryRegistry.instance.repositoryFor(
        source.slug,
      );
      if (repo == null) return const <String, String>{};
      return await repo.database.authorDao.getAllBookTitleToGeneration();
    } catch (e) {
      debugPrint('⚠️ attached era cache skipped (${source.slug}): $e');
      return const <String, String>{};
    }
  }();
}

/// האם טבלת הדורות נטענה מה-DB.
///
/// כשלא — כל סיווג דור יוצא "מפרשים נוספים", ואין לשמור אותו במטמון.
bool get isEraTableLoaded => _csvCache != null;

/// מנקה את ה-cache של תקופות כדי לאלץ טעינה מחדש
void clearCommentatorOrderCache() {
  _attachedEraMaps.clear();
  _csvCache = null;
  _csvCacheLoading = null;
  _csvCacheUnavailable = false;
}

// ממפה שם תקופה מה-DB לקטגוריה (השמות זהים, רק fallback)
String _mapGenerationToCategory(String generation) {
  if (_eraCategories.contains(generation)) {
    return generation;
  }
  return _defaultCategory;
}

// Matches the Tetragrammaton with any Hebrew diacritics or cantillation marks.
/// מקטין טקסט בתוך סוגריים עגולים
/// תנאים:
/// 1. אם יש סוגר פותח נוסף בפנים - מתעלם מהסוגר החיצוני ומקטין רק את הפנימיים
/// 2. אם אין סוגר סוגר עד סוף המקטע - לא מקטין כלום
String formatTextWithParentheses(String text) {
  if (text.isEmpty) return text;

  final StringBuffer result = StringBuffer();
  int i = 0;

  while (i < text.length) {
    // תגי HTML עוברים כמכלול - אחרת סוגריים בתוך attribute (למשל
    // style="color:rgb(0,0,0)") נעטפים ב-<small> וההגדרה נהרסת.
    if (text[i] == '<') {
      final tagEnd = _htmlTagEnd(text, i);
      if (tagEnd != -1) {
        result.write(text.substring(i, tagEnd + 1));
        i = tagEnd + 1;
        continue;
      }
    }

    if (text[i] == '(') {
      // מחפשים את הסוגר הסוגר המתאים
      int openCount = 1;
      int j = i + 1;
      int innerOpenIndex = -1;

      // בודקים אם יש סוגר פותח נוסף בפנים
      while (j < text.length && openCount > 0) {
        if (text[j] == '<') {
          final tagEnd = _htmlTagEnd(text, j);
          if (tagEnd != -1) {
            j = tagEnd + 1;
            continue;
          }
        }
        if (text[j] == '(') {
          if (innerOpenIndex == -1) {
            innerOpenIndex = j; // שומרים את המיקום של הסוגר הפנימי הראשון
          }
          openCount++;
        } else if (text[j] == ')') {
          openCount--;
        }
        j++;
      }

      // אם לא מצאנו סוגר סוגר - מוסיפים הכל כמו שהוא
      if (openCount > 0) {
        result.write(text[i]);
        i++;
        continue;
      }

      // אם יש סוגר פנימי - מתעלמים מהחיצוני ומעבדים רק את הפנימי
      if (innerOpenIndex != -1) {
        // מוסיפים את החלק עד הסוגר הפנימי
        result.write(text.substring(i, innerOpenIndex));
        // ממשיכים מהסוגר הפנימי
        i = innerOpenIndex;
        continue;
      }

      // אם אין סוגר פנימי - מקטינים את כל התוכן
      final content = text.substring(i + 1, j - 1);
      result.write('<small>(');
      result.write(content);
      result.write(')</small>');
      i = j;
    } else {
      result.write(text[i]);
      i++;
    }
  }

  return result.toString();
}

int _htmlTagEnd(String text, int start) {
  if (text.startsWith('<!--', start)) {
    final commentEnd = text.indexOf('-->', start + 4);
    return commentEnd == -1 ? -1 : commentEnd + 2;
  }

  if (start + 1 >= text.length) return -1;
  final first = text[start + 1];
  final firstCode = first.codeUnitAt(0);
  final startsWithLetter =
      (firstCode >= 65 && firstCode <= 90) ||
      (firstCode >= 97 && firstCode <= 122);
  if (!startsWithLetter && first != '!' && first != '/' && first != '?') {
    return -1;
  }

  String? quote;
  for (var i = start + 1; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == quote) quote = null;
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '>') {
      return i;
    }
  }
  return -1;
}

/// סגנון החלפת שם הקודש בתצוגה.
enum HolyNameStyle {
  /// החלפת ה' ב-ק' (יקוק) תוך שמירת הניקוד.
  kufKuf('kuf'),

  /// החלפה ב"ה'" — הניקוד והטעמים של השם עצמו מושמטים.
  hehApostrophe('heh');

  final String storageKey;
  const HolyNameStyle(this.storageKey);

  static HolyNameStyle fromStorage(String? key) =>
      key == HolyNameStyle.hehApostrophe.storageKey
      ? HolyNameStyle.hehApostrophe
      : HolyNameStyle.kufKuf;
}

String replaceHolyNames(
  String s, {
  HolyNameStyle style = HolyNameStyle.kufKuf,
}) {
  return s.replaceAllMapped(
    _holyName,
    (match) {
      if (_hasThreeContiguousHebrewLettersBeforeMatch(s, match.start)) {
        return match.group(0)!;
      }

      return style == HolyNameStyle.hehApostrophe
          ? "ה'"
          : 'י${match[1]}ק${match[2]}ו${match[3]}ק${match[4]}';
    },
  );
}

bool _hasThreeContiguousHebrewLettersBeforeMatch(String text, int matchStart) {
  var contiguousLetters = 0;

  for (var index = matchStart - 1; index >= 0; index--) {
    final char = text[index];

    if (RegExp(r'[\p{Mn}]', unicode: true).hasMatch(char)) {
      continue;
    }

    if (RegExp(r'[א-ת]').hasMatch(char)) {
      contiguousLetters++;
      if (contiguousLetters >= 3) {
        return true;
      }
      continue;
    }

    break;
  }

  return false;
}

String removeTeamim(String s) => s
    .replaceAll('־', ' ')
    .replaceAll(' ׀', '')
    .replaceAll('ֽ', '')
    .replaceAll('׀', '')
    .replaceAll(_cantillationOnly, '');

/// נורמליזציה לצורך התאמת מקור (FindRef):
/// מסיר ניקוד, טעמים, גרשיים, סימני פיסוק, ומאחד רווחים.
/// "שו"ע" → "שוע" ; "בְּרֵאשִׁית" → "בראשית".
String normalizeForFindRefMatch(String input) {
  var cleaned = removeTeamim(removeVolwels(input));

  // הרחבת סימון עמוד גמרא — חייב לרוץ לפני הסרת הגרשיים.
  // כך קיצורים כמו "פ"א." (גרש לפני האות) נשמרים: הלוקבאק
  // השלילי מכיל גם גרשיים/גרש, ולכן "פ"א." לא יפורש כציון דף.
  //   "ב."  (נקודה = עמוד א)  →  "ב א"
  //   "ב:"  (נקודתיים = עמוד ב)  →  "ב ב"
  // הטוקנים "א"/"ב" תואמים את ownTokens של רשומות TOC בפורמט "דף ב עמוד א".
  // הדפוס תופס 1–3 אותיות עבריות הסמוכות לנקודה/נקודתיים בגבול מילה.
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3})\.(?=\s|$)'''),
    (m) => '${m[1]} א',
  );
  cleaned = cleaned.replaceAllMapped(
    RegExp(r'''(?<![א-ת'"״׳])([א-ת]{1,3}):(?=\s|$)'''),
    (m) => '${m[1]} ב',
  );

  // הסרה מוחלטת של גרשיים — כך מ"ב הופך למב (לא מ ב)
  cleaned = cleaned
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('״', '')
      .replaceAll('׳', '');

  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9֐-׿\s]'), ' ');
  cleaned = cleaned.toLowerCase();
  return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// מחזיר את [titleToken] בלי אות-חיבור פותחת שהמשתמש עשוי לא להקליד —
/// ה' הידיעה ("הטור" → "טור") או ו' החיבור ("וברכת" → "ברכת") — או null
/// אם אין כזו.
///
/// הדרישה לאורך >= 3 מותירה שארית באורך >= 2, כדי שטוקן מיקום של אות בודדת
/// ("עמוד א") לא ייבלע. [allowVav] כבוי בטוקן הפותח את הכותרת: שם ו' היא
/// חלק מהשם ("ויקרא", "וזה לשונו", "וביום השבת") ולא אות חיבור.
String? titleTokenWithoutConjunction(
  String titleToken, {
  required bool allowVav,
}) {
  if (titleToken.length < 3) return null;
  final first = titleToken[0];
  if (first == 'ה' || (allowVav && first == 'ו')) {
    return titleToken.substring(1);
  }
  return null;
}

/// טוקני [normalizedTitle] בתוספת הגרסאות בלי אות-חיבור פותחת — לשאלה "האם
/// המילה הזו היא מילה מכותרת הספר". ראו [titleTokenWithoutConjunction].
Set<String> titleMatchTokens(String normalizedTitle) {
  final tokens = normalizedTitle.split(' ');
  final result = <String>{...tokens};
  for (var i = 0; i < tokens.length; i++) {
    final bare = titleTokenWithoutConjunction(tokens[i], allowVav: i > 0);
    if (bare != null) result.add(bare);
  }
  return result;
}

/// ציטוט דף מנותח: מספר הדף ועמוד אופציונלי ("א"/"ב").
typedef DafCitation = ({String number, String? amud});

/// מחזיר טוקן + גרסת טרנספוזיציה לאותיות עבריות דו-תווניות.
/// לדוגמה: "טל" → ["טל", "לט"] (שתי שיטות מניין עבריות ל-39).
List<String> hebrewTokenAlternatives(String token) {
  if (token.length == 2) {
    final c0 = token.codeUnitAt(0);
    final c1 = token.codeUnitAt(1);
    // אותיות עבריות U+05D0–U+05EA
    if (c0 >= 0x05D0 &&
        c0 <= 0x05EA &&
        c1 >= 0x05D0 &&
        c1 <= 0x05EA &&
        c0 != c1) {
      return [token, '${token[1]}${token[0]}'];
    }
  }
  return [token];
}

/// האם [token] הוא ראשי-תיבות של [words] — כל מילה תורמת תחילית רצופה
/// והצירוף שווה בדיוק לטוקן ("יוד" ← "יורה דעה", "אהע" ← "אבן העזר").
/// הסף (3 תווים, שתי מילים לפחות) מונע מטוקן-מיקום קצר להיתפס ככותרת.
bool hebrewAbbreviationMatchesWords(String token, List<String> words) {
  if (token.length < 3 || words.length < 2) return false;

  bool walk(int wordIndex, int pos) {
    if (wordIndex == words.length) return pos == token.length;
    final word = words[wordIndex];
    final remaining = token.length - pos;
    if (remaining <= 0) return false;
    final maxLen = word.length < remaining ? word.length : remaining;
    for (var len = 1; len <= maxLen; len++) {
      if (word.codeUnitAt(len - 1) != token.codeUnitAt(pos + len - 1)) break;
      if (walk(wordIndex + 1, pos + len)) return true;
    }
    return false;
  }

  return walk(0, 0);
}

/// מנתח טוקני-מיקום כציטוט דף בפורמט "מספר ואחריו עמוד אופציונלי" (אחרי הפשטת
/// "דף"/"עמוד"). מחזיר null אם אינו ציטוט דף נקי — אז המתקשר משתמש בהתאמה
/// הרגילה. הבחנה זו מונעת ש-"ב" בודד (מספר דף) ייתפס ע"י סימון צד ע"ב
/// (הנקודתיים שבנרמול הופכות ל-"ב") של כל דף במסכת.
DafCitation? parseDafCitation(List<String> tokens) {
  final loc = tokens
      .where((t) => t != 'דף' && t != 'עמוד')
      .toList(growable: false);
  if (loc.isEmpty) return null;

  // מספר דף: 1–3 אותיות עבריות בלבד (כדי לא לתפוס מילות-הקשר כמו "ראשון").
  final number = loc.first;
  if (number.isEmpty ||
      number.length > 3 ||
      !number.codeUnits.every((c) => c >= 0x05D0 && c <= 0x05EA)) {
    return null;
  }

  String? amud;
  if (loc.length >= 2) {
    if (loc[1] == 'א' || loc[1] == 'ב') {
      amud = loc[1];
    } else {
      return null; // טוקן מיקום שני שאינו עמוד — אינו ציטוט דף פשוט
    }
  }
  if (loc.length > (amud != null ? 2 : 1)) return null;
  return (number: number, amud: amud);
}

/// התאמה מיקומית של טוקני ערך בפורמט "דף מספר עמוד" לציטוט דף [cite].
/// מחזיר null אם הערך אינו בפורמט "דף ..." (אז המתקשר משתמש בהתאמה הרגילה),
/// אחרת bool האם המספר (וגם העמוד, אם צוין בשאילתה) תואמים.
bool? matchDafCitation(List<String> ownTokens, DafCitation cite) {
  if (ownTokens.length < 2 || ownTokens.first != 'דף') return null;
  if (!hebrewTokenAlternatives(cite.number).contains(ownTokens[1])) {
    return false;
  }
  if (cite.amud != null) {
    final entryAmud =
        ownTokens.length >= 3 && (ownTokens[2] == 'א' || ownTokens[2] == 'ב')
        ? ownTokens[2]
        : null;
    if (cite.amud != entryAmud) return false;
  }
  return true;
}

/// בודק אם כותרת TOC תואמת להפניה חופשית של תוסף (למשל "ס\"ד ע\"ב" ↔ "דף סד:").
/// תחילה התאמה גולמית, ואז התאמת טוקנים מנורמלים — כדי לגשר על פערי
/// גרשיים, "דף"/"עמוד", וסימון העמוד ("ע\"א/ע\"ב" מול ".":/":") שבין התוסף ל-TOC.
bool tocTextMatchesRef(String tocText, String ref) {
  if (ref.isEmpty) return false;
  if (tocText.contains(ref)) return true;
  final refTokens = _refMatchTokens(ref);
  if (refTokens.isEmpty) return false;
  final tocTokens = _refMatchTokens(tocText);
  // תת-רצף מסודר — הסדר מבדיל בין מספר הדף לציון העמוד,
  // כך ש"ב ע\"א" (ב,א) לא יתאים ל"דף א:" (א,ב).
  var ti = 0;
  for (final token in refTokens) {
    while (ti < tocTokens.length && tocTokens[ti] != token) {
      ti++;
    }
    if (ti == tocTokens.length) return false;
    ti++;
  }
  return true;
}

List<String> _refMatchTokens(String s) => normalizeForFindRefMatch(s)
    .split(' ')
    .map((t) => t == 'עא' ? 'א' : (t == 'עב' ? 'ב' : t))
    .where((t) => t.isNotEmpty && t != 'דף' && t != 'עמוד')
    .toList();

//פונקציה לחלוקת מפרשים לפי תקופה
///
/// [source] — המקור של הספר הפתוח: מפרשי מסד מצורף מסווגים קודם לפי הדורות
/// של המסד שלו. [sourceByTitle] — מפרש ממסד אחר (קישור חוצה-מסדים).
Future<Map<String, List<String>>> splitByEra(
  List<String> titles, {
  BookSource source = BookSource.official,
  Map<String, BookSource> sourceByTitle = const {},
}) async {
  // טעינת ה-cache פעם אחת בהתחלה (אם עדיין לא נטען).
  // קריאות מקבילות חולקות את אותה טעינה ולא רואות מפה ריקה באמצע.
  if (_shouldLoadCsvCache()) {
    await (_csvCacheLoading ??= _loadCsvCache());
  }
  final overlays = <BookSource, Map<String, String>>{
    source: await _eraOverlayFor(source),
  };
  for (final other in sourceByTitle.values.toSet()) {
    if (!overlays.containsKey(other)) {
      overlays[other] = await _eraOverlayFor(other);
    }
  }

  // יוצרים מבנה נתונים ריק לכל הקטגוריות
  final Map<String, List<String>> byEra = {
    for (var category in _eraCategories) category: [],
    _defaultCategory: [],
  };

  // ממיינים כל פרשן לקטגוריה הראשונה שמתאימה לו (סינכרוני!)
  for (final t in titles) {
    final overlay = overlays[sourceByTitle[t] ?? source]!;
    final category = _getTopicSync(t, overlay);
    byEra[category]!.add(t);
  }

  // מחזירים את כל הקטגוריות, גם אם הן ריקות
  return byEra;
}

/// גרסה סינכרונית של hasTopic - משתמשת ב-cache שכבר נטען
String _getTopicSync(String title, [Map<String, String> overlay = const {}]) {
  // הדור נלקח מטבלת book_generation ב-DB; ספר שאינו מתויג -> "מפרשים נוספים"
  final generationRaw = overlay[title] ?? _csvCache?[title];
  if (generationRaw != null) {
    final parsedCategories = generationRaw
        .split(',')
        .map((e) => _mapGenerationToCategory(e.trim()))
        .toSet();

    // העדפת התקופה המוקדמת ביותר על פי סדר הקטגוריות
    for (final category in _eraCategories) {
      if (parsedCategories.contains(category)) {
        return category;
      }
    }
    return parsedCategories.first;
  }

  return _defaultCategory;
}
