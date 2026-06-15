import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

/// רגקס להסרת תגי HTML וישויות.
final RegExp _htmlStripper = RegExp(r'<[^>]*>|&[^;]+;');

/// רגקס להסרת ניקוד וטעמים.
final RegExp _vowelsAndCantillation = RegExp(r'[֑-ׇ]');

/// מחלקת-תווים של ניקוד וטעמים *הצמודים לאות* — ללא מקף (U+05BE) ופסק (U+05C0),
/// שהם מפרידי מילים. אילו נכללו, ה-`*` היה בולע מקף בין מילים ושובר את
/// זיהוי גבול המילה (וכך את הדגשת ביטוי כמו "אשר־שמע").
const String _attachedNikudClass = '֑-ֽֿׁ-ׇ';
final RegExp _attachedNikud = RegExp('[$_attachedNikudClass]');

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

String stripHtmlIfNeeded(String text) {
  // Replace whitespace HTML entities with actual spaces before stripping,
  // otherwise adjacent words get merged (e.g. "לאמר&nbsp;&nbsp;שירה" → "לאמרשירה")
  final withSpaces = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&thinsp;', ' ')
      .replaceAll('&ensp;', ' ')
      .replaceAll('&emsp;', ' ');
  return withSpaces.replaceAll(_htmlStripper, '');
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
/// מסיר " ״ כשזה לא באמצע מילה
/// מסיר מעבר שורה אם אין . או : בסוף השורה המקורית
String removePunctuation(String text) {
  if (text.isEmpty) return text;

  final hadHtmlBreaks =
      RegExp(r'<br\s*/?>', caseSensitive: false).hasMatch(text);
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

    final lastAllowedPunctuationMatch =
        RegExp(r'[.:](\s*)$').firstMatch(processed);
    final lastAllowedPunctuationIndex = lastAllowedPunctuationMatch?.start;

    // הסרה לינארית של פיסוק, עם תמיכה בסוגריים מקוננים.
    // בתוך סוגריים שומרים רק . ו- :
    final buffer = StringBuffer();
    var parenDepth = 0;
    for (var i = 0; i < processed.length; i++) {
      final ch = processed[i];

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

      final isPunctuation = ch == '!' ||
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

    processed = processed.replaceAllMapped(
      RegExp(r'["״]'),
      (match) {
        final index = match.start;
        final hasBefore =
            index > 0 && RegExp(r'[א-תa-zA-Z]').hasMatch(processed[index - 1]);
        final hasAfter = index < processed.length - 1 &&
            RegExp(r'[א-תa-zA-Z]').hasMatch(processed[index + 1]);
        if (hasBefore && hasAfter) {
          return match.group(0)!;
        }
        return '';
      },
    );

    processedLines.add(processed);
  }

  final finalResult = StringBuffer();
  bool lastCharWasNewline = false;
  bool lastCharWasSpace = false;

  for (int i = 0; i < processedLines.length; i++) {
    final line = processedLines[i];
    final shouldKeepNewline = originalEndsWithAllowed[i] ||
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

bool isHeadingLine(String line) {
  final trimmedLine = line.trim();
  if (trimmedLine.isEmpty) return false;
  return RegExp(r'^<h[1-6][^>]*>.*?</h[1-6]>$', caseSensitive: false)
          .hasMatch(trimmedLine) ||
      RegExp(r'^#{1,6}\s').hasMatch(trimmedLine);
}

/// בדיקה אם טקסט מכיל ניקוד או טעמים
bool hasNikud(String text) {
  return _vowelsAndCantillation.hasMatch(text);
}

List<String> generateFullPartialSpellingVariations(String word) {
  if (word.isEmpty) return [word];

  final variations = <String>{word}; // המילה המקורית

  // מוצא את כל המיקומים של י, ו, וגרשיים
  final chars = word.split('');
  final optionalIndices = <int>[];

  // מוצא אינדקסים של תווים שיכולים להיות אופציונליים
  for (int i = 0; i < chars.length; i++) {
    if (chars[i] == 'י' ||
        chars[i] == 'ו' ||
        chars[i] == "'" ||
        chars[i] == '"') {
      optionalIndices.add(i);
    }
  }

  // יוצר את כל הצירופים האפשריים (2^n אפשרויות)
  final numCombinations = 1 << optionalIndices.length; // 2^n

  for (int combination = 0; combination < numCombinations; combination++) {
    final variant = <String>[];

    for (int i = 0; i < chars.length; i++) {
      // אם התו הוא לא אופציונלי, תמיד מוסיפים אותו
      if (!optionalIndices.contains(i)) {
        variant.add(chars[i]);
      } else {
        // אם התו אופציונלי, בודקים אם הביט המתאים דולק
        final optionalIndex = optionalIndices.indexOf(i);
        if ((combination >> optionalIndex) & 1 == 1) {
          variant.add(chars[i]);
        }
      }
    }
    variations.add(variant.join());
  }

  return variations.toList();
}

String _highlightWordSeparator({int maxIntermediateWords = 0}) {
  const separator =
      r'''(?:\s|[\u0591-\u05C7]|<[^>]*>|[.,:;!?'"״׳־\-–—()\[\]{}])+''';
  if (maxIntermediateWords <= 0) {
    return separator;
  }

  return '$separator(?:\\S+$separator){0,$maxIntermediateWords}';
}

int _maxSpacingValue(Map<String, String> spacingValues) {
  var maxSpacing = 0;
  for (final value in spacingValues.values) {
    final spacing = int.tryParse(value) ?? 0;
    if (spacing > maxSpacing) {
      maxSpacing = spacing;
    }
  }
  return maxSpacing;
}

String _highlightSeparatorForIndex(
  Map<String, String> spacingValues,
  int index,
) {
  final maxIntermediateWords =
      int.tryParse(spacingValues['$index-${index + 1}'] ?? '') ??
          _maxSpacingValue(spacingValues);
  return _highlightWordSeparator(maxIntermediateWords: maxIntermediateWords);
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

bool _isHebrewMark(String char) {
  return _attachedNikud.hasMatch(char);
}

bool _isSearchTokenChar(String char) {
  return RegExp(r'[א-תA-Za-z0-9]').hasMatch(char);
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
  List<List<String>> patternGroups,
  List<bool> requireTokenBoundaries,
) {
  final ranges = <_HighlightRange>[];
  var searchOffset = 0;

  for (var i = 0; i < patternGroups.length; i++) {
    final group = patternGroups[i];
    final wordPattern =
        group.length == 1 ? group.first : '(?:${group.join('|')})';
    final wordRegex = RegExp(wordPattern, caseSensitive: false);
    final searchText = matchedText.substring(searchOffset);
    final wordMatch = wordRegex.firstMatch(searchText);
    if (wordMatch == null) {
      return null;
    }

    final wordStart = searchOffset + wordMatch.start;
    final wordEnd = searchOffset + wordMatch.end;
    final absoluteStart = matchStart + wordStart;
    final absoluteEnd = matchStart + wordEnd;

    if (requireTokenBoundaries[i] &&
        (!_hasTokenBoundaryBefore(fullText, absoluteStart) ||
            !_hasTokenBoundaryAfter(fullText, absoluteEnd))) {
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
  final highlighted = matchedText.substring(start, end).splitMapJoin(
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
}) {
  if (searchQuery.isEmpty) return data;

  // 1. חילוץ מילות החיפוש כולל מילים חילופיות
  final originalWords = SearchQueryBuilder.sanitizeQuery(searchQuery)
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
  final effectiveSpacingValues = SearchQueryBuilder.effectiveSpacingValues(
    wordCount: originalWords.length,
    spacingValues: spacingValues,
    searchDistance: searchDistance,
  );

  // בניית קבוצת patterns לכל מילה בנפרד (כולל חלופות לכל מיקום)
  final patternGroups = <List<String>>[];
  final requireTokenBoundaries = <bool>[];
  for (int i = 0; i < originalWords.length; i++) {
    final word = originalWords[i];
    final wordKey = '${word}_$i';

    // בדיקת אפשרויות החיפוש למילה הזו
    final wordOptions = searchOptions[wordKey] ?? {};
    final hasPrefix = wordOptions['קידומות'] == true;
    final hasSuffix = wordOptions['סיומות'] == true;
    final hasGrammaticalPrefixes = wordOptions['קידומות דקדוקיות'] == true;
    final hasGrammaticalSuffixes = wordOptions['סיומות דקדוקיות'] == true;
    final hasFullPartialSpelling = wordOptions['כתיב מלא/חסר'] == true;
    final hasPartialWord = wordOptions['חלק ממילה'] == true;
    final hasWordExpansion = hasPrefix ||
        hasSuffix ||
        hasGrammaticalPrefixes ||
        hasGrammaticalSuffixes ||
        hasPartialWord;

    final wordTerms = <String>[];
    if (hasFullPartialSpelling) {
      wordTerms.addAll(generateFullPartialSpellingVariations(word));
    } else {
      wordTerms.add(word);
    }

    // הוספת מילים חילופיות אם יש
    final alternatives = alternativeWords[i];
    if (alternatives != null && alternatives.isNotEmpty) {
      if (hasFullPartialSpelling) {
        for (final alt in alternatives) {
          wordTerms.addAll(generateFullPartialSpellingVariations(alt));
        }
      } else {
        wordTerms.addAll(alternatives);
      }
    }

    // המרת כל term ל-pattern regex עם תמיכה בניקוד
    final wordPatterns = wordTerms.map((term) {
      final cleanTerm = removeVolwels(term);
      return cleanTerm.split('').map((char) {
        if (RegExp(r'[א-ת]').hasMatch(char)) {
          return '${RegExp.escape(char)}[$_attachedNikudClass]*';
        }
        if (char == '"') return '["״]';
        if (char == "'") return "['׳]";
        return RegExp.escape(char);
      }).join();
    }).toList();

    patternGroups.add(wordPatterns);
    // בהדגשת ציטוט (רקע צהוב) הטקסט הועתק מהמקטע עצמו ועשוי להיקטע
    // באמצע מילה — דרישת גבולות מילה תפסול אז את כל ההדגשה.
    requireTokenBoundaries.add(!hasWordExpansion && !yellowBackground);
  }

  if (patternGroups.isEmpty) return data;

  // בניית ה-pattern המשולב:
  // - מילה אחת: OR פשוט בין החלופות
  // - כמה מילים: pattern רצפי - כל מילה חייבת להופיע לפי הסדר
  //   ובין מילים: רווח לבן, ניקוד, או תגי HTML (למניעת החמצה בגלל HTML בטקסט)
  String combinedPattern;
  if (patternGroups.length == 1) {
    final patterns = patternGroups.first;
    combinedPattern =
        patterns.length == 1 ? patterns.first : '(?:${patterns.join('|')})';
  } else {
    final wordPatternStrings = patternGroups.map((group) {
      return group.length == 1 ? group.first : '(?:${group.join('|')})';
    }).toList();
    final patternParts = <String>[];
    for (var i = 0; i < wordPatternStrings.length; i++) {
      patternParts.add(wordPatternStrings[i]);
      if (i < wordPatternStrings.length - 1) {
        patternParts
            .add(_highlightSeparatorForIndex(effectiveSpacingValues, i));
      }
    }
    combinedPattern = patternParts.join();
  }
  final regex = RegExp(combinedPattern, caseSensitive: false);
  final matches = regex
      .allMatches(data)
      .map((match) {
        final matchedText = match.group(0)!;
        final ranges = _collectMatchedSearchWordRanges(
          data,
          matchedText,
          match.start,
          patternGroups,
          requireTokenBoundaries,
        );
        return ranges == null ? null : _HighlightMatch(match, ranges);
      })
      .whereType<_HighlightMatch>()
      .toList();

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
    final backgroundColor =
        i == currentIndex ? 'background-color: yellow;' : '';
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

/// מנרמל נתיב קטגוריה לפורמט אחיד מופרד בפסיקים.
///
/// ממיר נתיבי קבצים (\\ ו /) לפסיקים, מסיר סיומות קבצים
/// ומחזיר מחרוזת נקייה בפורמט "a, b, c".
String normalizeCategoryPath(String rawPath) {
  if (rawPath.isEmpty) return rawPath;
  final normalized = rawPath
      .replaceAll('\\', ', ')
      .replaceAll('/', ', ')
      .replaceAll('.txt', '')
      .replaceAll('.docx', '')
      .replaceAll('.pdf', '');
  return normalized
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty && part != '.')
      .join(', ');
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

int countMatches(String text, String searchQuery) {
  if (searchQuery.isEmpty) return 0;

  // ניקוי תווים מיוחדים מהשאילתה
  final cleanedQuery = SearchQueryBuilder.sanitizeQuery(searchQuery);

  if (cleanedQuery.isEmpty) return 0;

  // אותו רג'קס כמו ב-highLight
  final RegExp regex = RegExp(
    RegExp.escape(cleanedQuery),
    caseSensitive: false,
  );
  return regex.allMatches(text).length;
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

  // Book not found in CSV, it's "מפרשים נוספים"
  if (topic == _defaultCategory) {
    return true;
  }

  // Fallback to original path-based logic
  final location = await BookLocator.locateBook(title);
  return location?.filePath?.contains(topic) ?? false;
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
      _csvCache = await db.authorDao.getAllBookTitleToGeneration();
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

  // טעינת titleToPath פעם אחת (לא בכל איטרציה)
  final titleToPath = await FileSystemData.instance.titleToPath;

  // יוצרים מבנה נתונים ריק לכל הקטגוריות
  final Map<String, List<String>> byEra = {
    for (var category in _eraCategories) category: [],
    _defaultCategory: [],
  };

  // ממיינים כל פרשן לקטגוריה הראשונה שמתאימה לו (סינכרוני!)
  for (final t in titles) {
    final category = _getTopicSync(t, titleToPath);
    byEra[category]!.add(t);
  }

  // מחזירים את כל הקטגוריות, גם אם הן ריקות
  return byEra;
}

/// גרסה סינכרונית של hasTopic - משתמשת ב-cache שכבר נטען
String _getTopicSync(String title, Map<String, String> titleToPath) {
  // בדיקה ב-DB cache
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

  // Fallback לפי נתיב
  final path = titleToPath[title];
  if (path != null) {
    final normalizedPath = normalizeCategoryPath(path);
    for (var category in _eraCategories) {
      if (normalizedPath.contains(category)) return category;
    }
  }

  return _defaultCategory;
}
