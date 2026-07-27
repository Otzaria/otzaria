import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show HighlightPattern, generateHighlightPattern;

/// רגקס להסרת תגי HTML.
final RegExp _htmlStripper = RegExp(r'<[^>]*>');

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
String stripHtmlIfNeeded(String text) {
  return decodeHtmlEntities(text.replaceAll(_htmlStripper, ''));
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

    String processed = line;

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

    processed = _stripQuotesOutsideTags(processed);

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
    buffer.write(_stripAcronymQuotes(text.substring(lastEnd, match.start)));
    buffer.write(match.group(0));
    lastEnd = match.end;
  }
  buffer.write(_stripAcronymQuotes(text.substring(lastEnd)));
  return buffer.toString();
}

/// מסיר גרשיים/מירכאות מקטע טקסט (ללא תגי HTML), פרט לראשי תיבות.
String _stripAcronymQuotes(String segment) {
  if (segment.isEmpty) return segment;
  return segment.replaceAllMapped(RegExp(r'["״]'), (match) {
    final index = match.start;
    final letter = RegExp(r'[א-תa-zA-Z]');
    // ראשי תיבות: הגרשיים לפני האות האחרונה, כלומר אות אחת בלבד אחריו
    // ואז גבול מילה. שתי אותיות אחריו = מירכאות ציטוט (כמו ב"כי יותן).
    // מנקים ניקוד משני הצדדים כדי שאות מנוקדת (רַשִׁ"י, ב"כִּי) לא תיחשב
    // בטעות כסימן ניקוד או כאות בודדת.
    final before = removeVolwels(segment.substring(0, index));
    final hasBefore =
        before.isNotEmpty && letter.hasMatch(before[before.length - 1]);
    final rest = removeVolwels(segment.substring(index + 1));
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
/// חלק ממילה), בזהות מלאה להדגשת ה-snippets. רשומה יכולה להיות null (שאילתה
/// ללא מילים ברות-הדגשה) — לכן containsKey ולא lookup.
///
/// כשאין רשומה (חיפוש שלא עבר דרך ה-gateway, או שההזנה נכשלה/טרם הסתיימה)
/// ממשיכים ל-fallback הסינכרוני שמכיר רק את צורת השאילתה — ההתנהגות הקודמת.
final LinkedHashMap<String, _CompiledHighlightPattern?> _primedHighlightCache =
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
    _primedHighlightCache[key] = compiled;
    while (_primedHighlightCache.length > _maxPrimedHighlightEntries) {
      _primedHighlightCache.remove(_primedHighlightCache.keys.first);
    }
    // תבנית מדויקת חדשה זמינה — מאותת לרינדור להתרנן מחדש.
    if (compiled != null) {
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
  if (_primedHighlightCache.containsKey(key)) {
    return _primedHighlightCache[key];
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
List<_HighlightMatch> _findHighlightMatches(
  String data,
  _CompiledHighlightPattern compiled,
  List<bool> requireTokenBoundaries,
) {
  return compiled.combined
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

  final matches = _findHighlightMatches(data, compiled, requireTokenBoundaries);

  if (matches.isEmpty) return data;

  // אם לא צוין אינדקס נוכחי, נדגיש את כל התוצאות
  if (currentIndex == -1) {
    String result = data;
    int offset = 0;

    final style = yellowBackground
        ? 'background-color: yellow; color: black'
        : 'color: red';

    for (final highlightMatch in matches) {
      final match = highlightMatch.match;
      final matchedText = match.group(0)!;
      // הדגשת קטע מקושר (רקע צהוב) צריכה להיות רציפה כמו מרקר,
      // בניגוד להדגשת חיפוש שמסמנת רק את מילות החיפוש עצמן.
      final replacement = yellowBackground
          ? _highlightContinuousMatch(matchedText, highlightMatch.ranges, style)
          : _highlightMatchedSearchWords(
              matchedText,
              highlightMatch.ranges,
              style,
            );

      final start = match.start + offset;
      final end = match.end + offset;

      result = result.substring(0, start) + replacement + result.substring(end);
      offset += replacement.length - matchedText.length;
    }

    return result;
  }

  // נדגיש את התוצאה הנוכחית בכחול ואת השאר באדום
  String result = data;
  int offset = 0;

  for (int i = 0; i < matches.length; i++) {
    final highlightMatch = matches[i];
    final match = highlightMatch.match;
    final matchedText = match.group(0)!;
    final color = i == currentIndex ? 'blue' : 'red';
    final backgroundColor = i == currentIndex
        ? 'background-color: yellow;'
        : '';
    final replacement = _highlightMatchedSearchWords(
      matchedText,
      highlightMatch.ranges,
      'color: $color; $backgroundColor',
    );

    final start = match.start + offset;
    final end = match.end + offset;

    result = result.substring(0, start) + replacement + result.substring(end);
    offset += replacement.length - matchedText.length;
  }

  return result;
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
  final matches = _findHighlightMatches(data, compiled, requireTokenBoundaries);
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

// Era categories constant - used across multiple functions
const List<String> _eraCategories = [
  'תורה שבכתב',
  'חז"ל',
  'ראשונים',
  'אחרונים',
  'מחברי זמננו',
];
const String _defaultCategory = 'מפרשים נוספים';

/// סופר את הופעות השאילתה בטקסט — באותה התאמה בדיוק כמו [highLight]
/// (תבנית מהמנוע, סובלנות ניקוד ובדיקת גבולות מילה), כך שהמונה המוצג
/// לעולם לא סוטה ממספר ההדגשות בפועל.
int countMatches(String text, String searchQuery) {
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
  return _findHighlightMatches(
    text,
    compiled,
    compiled.boundaryEligible,
  ).length;
}

Future<bool> hasTopic(String title, String topic) async {
  // Load CSV data once and cache it (קריאות מקבילות חולקות את אותה טעינה)
  if (_csvCache == null) {
    await (_csvCacheLoading ??= _loadCsvCache());
  }

  // For non-era topics (like 'על ברכות'), check if the commentator title contains the topic.
  // e.g. "רש"י על ברכות".contains("על ברכות") == true
  if (!_eraCategories.contains(topic) && topic != _defaultCategory) {
    return title.contains(topic);
  }

  // Check if title exists in DB cache
  if (_csvCache!.containsKey(title)) {
    final generationRaw = _csvCache![title]!;
    return generationRaw
        .split(',')
        .any((g) => _mapGenerationToCategory(g.trim()) == topic);
  }

  // ספר שאינו מתויג ב-DB משויך ל"מפרשים נוספים" בלבד
  return topic == _defaultCategory;
}

/// טוען את ה-cache של תקופות מפרשים מה-DB
Future<void> _loadCsvCache() async {
  // לא מגדירים _csvCache={} כאן — אחרת קריאה מקבילה שתבדוק `_csvCache == null`
  // תראה מפה ריקה באמצע ה-await ותסווג את כל המפרשים כ"שאר מפרשים".
  // _csvCache מקבל ערך רק בסיום הטעינה (בהצלחה או בכשל).
  try {
    final provider = SqliteDataProvider.instance;
    if (!provider.isInitialized) {
      await provider.initialize();
    }
    final db = provider.repository?.database;
    if (db != null) {
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
    } else {
      _csvCache = {};
      debugPrint('⚠️ SqliteDataProvider repository is null');
    }
  } catch (e) {
    debugPrint('⚠️ Failed to load era cache from DB: $e');
    _csvCache = {};
  }
}

/// מנקה את ה-cache של תקופות כדי לאלץ טעינה מחדש
void clearCommentatorOrderCache() {
  _csvCache = null;
  _csvCacheLoading = null;
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
    if (text[i] == '(') {
      // מחפשים את הסוגר הסוגר המתאים
      int openCount = 1;
      int j = i + 1;
      int innerOpenIndex = -1;

      // בודקים אם יש סוגר פותח נוסף בפנים
      while (j < text.length && openCount > 0) {
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

String replaceHolyNames(String s) {
  return s.replaceAllMapped(
    _holyName,
    (match) {
      if (_hasThreeContiguousHebrewLettersBeforeMatch(s, match.start)) {
        return match.group(0)!;
      }

      return 'י${match[1]}ק${match[2]}ו${match[3]}ק${match[4]}';
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

String removeSectionNames(String s) => s
    .replaceAll('פרק', '')
    .replaceAll('פסוק', '')
    .replaceAll('פסקה', '')
    .replaceAll('סעיף', '')
    .replaceAll('סימן', '')
    .replaceAll('הלכה', '')
    .replaceAll('מאמר', '')
    .replaceAll('קטן', '')
    .replaceAll('משנה', '')
    .replaceAll(RegExp(r'(?<=[א-ת])י|י(?=[א-ת])'), '')
    .replaceAll(RegExp(r'(?<=[א-ת])ו|ו(?=[א-ת])'), '')
    .replaceAll('"', '')
    .replaceAll("'", '')
    .replaceAll(',', '')
    .replaceAll(':', ' ב')
    .replaceAll('.', ' א');

String replaceParaphrases(String s) {
  s = s
      .replaceAll(' מהדורא תנינא', ' מהדו"ת')
      .replaceAll(' מהדורא', ' מהדורה')
      .replaceAll(' מהדורה', ' מהדורא')
      .replaceAll(' פני', ' פני יהושע')
      .replaceAll(' תניינא', ' תנינא')
      .replaceAll(' תנינא', ' תניינא')
      .replaceAll(' אא', ' אשל אברהם')
      .replaceAll(' אבהע', ' אבן העזר')
      .replaceAll(' אבעז', ' אבן עזרא')
      .replaceAll(' אדז', ' אדרא זוטא')
      .replaceAll(' אדרא רבה', ' אדרא')
      .replaceAll(' אדרות', ' אדרא')
      .replaceAll(' אהע', ' אבן העזר')
      .replaceAll(' אהעז', ' אבן העזר')
      .replaceAll(' אוהח', ' אור החיים')
      .replaceAll(' אוח', ' אורח חיים')
      .replaceAll(' אורח', ' אורח חיים')
      .replaceAll(' אידרא', ' אדרא')
      .replaceAll(' אידרות', ' אדרא')
      .replaceAll(' ארבעה טורים', ' טור')
      .replaceAll(' באהג', ' באר הגולה')
      .replaceAll(' באוה', ' ביאור הלכה')
      .replaceAll(' באוהל', ' ביאור הלכה')
      .replaceAll(' באור הלכה', ' ביאור הלכה')
      .replaceAll(' בב', ' בבא בתרא')
      .replaceAll(' בהגרא', ' ביאור הגרא')
      .replaceAll(' בי', ' ביאור')
      .replaceAll(' בי', ' בית יוסף')
      .replaceAll(' ביאהל', ' ביאור הלכה')
      .replaceAll(' ביאו', ' ביאור')
      .replaceAll(' ביאוה', ' ביאור הלכה')
      .replaceAll(' ביאוהג', ' ביאור הגרא')
      .replaceAll(' ביאוהל', ' ביאור הלכה')
      .replaceAll(' ביהגרא', ' ביאור הגרא')
      .replaceAll(' ביהל', ' בית הלוי')
      .replaceAll(' במ', ' בבא מציעא')
      .replaceAll(' במדבר', ' במדבר רבה')
      .replaceAll(' במח', ' באר מים חיים')
      .replaceAll(' במר', ' במדבר רבה')
      .replaceAll(' בעהט', ' בעל הטורים')
      .replaceAll(' בק', ' בבא קמא')
      .replaceAll(' בר', ' בראשית רבה')
      .replaceAll(' ברר', ' בראשית רבה')
      .replaceAll(' בש', ' בית שמואל')
      .replaceAll(' ד ', ' דף ')
      .replaceAll(' דבר', ' דברים רבה')
      .replaceAll(' דהי', ' דברי הימים')
      .replaceAll(' דויד', ' דוד')
      .replaceAll(' דמ', ' דגול מרבבה')
      .replaceAll(' דמ', ' דרכי משה')
      .replaceAll(' דמר', ' דגול מרבבה')
      .replaceAll(' דרך ה', ' דרך השם')
      .replaceAll(' דרך פיקודיך', ' דרך פקודיך')
      .replaceAll(' דרמ', ' דרכי משה')
      .replaceAll(' דרפ', ' דרך פקודיך')
      .replaceAll(' האריזל', ' הארי')
      .replaceAll(' הגהות מיימוני', ' הגהות מיימוניות')
      .replaceAll(' הגהות מימוניות', ' הגהות מיימוניות')
      .replaceAll(' הגהמ', ' הגהות מיימוניות')
      .replaceAll(' הגמ', ' הגהות מיימוניות')
      .replaceAll(' הילכות', ' הלכות')
      .replaceAll(' הל', ' הלכות')
      .replaceAll(' הלכ', ' הלכות')
      .replaceAll(' הלכה', ' הלכות')
      .replaceAll(' המשנה', ' המשניות')
      .replaceAll(' הרב', ' ר')
      .replaceAll(' הרב', ' רבי')
      .replaceAll(' הרב', ' רבינו')
      .replaceAll(' הרב', ' רבנו')
      .replaceAll(' ויקר', ' ויקרא רבה')
      .replaceAll(' ויר', ' ויקרא רבה')
      .replaceAll(' זהח', ' זוהר חדש')
      .replaceAll(' זהר חדש', ' זוהר חדש')
      .replaceAll(' זהר', ' זוהר')
      .replaceAll(' זוהח', ' זוהר חדש')
      .replaceAll(' זח', ' זוהר חדש')
      .replaceAll(' חדושי', ' חי')
      .replaceAll(' חוד', ' חוות דעת')
      .replaceAll(' חוהל', ' חובת הלבבות')
      .replaceAll(' חווד', ' חוות דעת')
      .replaceAll(' חומ', ' חושן משפט')
      .replaceAll(' חח', ' חפץ חיים')
      .replaceAll(' חי', ' חדושי')
      .replaceAll(' חידושי אגדות', ' חדושי אגדות')
      .replaceAll(' חידושי הלכות', ' חדושי הלכות')
      .replaceAll(' חידושי', ' חדושי')
      .replaceAll(' חידושי', ' חי')
      .replaceAll(' חתס', ' חתם סופר')
      .replaceAll(' יד החזקה', ' רמבם')
      .replaceAll(' יהושוע', ' יהושע')
      .replaceAll(' יוד', ' יורה דעה')
      .replaceAll(' יוט', ' יום טוב')
      .replaceAll(' יורד', ' יורה דעה')
      .replaceAll(' ילקוט', ' ילקוט שמעוני')
      .replaceAll(' ילקוש', ' ילקוט שמעוני')
      .replaceAll(' ילקש', ' ילקוט שמעוני')
      .replaceAll(' ירוש', ' ירושלמי')
      .replaceAll(' ירמי', ' ירמיהו')
      .replaceAll(' ירמיה', ' ירמיהו')
      .replaceAll(' ישעי', ' ישעיהו')
      .replaceAll(' ישעיה', ' ישעיהו')
      .replaceAll(' כופ', ' כרתי ופלתי')
      .replaceAll(' כפ', ' כרתי ופלתי')
      .replaceAll(' כרופ', ' כרתי ופלתי')
      .replaceAll(' כתס', ' כתב סופר')
      .replaceAll(' לחמ', ' לחם משנה')
      .replaceAll(' ליקוטי אמרים', ' תניא')
      .replaceAll(' מ', ' משנה')
      .replaceAll(' מאוש', ' מאור ושמש')
      .replaceAll(' מב', ' משנה ברורה')
      .replaceAll(' מגא', ' מגיני ארץ')
      .replaceAll(' מגא', ' מגן אברהם')
      .replaceAll(' מגילת', ' מגלת')
      .replaceAll(' מגמ', ' מגיד משנה')
      .replaceAll(' מד רבה', ' מדרש רבה')
      .replaceAll(' מד', ' מדרש')
      .replaceAll(' מדות', ' מידות')
      .replaceAll(' מדר', ' מדרש רבה')
      .replaceAll(' מדר', ' מדרש')
      .replaceAll(' מדרש רבא', ' מדרש רבה')
      .replaceAll(' מדת', ' מדרש תהלים')
      .replaceAll(' מהדורא תנינא', ' מהדות')
      .replaceAll(' מהדורא', ' מהדורה')
      .replaceAll(' מהדורה', ' מהדורא')
      .replaceAll(' מהרשא', ' חדושי אגדות')
      .replaceAll(' מהרשא', ' חדושי הלכות')
      .replaceAll(' מונ', ' מורה נבוכים')
      .replaceAll(' מז', ' משבצות זהב')
      .replaceAll(' ממ', ' מגיד משנה')
      .replaceAll(' מסי', ' מסילת ישרים')
      .replaceAll(' מפרג', ' מפראג')
      .replaceAll(' מקוח', ' מקור חיים')
      .replaceAll(' מרד', ' מרדכי')
      .replaceAll(' משבז', ' משבצות זהב')
      .replaceAll(' משנב', ' משנה ברורה')
      .replaceAll(' משנה תורה', ' רמבם')
      .replaceAll(' משנה', ' משניות')
      .replaceAll(' נהמ', ' נתיבות המשפט')
      .replaceAll(' נובי', ' נודע ביהודה')
      .replaceAll(' נובית', ' נודע ביהודה תניא')
      .replaceAll(' נועא', ' נועם אלימלך')
      .replaceAll(' נפהח', ' נפש החיים')
      .replaceAll(' נפש החים', ' נפש החיים')
      .replaceAll(' נתיבוש', ' נתיבות שלום')
      .replaceAll(' נתיהמ', ' נתיבות המשפט')
      .replaceAll(' ס', ' סעיף')
      .replaceAll(' סדצ', ' ספרא דצניעותא')
      .replaceAll(' סהמ', ' ספר המצוות')
      .replaceAll(' סהמצ', ' ספר המצוות')
      .replaceAll(' סי', ' סימן')
      .replaceAll(' סמע', ' מאירת עינים')
      .replaceAll(' סע', ' סעיף')
      .replaceAll(' סעי', ' סעיף')
      .replaceAll(' ספדצ', ' ספרא דצניעותא')
      .replaceAll(' ספהמצ', ' ספר המצוות')
      .replaceAll(' ספר המצות', ' ספר המצוות')
      .replaceAll(' ספרא', ' תורת כהנים')
      .replaceAll(' עמ', ' עמוד')
      .replaceAll(' עא', ' עמוד א')
      .replaceAll(' עב', ' עמוד ב')
      .replaceAll(' עהש', ' ערוך השולחן')
      .replaceAll(' עח', ' עץ חיים')
      .replaceAll(' עי', ' עין יעקב')
      .replaceAll(' ערהש', ' ערוך השולחן')
      .replaceAll(' ערוך השלחן', ' ערוך השולחן')
      .replaceAll(' פ', ' פרק')
      .replaceAll(' פי', ' פירוש')
      .replaceAll(' פיהמ', ' פירוש המשניות')
      .replaceAll(' פיהמש', ' פירוש המשניות')
      .replaceAll(' פיסקי', ' פסקי')
      .replaceAll(' פירו', ' פירוש')
      .replaceAll(' פירוש המשנה', ' פירוש המשניות')
      .replaceAll(' פמג', ' פרי מגדים')
      .replaceAll(' פני', ' פני יהושע')
      .replaceAll(' פסז', ' פסיקתא זוטרתא')
      .replaceAll(' פסיקתא זוטא', ' פסיקתא זוטרתא')
      .replaceAll(' פסיקתא רבה', ' פסיקתא רבתי')
      .replaceAll(' פסר', ' פסיקתא רבתי')
      .replaceAll(' פעח', ' פרי עץ חיים')
      .replaceAll(' פרח', ' פרי חדש')
      .replaceAll(' פרמג', ' פרי מגדים')
      .replaceAll(' פתש', ' פתחי תשובה')
      .replaceAll(' צפנפ', ' צפנת פענח')
      .replaceAll(' קדושל', ' קדושת לוי')
      .replaceAll(' קוא', ' קול אליהו')
      .replaceAll(' קידושין', ' קדושין')
      .replaceAll(' קיצור', ' קצור')
      .replaceAll(' קצהח', ' קצות החושן')
      .replaceAll(' קצוהח', ' קצות החושן')
      .replaceAll(' קצור', ' קיצור')
      .replaceAll(' קצשוע', ' קיצור שולחן ערוך')
      .replaceAll(' קשוע', ' קיצור שולחן ערוך')
      .replaceAll(' ר חיים', ' הגרח')
      .replaceAll(' ר', ' הרב')
      .replaceAll(' ר', ' ר')
      .replaceAll(' ר', ' רבי')
      .replaceAll(' ר', ' רבינו')
      .replaceAll(' ר', ' רבנו')
      .replaceAll(' רא בהרמ', ' רבי אברהם בן הרמבם')
      .replaceAll(' ראבע', ' אבן עזרא')
      .replaceAll(' ראשיח', ' ראשית חכמה')
      .replaceAll(' רבה', ' מדרש רבה')
      .replaceAll(' רבה', ' רבא')
      .replaceAll(' רבי חיים', ' הגרח')
      .replaceAll(' רבי נחמן', ' מוהרן')
      .replaceAll(' רבי נתן', ' מוהרנת')
      .replaceAll(' רבי', ' הרב')
      .replaceAll(' רבי', ' רבינו')
      .replaceAll(' רבי', ' רבנו')
      .replaceAll(' רבינו חיים', ' הגרח')
      .replaceAll(' רבינו', ' הרב')
      .replaceAll(' רבינו', ' ר')
      .replaceAll(' רבינו', ' רבי')
      .replaceAll(' רבינו', ' רבנו')
      .replaceAll(' רבנו', ' הרב')
      .replaceAll(' רבנו', ' ר')
      .replaceAll(' רבנו', ' רבי')
      .replaceAll(' רבנו', ' רבינו')
      .replaceAll(' רח', ' רבנו חננאל')
      .replaceAll(' ריהל', ' רבי יהודה הלוי')
      .replaceAll(' רעא', ' רבי עקיבא איגר')
      .replaceAll(' רעמ', ' רעיא מהימנא')
      .replaceAll(' רעקא', ' רבי עקיבא איגר')
      .replaceAll(' שבהל', ' שבלי הלקט')
      .replaceAll(' שהג', ' שער הגלגולים')
      .replaceAll(' שהש', ' שיר השירים')
      .replaceAll(' שולחן ערוך הגרז', ' שולחן ערוך הרב')
      .replaceAll(' שוע הגאון רבי זלמן', ' שוע הגרז')
      .replaceAll(' שוע הגאון רבי זלמן', ' שוע הרב')
      .replaceAll(' שוע הגרז', ' שוע הרב')
      .replaceAll(' שוע הרב', ' שולחן ערוך הרב')
      .replaceAll(' שוע הרב', ' שוע הגרז')
      .replaceAll(' שוע', ' שולחן ערוך')
      .replaceAll(' שורש', ' שרש')
      .replaceAll(' שורשים', ' שרשים')
      .replaceAll(' שות', ' תשו')
      .replaceAll(' שות', ' תשובה')
      .replaceAll(' שות', ' תשובות')
      .replaceAll(' שטה מקובצת', ' שיטה מקובצת')
      .replaceAll(' שטמק', ' שיטה מקובצת')
      .replaceAll(' שיהש', ' שיר השירים')
      .replaceAll(' שיטמק', ' שיטה מקובצת')
      .replaceAll(' שך', ' שפתי כהן')
      .replaceAll(' שלחן ערוך', ' שולחן ערוך')
      .replaceAll(' שמור', ' שמות רבה')
      .replaceAll(' שמטה', ' שמיטה')
      .replaceAll(' שמיהל', ' שמירת הלשון')
      .replaceAll(' שע', ' שולחן ערוך')
      .replaceAll(' שעק', ' שערי קדושה')
      .replaceAll(' שעת', ' שערי תשובה')
      .replaceAll(' שפח', ' שפתי חכמים')
      .replaceAll(' שפתח', ' שפתי חכמים')
      .replaceAll(' תבואש', ' תבואות שור')
      .replaceAll(' תבוש', ' תבואות שור')
      .replaceAll(' תהילים', ' תהלים')
      .replaceAll(' תהלים', ' תהילים')
      .replaceAll(' תוכ', ' תורת כהנים')
      .replaceAll(' תומד', ' תומר דבורה')
      .replaceAll(' תוס', ' תוספות')
      .replaceAll(' תוס', ' תוספתא')
      .replaceAll(' תוספ', ' תוספתא')
      .replaceAll(' תנדא', ' תנא דבי אליהו')
      .replaceAll(' תנדבא', ' תנא דבי אליהו')
      .replaceAll(' תנח', ' תנחומא')
      .replaceAll(' תניינא', ' תנינא')
      .replaceAll(' תנינא', ' תניינא')
      .replaceAll(' תקוז', ' תיקוני זוהר')
      .replaceAll(' תשו', ' שות')
      .replaceAll(' תשו', ' תשובה')
      .replaceAll(' תשו', ' תשובות')
      .replaceAll(' תשובה', ' שות')
      .replaceAll(' תשובה', ' תשו')
      .replaceAll(' תשובה', ' תשובות')
      .replaceAll(' תשובות', ' שות')
      .replaceAll(' תשובות', ' תשו')
      .replaceAll(' תשובות', ' תשובה')
      .replaceAll(' תשובת', ' שות')
      .replaceAll(' תשובת', ' תשו')
      .replaceAll(' תשובת', ' תשובה')
      .replaceAll(' תשובת', ' תשובות');

  if (s.startsWith("טז")) {
    s = s.replaceFirst("טז", "טורי זהב");
  }

  if (s.startsWith("מב")) {
    s = s.replaceFirst("מב", "משנה ברורה");
  }

  return s;
}

//פונקציה לחלוקת מפרשים לפי תקופה
Future<Map<String, List<String>>> splitByEra(
  List<String> titles,
) async {
  // טעינת ה-cache פעם אחת בהתחלה (אם עדיין לא נטען).
  // קריאות מקבילות חולקות את אותה טעינה ולא רואות מפה ריקה באמצע.
  if (_csvCache == null) {
    await (_csvCacheLoading ??= _loadCsvCache());
  }

  // יוצרים מבנה נתונים ריק לכל הקטגוריות
  final Map<String, List<String>> byEra = {
    for (var category in _eraCategories) category: [],
    _defaultCategory: [],
  };

  // ממיינים כל פרשן לקטגוריה הראשונה שמתאימה לו (סינכרוני!)
  for (final t in titles) {
    final category = _getTopicSync(t);
    byEra[category]!.add(t);
  }

  // מחזירים את כל הקטגוריות, גם אם הן ריקות
  return byEra;
}

/// גרסה סינכרונית של hasTopic - משתמשת ב-cache שכבר נטען
String _getTopicSync(String title) {
  // הדור נלקח מטבלת book_generation ב-DB; ספר שאינו מתויג -> "מפרשים נוספים"
  if (_csvCache != null && _csvCache!.containsKey(title)) {
    final generationRaw = _csvCache![title]!;
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
