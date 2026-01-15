import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/utils/regex_patterns.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';

String stripHtmlIfNeeded(String text) {
  return text.replaceAll(SearchRegexPatterns.htmlStripper, '');
}

String truncate(String text, int length) {
  return text.length > length ? '${text.substring(0, length)}...' : text;
}

String removeVolwels(String s) {
  s = s.replaceAll('־', ' ').replaceAll('׀', ' ').replaceAll('|', ' ');
  final result = s.replaceAll(SearchRegexPatterns.vowelsAndCantillation, '');
  return result;
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
  // Check if generation matches any of the era categories
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
  // טעינת ה-cache פעם אחת בהתחלה (אם עדיין לא נטען)
  if (_csvCache == null) {
    await _loadCsvCache();
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
  // בדיקה ב-CSV cache
  if (_csvCache != null && _csvCache!.containsKey(title)) {
    final generation = _csvCache![title]!;
    return _mapGenerationToCategory(generation);
  }

  // Fallback לפי נתיב
  final path = titleToPath[title];
  if (path != null) {
    for (var category in _eraCategories) {
      if (path.contains(category)) return category;
    }
  }

  return _defaultCategory;
}
/// פונקציה להדגשה מדויקת של טקסט שמתעלמת משינויים קלים כמו ניקוד וטעמים
/// מיועדת להדגשה ספציפית במקום חיפוש כללי
/// עם תמיכה ב-fuzzy matching למשפטים ארוכים ומילים מרובות
String exactHighlight(String text, String searchTerm, {bool fuzzyForLongText = false}) {
  if (searchTerm.isEmpty || text.isEmpty) {
    return text;
  }

  // עבור מילים מרובות או טקסט ארוך, תמיד נשתמש ב-fuzzy matching אם הפרמטר מופעל
  final hasMultipleWords = searchTerm.trim().contains(' ');
  final isLongText = searchTerm.length > 10; // גם עבור טקסט ארוך
  
  if (fuzzyForLongText && (hasMultipleWords || isLongText)) {
    return unlimitedHighlight(text, searchTerm);
  }

  // נרמול הטקסטים - הסרת ניקוד, טעמים, תגי HTML ומקפים
  String normalizeText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }

  final normalizedText = normalizeText(text);
  final normalizedSearchTerm = normalizeText(searchTerm);

  // בדיקה אם המונח המנורמל קיים בטקסט המנורמל
  if (!normalizedText.contains(normalizedSearchTerm)) {
    // במקום לוותר, ננסה unlimitedHighlight שיכול למצוא התאמות חלקיות
    return unlimitedHighlight(text, searchTerm);
  }

  // אם הטקסט נמצא, ננסה להדגיש אותו בצורה פשוטה יותר
  // נשתמש בגישה פשוטה יותר למילים מרובות
  if (hasMultipleWords) {
    return _simpleMultiWordHighlight(text, searchTerm);
  }

  // מציאת המיקום המדויק בטקסט המנורמל (לטקסט של מילה אחת)
  final startIndex = normalizedText.indexOf(normalizedSearchTerm);
  final endIndex = startIndex + normalizedSearchTerm.length;

  // עכשיו נמצא את המיקום המתאים בטקסט המקורי (עם HTML וניקוד)
  // נעבור תו אחר תו ונספור רק תווים שאינם HTML/ניקוד/טעמים/מקפים
  int originalIndex = 0;
  int normalizedIndex = 0;
  int highlightStart = -1;
  int highlightEnd = -1;

  while (originalIndex < text.length && normalizedIndex <= endIndex) {
    final char = text[originalIndex];
    
    // אם זה תחילת תג HTML, נדלג עליו
    if (char == '<') {
      final tagEnd = text.indexOf('>', originalIndex);
      if (tagEnd != -1) {
        originalIndex = tagEnd + 1;
        continue;
      }
    }
    
    // אם זה תו ניקוד או טעמים, נדלג עליו
    if (SearchRegexPatterns.vowelsAndCantillation.hasMatch(char)) {
      originalIndex++;
      continue;
    }
    
    // אם זה מקף עברי או רגיל, נתרגם לרווח
    if (char == '־' || char == '-') {
      if (normalizedIndex == startIndex) {
        highlightStart = originalIndex;
      }
      normalizedIndex++;
      if (normalizedIndex == endIndex) {
        highlightEnd = originalIndex + 1;
        break;
      }
      originalIndex++;
      continue;
    }
    
    // אם זה רווח מיותר (יותר מרווח אחד ברצף), נדלג
    if (char == ' ' || char == '\n' || char == '\t') {
      // בדוק אם יש רווח ברצף
      if (normalizedIndex < normalizedText.length && normalizedText[normalizedIndex] == ' ') {
        if (normalizedIndex == startIndex) {
          highlightStart = originalIndex;
        }
        normalizedIndex++;
        if (normalizedIndex == endIndex) {
          highlightEnd = originalIndex + 1;
          break;
        }
      }
      originalIndex++;
      continue;
    }
    
    // תו רגיל - נבדוק אם אנחנו במיקום הנכון
    if (normalizedIndex == startIndex) {
      highlightStart = originalIndex;
    }
    
    normalizedIndex++;
    
    if (normalizedIndex == endIndex) {
      highlightEnd = originalIndex + 1;
      break;
    }
    
    originalIndex++;
  }

  // אם מצאנו את המיקומים, נדגיש
  if (highlightStart != -1 && highlightEnd != -1) {
    final before = text.substring(0, highlightStart);
    final highlighted = text.substring(highlightStart, highlightEnd);
    final after = text.substring(highlightEnd);
    
    final result = '$before<mark>$highlighted</mark>$after';
    return result;
  }

  return unlimitedHighlight(text, searchTerm);
}

/// פונקציה להדגשה מטושטשת (fuzzy) למשפטים ארוכים
/// מאפשרת הבדלים קלים בעיצוב ושורות חדשות
String fuzzyHighlight(String text, String searchTerm) {
  if (kDebugMode) {
    debugPrint('fuzzyHighlight called with searchTerm: "$searchTerm"');
  }
  
  if (searchTerm.isEmpty || text.isEmpty) {
    return text;
  }

  // נרמול הטקסט והמונח לחיפוש
  String normalizeText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }

  final normalizedText = normalizeText(text);
  final normalizedSearchTerm = normalizeText(searchTerm);

  // פיצול המונח לחיפוש למילים
  final searchWords = normalizedSearchTerm.split(' ').where((word) => word.isNotEmpty).toList();
  
  // חיפוש רצפים של מילים בטקסט
  final textWords = normalizedText.split(' ');
  String bestMatch = '';
  double bestScore = 0.0;

  // חיפוש רצפים של אורכים שונים
  for (int length = searchWords.length; length >= 1; length--) {
    for (int i = 0; i <= textWords.length - length; i++) {
      final sequence = textWords.sublist(i, i + length).join(' ');
      final score = _calculateSimilarity(sequence, normalizedSearchTerm);
      
      // הורדת דרישת ההתאמה מ-70% ל-30% לגמישות מקסימלית
      if (score > bestScore && score >= 0.3) {
        bestScore = score;
        bestMatch = sequence;
      }
    }
  }

  // אם מצאנו התאמה טובה, נדגיש אותה
  if (bestMatch.isNotEmpty) {
    if (kDebugMode) {
      debugPrint('fuzzyHighlight: Found best match: "$bestMatch"');
    }
    return _highlightBestMatch(text, bestMatch);
  }

  // אם לא מצאנו התאמה טובה, ננסה חיפוש פשוט יותר
  // נחפש את כל המונח כמו שהוא (עם רווחים)
  if (normalizedText.contains(normalizedSearchTerm)) {
    if (kDebugMode) {
      debugPrint('fuzzyHighlight: Found simple match');
    }
    return _highlightBestMatch(text, normalizedSearchTerm);
  }

  // אם לא מצאנו התאמה מלאה, נדגיש את המילה הראשונה שנמצאה
  for (final word in searchWords) {
    if (normalizedText.contains(word)) {
      if (kDebugMode) {
        debugPrint('fuzzyHighlight: Found word match: "$word"');
      }
      return _highlightBestMatch(text, word);
    }
  }

  if (kDebugMode) {
    debugPrint('fuzzyHighlight: No match found');
  }
  return text;
}

/// פונקציה להדגשת טקסט ללא הגבלות - מיועדת לטקסט ארוך ומשפטים שלמים
String unlimitedHighlight(String text, String searchTerm) {
  if (kDebugMode) {
    debugPrint('unlimitedHighlight called with searchTerm: "$searchTerm"');
  }
  
  if (searchTerm.isEmpty || text.isEmpty) {
    return text;
  }

  // נרמול הטקסט והמונח לחיפוש
  String normalizeForSearch(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }

  final normalizedText = normalizeForSearch(text);
  final normalizedSearchTerm = normalizeForSearch(searchTerm);

  // חיפוש ישיר של המונח המלא
  if (normalizedText.contains(normalizedSearchTerm)) {
    if (kDebugMode) {
      debugPrint('unlimitedHighlight: Found exact match');
    }
    return _highlightBestMatch(text, normalizedSearchTerm);
  }

  // חיפוש גמיש - ננסה למצוא את הרצף הטוב ביותר
  final searchWords = normalizedSearchTerm.split(' ').where((word) => word.isNotEmpty).toList();
  final textWords = normalizedText.split(' ');
  
  // חיפוש רצף הארוך ביותר שמתאים
  String bestMatch = '';
  double bestScore = 0.0;

  // ננסה רצפים של אורכים שונים - מהארוך לקצר
  for (int length = searchWords.length; length >= 1; length--) {
    for (int startIndex = 0; startIndex <= textWords.length - length; startIndex++) {
      final sequence = textWords.sublist(startIndex, startIndex + length).join(' ');
      
      // חישוב ציון התאמה - כמה מילים מהחיפוש נמצאות ברצף
      int matchingWords = 0;
      for (final searchWord in searchWords) {
        if (sequence.contains(searchWord)) {
          matchingWords++;
        }
      }
      
      final score = matchingWords / searchWords.length;
      
      // אם מצאנו רצף טוב יותר (ציון גבוה יותר)
      // הורדנו את הסף ל-0.1 לגמישות מקסימלית
      if (score > bestScore && score >= 0.1) {
        bestScore = score;
        bestMatch = sequence;
        if (kDebugMode) {
          debugPrint('unlimitedHighlight: Found better match with score $score: "$bestMatch"');
        }
      }
    }
  }

  // אם מצאנו התאמה טובה, נדגיש אותה
  if (bestMatch.isNotEmpty) {
    if (kDebugMode) {
      debugPrint('unlimitedHighlight: Using best match: "$bestMatch"');
    }
    return _highlightBestMatch(text, bestMatch);
  }

  // חיפוש חלקי - ננסה למצוא חלק מהמונח
  final longestWord = searchWords.reduce((a, b) => a.length > b.length ? a : b);
  if (normalizedText.contains(longestWord)) {
    if (kDebugMode) {
      debugPrint('unlimitedHighlight: Using longest word: "$longestWord"');
    }
    return _highlightBestMatch(text, longestWord);
  }

  // כפתרון אחרון, נדגיש את המילה הראשונה שנמצאה
  for (final word in searchWords) {
    if (normalizedText.contains(word)) {
      if (kDebugMode) {
        debugPrint('unlimitedHighlight: Using first found word: "$word"');
      }
      return _highlightBestMatch(text, word);
    }
  }

  if (kDebugMode) {
    debugPrint('unlimitedHighlight: No match found');
  }
  return text;
}

/// פונקציה עזר לחישוב דמיון בין שני מחרוזות
double _calculateSimilarity(String text1, String text2) {
  if (text1.isEmpty || text2.isEmpty) return 0.0;
  if (text1 == text2) return 1.0;
  
  final words1 = text1.split(' ').where((w) => w.isNotEmpty).toList();
  final words2 = text2.split(' ').where((w) => w.isNotEmpty).toList();
  
  if (words1.isEmpty || words2.isEmpty) return 0.0;
  
  int matchingWords = 0;
  for (final word1 in words1) {
    for (final word2 in words2) {
      if (word1 == word2 || word1.contains(word2) || word2.contains(word1)) {
        matchingWords++;
        break;
      }
    }
  }
  
  // שיפור: נחשב את הציון על בסיס המילים הקצרות יותר
  final minLength = words1.length < words2.length ? words1.length : words2.length;
  return matchingWords / minLength;
}

/// פונקציה עזר להדגשת ההתאמה הטובה ביותר
String _highlightBestMatch(String text, String matchTerm) {
  // נרמול לחיפוש המיקום המדויק
  String normalizeText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }

  final normalizedText = normalizeText(text);
  final normalizedMatch = normalizeText(matchTerm);

  // ננסה חיפוש ישיר קודם
  int startIndex = normalizedText.indexOf(normalizedMatch);
  
  // אם לא מצאנו, ננסה חיפוש גמיש יותר
  if (startIndex == -1) {
    // ננסה לחפש חלקים מהמונח
    final matchWords = normalizedMatch.split(' ');
    for (final word in matchWords) {
      if (word.length > 2) { // רק מילים משמעותיות
        final wordIndex = normalizedText.indexOf(word);
        if (wordIndex != -1) {
          startIndex = wordIndex;
          break;
        }
      }
    }
  }
  
  if (startIndex == -1) return text;

  // מציאת המיקום המדויק בטקסט המקורי
  int highlightStart = -1;
  int highlightEnd = -1;
  
  // חיפוש פשוט יותר - נחפש את המונח בטקסט המקורי
  // ננסה קודם חיפוש ישיר
  final directIndex = text.toLowerCase().indexOf(matchTerm.toLowerCase());
  if (directIndex != -1) {
    highlightStart = directIndex;
    highlightEnd = directIndex + matchTerm.length;
  } else {
    // חיפוש מתקדם יותר
    int currentPos = 0;
    int normalizedPos = 0;
    
    while (currentPos < text.length && normalizedPos < normalizedText.length) {
      if (normalizedPos == startIndex) {
        highlightStart = currentPos;
      }
      if (normalizedPos == startIndex + normalizedMatch.length) {
        highlightEnd = currentPos;
        break;
      }
      
      final char = text[currentPos];
      final normalizedChar = normalizeText(char);
      
      if (normalizedChar.isNotEmpty) {
        normalizedPos += normalizedChar.length;
      }
      currentPos++;
    }
    
    // אם לא מצאנו את הסוף, נשתמש באורך המונח
    if (highlightEnd == -1 && highlightStart != -1) {
      highlightEnd = (highlightStart + matchTerm.length).clamp(0, text.length);
    }
  }

  // הדגשה אם מצאנו מיקומים
  if (highlightStart != -1 && highlightEnd != -1) {
    final before = text.substring(0, highlightStart);
    final highlighted = text.substring(highlightStart, highlightEnd);
    final after = text.substring(highlightEnd);
    return '$before<mark>$highlighted</mark>$after';
  }

  return text;
}

/// פונקציה לחיפוש טקסט בכל המקטעים ומציאת האינדקס הנכון
int? findTextInContent(List<String> content, String searchTerm) {
  if (searchTerm.isEmpty) {
    return null;
  }
  
  // נרמול הטקסט לחיפוש
  String normalizeText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', '') // הסרת מקף עברי
        .replaceAll('-', '') // הסרת מקף רגיל
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }
  
  final normalizedSearchTerm = normalizeText(searchTerm);
  
  for (int i = 0; i < content.length; i++) {
    final normalizedContent = normalizeText(content[i]);
    if (normalizedContent.contains(normalizedSearchTerm)) {
      return i;
    }
  }
  
  return null;
}

/// פונקציה לחיפוש טקסט במקטע הנוכחי ובמקטעים הסמוכים בלבד
/// מחזירה את האינדקס אם נמצא, או null אם לא נמצא בטווח המוגבל
int? findTextInNearbyContent(List<String> content, String searchTerm, int originalIndex) {
  if (searchTerm.isEmpty || content.isEmpty) {
    return null;
  }
  
  // נרמול הטקסט לחיפוש - טיפול משופר במילים מרובות
  String normalizeText(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // הסרת תגי HTML
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }
  
  // נרמול מונח החיפוש עם טיפול מיוחד ב-%20 ורווחים
  String normalizedSearchTerm = searchTerm
      .replaceAll('%20', ' ')  // המרת %20 לרווח
      .replaceAll('+', ' ')    // המרת + לרווח (אם יש)
      .trim();
  
  normalizedSearchTerm = normalizeText(normalizedSearchTerm);
  
  // חיפוש במקטע המקורי ובמקטעים הסמוכים (±2)
  final startIndex = (originalIndex - 2).clamp(0, content.length - 1);
  final endIndex = (originalIndex + 2).clamp(0, content.length - 1);
  
  for (int i = startIndex; i <= endIndex; i++) {
    final normalizedContent = normalizeText(content[i]);
    if (normalizedContent.contains(normalizedSearchTerm)) {
      return i;
    }
  }
  
  return null;
}

/// פונקציה פשוטה להדגשת טקסט ארוך ללא הגבלות
/// מיועדת לטקסט של כמה מילים או שורות שלמות
String simpleUnlimitedHighlight(String text, String searchTerm) {
  if (searchTerm.isEmpty || text.isEmpty) {
    return text;
  }

  // נרמול פשוט
  String simpleNormalize(String input) {
    return input
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim()
        .toLowerCase();
  }

  final normalizedText = simpleNormalize(text);
  final normalizedSearchTerm = simpleNormalize(searchTerm);

  // חיפוש ישיר
  if (normalizedText.contains(normalizedSearchTerm)) {
    // מציאת המיקום בטקסט המקורי
    final index = text.toLowerCase().indexOf(searchTerm.toLowerCase());
    if (index != -1) {
      final before = text.substring(0, index);
      final match = text.substring(index, index + searchTerm.length);
      final after = text.substring(index + searchTerm.length);
      return '$before<mark>$match</mark>$after';
    }
  }

  // אם לא מצאנו התאמה ישירה, ננסה חיפוש גמיש
  return unlimitedHighlight(text, searchTerm);
}

/// פונקציה להדגשת כל המקטע (עבור text=true)
String highlightFullSection(String sectionText) {
  if (sectionText.isEmpty) {
    return sectionText;
  }
  
  // הדגשה עדינה עם צהוב בהיר
  final result = '<div style="background-color: #ffff99; padding: 4px; margin: 4px 0; border-radius: 4px;">$sectionText</div>';
  return result;
}

/// פונקציה פשוטה להדגשת טקסט רב-מילים
String _simpleMultiWordHighlight(String text, String searchTerm) {
  // נרמול פשוט
  String simpleNormalize(String input) {
    return input
        .replaceAll(SearchRegexPatterns.vowelsAndCantillation, '') // הסרת ניקוד וטעמים
        .replaceAll('־', ' ') // המרת מקף עברי לרווח
        .replaceAll('-', ' ') // המרת מקף רגיל לרווח
        .replaceAll(RegExp(r'\s+'), ' ') // נרמול רווחים
        .trim();
  }

  // נרמול הטקסט והמונח
  final normalizedText = simpleNormalize(text.replaceAll(RegExp(r'<[^>]*>'), ''));
  final normalizedSearchTerm = simpleNormalize(searchTerm);

  // חיפוש ישיר של המונח המלא
  if (normalizedText.contains(normalizedSearchTerm)) {
    // ננסה למצוא את המיקום בטקסט המקורי
    final words = normalizedSearchTerm.split(' ');
    final firstWord = words.first;
    final lastWord = words.last;
    
    // חיפוש המילה הראשונה והאחרונה בטקסט המקורי
    final textLower = text.toLowerCase();
    final firstWordLower = firstWord.toLowerCase();
    final lastWordLower = lastWord.toLowerCase();
    
    final firstIndex = textLower.indexOf(firstWordLower);
    if (firstIndex != -1) {
      // מציאת המילה האחרונה החל מהמילה הראשונה
      final searchStart = firstIndex;
      final lastIndex = textLower.indexOf(lastWordLower, searchStart);
      
      if (lastIndex != -1) {
        final endIndex = lastIndex + lastWord.length;
        final before = text.substring(0, firstIndex);
        final highlighted = text.substring(firstIndex, endIndex);
        final after = text.substring(endIndex);
        
        final result = '$before<mark>$highlighted</mark>$after';
        return result;
      }
    }
  }
  
  // אם לא הצלחנו, ננסה unlimitedHighlight
  return unlimitedHighlight(text, searchTerm);
}
