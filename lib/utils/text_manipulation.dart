import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/utils/regex_patterns.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/settings/settings_repository.dart';

String stripHtmlIfNeeded(String text) {
  return text.replaceAll(SearchRegexPatterns.htmlStripper, '');
}

String truncate(String text, int length) {
  return text.length > length ? '${text.substring(0, length)}...' : text;
}

String removeVolwels(String s) {
  s = s.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
  return s.replaceAll(SearchRegexPatterns.vowelsAndCantillation, '');
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

String highLight(
  String data,
  String searchQuery, {
  int currentIndex = -1,
  Map<String, Map<String, bool>> searchOptions = const {},
  Map<int, List<String>> alternativeWords = const {},
  Map<String, String> spacingValues = const {},
  bool isFuzzy = false,
}) {
  if (searchQuery.isEmpty) return data;

  // Debug print
  // debugPrint('highLight: query="$searchQuery", options=$searchOptions');

  // 1. חילוץ מילות החיפוש כולל מילים חילופיות
  final originalWords = searchQuery
      .trim()
      .replaceAll(RegExp(r'[~"*\(\)]'), ' ')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();

  final searchTerms = <String>[];
  for (int i = 0; i < originalWords.length; i++) {
    final word = originalWords[i];
    final wordKey = '${word}_$i';

    // בדיקת אפשרויות החיפוש למילה הזו
    final wordOptions = searchOptions[wordKey] ?? {};
    final hasFullPartialSpelling = wordOptions['כתיב מלא/חסר'] == true;

    if (hasFullPartialSpelling) {
      searchTerms.addAll(generateFullPartialSpellingVariations(word));
    } else {
      searchTerms.add(word);
    }

    // הוספת מילים חילופיות אם יש
    final alternatives = alternativeWords[i];
    if (alternatives != null && alternatives.isNotEmpty) {
      if (hasFullPartialSpelling) {
        for (final alt in alternatives) {
          searchTerms.addAll(generateFullPartialSpellingVariations(alt));
        }
      } else {
        searchTerms.addAll(alternatives);
      }
    }
  }

  if (searchTerms.isEmpty) return data;

  // יצירת regex שמתעלם מניקוד עבור כל מונח חיפוש
  final patterns = searchTerms.map((term) {
    final cleanTerm = removeVolwels(term);
    return cleanTerm.split('').map((char) {
      if (RegExp(r'[א-ת]').hasMatch(char)) {
        return '${RegExp.escape(char)}[\u0591-\u05C7]*';
      }
      return RegExp.escape(char);
    }).join();
  }).toList();

  // איחוד כל התבניות ל-regex אחד גדול
  final combinedPattern = patterns.join('|');
  final regex = RegExp(combinedPattern, caseSensitive: false);
  final matches = regex.allMatches(data).toList();

  if (matches.isEmpty) return data;

  // אם לא צוין אינדקס נוכחי, נדגיש את כל התוצאות באדום
  if (currentIndex == -1) {
    String result = data;
    int offset = 0;

    for (final match in matches) {
      final matchedText = match.group(0)!;
      final replacement = '<span style="color: red">$matchedText</span>';

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
    final match = matches[i];
    final matchedText = match.group(0)!;
    final color = i == currentIndex ? 'blue' : 'red';
    final backgroundColor =
        i == currentIndex ? 'background-color: yellow;' : '';
    final replacement =
        '<span style="color: $color; $backgroundColor">$matchedText</span>';

    final start = match.start + offset;
    final end = match.end + offset;

    result = result.substring(0, start) + replacement + result.substring(end);
    offset += replacement.length - matchedText.length;
  }

  return result;
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

int countMatches(String text, String searchQuery) {
  if (searchQuery.isEmpty) return 0;
  // אותו רג'קס כמו ב-highLight
  final RegExp regex = RegExp(
    RegExp.escape(searchQuery),
    caseSensitive: false,
  );
  return regex.allMatches(text).length;
}

Future<bool> hasTopic(String title, String topic) async {
  // Load CSV data once and cache it
  if (_csvCache == null) {
    await _loadCsvCache();
  }

  // Check if title exists in CSV cache
  if (_csvCache!.containsKey(title)) {
    final generation = _csvCache![title]!;
    final mappedCategory = _mapGenerationToCategory(generation);
    return mappedCategory == topic;
  }

  // Book not found in CSV, it's "מפרשים נוספים"
  if (topic == 'מפרשים נוספים') {
    return true;
  }

  // Fallback to original path-based logic
  final location = await BookLocator.locateBook(title);
  return location?.filePath?.contains(topic) ?? false;
}

Future<void> _loadCsvCache() async {
  _csvCache = {};

  try {
    final libraryPath =
        Settings.getValue<String>(SettingsRepository.keyLibraryPath) ?? '.';
    final csvPath =
        '$libraryPath${Platform.pathSeparator}אוצריא${Platform.pathSeparator}אודות התוכנה${Platform.pathSeparator}סדר הדורות.csv';
    final csvFile = File(csvPath);

    if (await csvFile.exists()) {
      final csvString = await csvFile.readAsString();
      final lines = csvString.split('\n');

      // Skip header and parse all lines
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // Parse CSV line properly - handle commas inside quoted fields
        final parts = _parseCsvLine(line);
        if (parts.length >= 2) {
          final bookTitle = parts[0].trim();
          final generation = parts[1].trim();
          _csvCache![bookTitle] = generation;
        }
      }
    }
  } catch (e) {
    // If CSV fails, keep empty cache
    _csvCache = {};
  }
}

/// Clears the CSV cache to force reload on next access
void clearCommentatorOrderCache() {
  _csvCache = null;
}

// Helper function to parse CSV line with proper comma handling
List<String> _parseCsvLine(String line) {
  final List<String> result = [];
  bool inQuotes = false;
  String currentField = '';

  for (int i = 0; i < line.length; i++) {
    final char = line[i];

    if (char == '"') {
      // Handle escaped quotes (double quotes)
      if (i + 1 < line.length && line[i + 1] == '"' && inQuotes) {
        currentField += '"';
        i++; // Skip the next quote
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      result.add(currentField.trim());
      currentField = '';
    } else {
      currentField += char;
    }
  }

  // Add the last field
  result.add(currentField.trim());

  return result;
}

// Helper function to map CSV generation to our categories
String _mapGenerationToCategory(String generation) {
  switch (generation) {
    case 'תורה שבכתב':
      return 'תורה שבכתב';
    case 'חז"ל':
      return 'חז"ל';
    case 'ראשונים':
      return 'ראשונים';
    case 'אחרונים':
      return 'אחרונים';
    case 'מחברי זמננו':
      return 'מחברי זמננו';
    default:
      return 'מפרשים נוספים';
  }
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
    SearchRegexPatterns.holyName,
    (match) => 'י${match[1]}ק${match[2]}ו${match[3]}ק${match[4]}',
  );
}

String removeTeamim(String s) => s
    .replaceAll('־', ' ')
    .replaceAll(' ׀', '')
    .replaceAll('ֽ', '')
    .replaceAll('׀', '')
    .replaceAll(SearchRegexPatterns.cantillationOnly, '');

String removeSectionNames(String s) {
  // Handle Amudim first (more specific)
  s = s
      .replaceAll('עמוד א', ' . ')
      .replaceAll('עמוד ב', ' : ')
      .replaceAll('ע"א', ' . ')
      .replaceAll('ע"ב', ' : ')
      .replaceAll('עא', ' . ')
      .replaceAll('עב', ' : ');

  // Handle common section names
  s = s.replaceAll(
      RegExp(r'פרק|פסוק|פסקה|סעיף|סימן|הלכה|מאמר|קטן|משנה|דף|עמוד'), ' ');

  // Standard cleanup
  s = s.replaceAll('"', '').replaceAll("'", '').replaceAll(',', '');

  return s;
}

String normalizeReference(String s) {
  s = ' $s '; // Add spaces for easier word boundary matching

  // Section abbreviations
  s = s
      .replaceAll(' ד ', ' דף ')
      .replaceAll(' פ ', ' פרק ')
      .replaceAll(' ס ', ' סעיף ')
      .replaceAll(' סי ', ' סימן ')
      .replaceAll(' עמ ', ' עמוד ');

  s = removeSectionNames(s);
  s = s.replaceAll('.', ' . ').replaceAll(':', ' : ');
  s = removeTeamim(removeVolwels(s));
  s = s.replaceAll('\u05F4', '').replaceAll('\u05F3', '');
  s = s.replaceAll(RegExp(r'[^a-zA-Z0-9\u0590-\u05FF\s.:]'), ' ');

  return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

@Deprecated(
    'Use normalizeReference directly. This function is kept for backward compatibility.')
String replaceParaphrases(String s) {
  return normalizeReference(s);
}

//פונקציה לחלוקת מפרשים לפי תקופה
Future<Map<String, List<String>>> splitByEra(
  List<String> titles,
) async {
  // יוצרים מבנה נתונים ריק לכל הקטגוריות החדשות
  final Map<String, List<String>> byEra = {
    'תורה שבכתב': [],
    'חז"ל': [],
    'ראשונים': [],
    'אחרונים': [],
    'מחברי זמננו': [],
    'מפרשים נוספים': [],
  };

  // ממיינים כל פרשן לקטגוריה הראשונה שמתאימה לו
  for (final t in titles) {
    if (await hasTopic(t, 'תורה שבכתב')) {
      byEra['תורה שבכתב']!.add(t);
    } else if (await hasTopic(t, 'חז"ל')) {
      byEra['חז"ל']!.add(t);
    } else if (await hasTopic(t, 'ראשונים')) {
      byEra['ראשונים']!.add(t);
    } else if (await hasTopic(t, 'אחרונים')) {
      byEra['אחרונים']!.add(t);
    } else if (await hasTopic(t, 'מחברי זמננו')) {
      byEra['מחברי זמננו']!.add(t);
    } else {
      // כל ספר שלא נמצא בקטגוריות הקודמות יוכנס ל"מפרשים נוספים"
      byEra['מפרשים נוספים']!.add(t);
    }
  }

  // מחזירים את כל הקטגוריות, גם אם הן ריקות
  return byEra;
}
