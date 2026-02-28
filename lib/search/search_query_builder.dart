import 'dart:math' as math;
import 'package:otzaria/search/utils/regex_patterns.dart';

/// מחלקת שירות לריכוז לוגיקת בניית שאילתות החיפוש.
///
/// מחלקה זו מאחדת את הלוגיקה המשותפת לבניית שאילתות חיפוש מתקדמות,
/// הכוללת מילים חילופיות ואפשרויות חיפוש שונות.
/// משמשת הן עבור חיפוש והן עבור ספירת תוצאות.
class SearchQueryBuilder {
  SearchQueryBuilder._();

  /// ניקוי שאילתה מתווים מיוחדים שיכולים להפריע לחיפוש
  /// מסירים: ! ? " : * ( ) [ ] { } ^ $ | \ + . ~ `
  static String sanitizeQuery(String query) {
    return query
        .replaceAll(RegExp(r'[!?":*\(\)\[\]\{\}\^\$\|\\+.~`]'), '')
        .trim();
  }

  /// מחשב את המרווח המקסימלי מהמרווחים המותאמים אישית
  static int getMaxCustomSpacing(
      Map<String, String> customSpacing, int wordCount) {
    int maxSpacing = 0;

    for (int i = 0; i < wordCount - 1; i++) {
      final spacingKey = '$i-${i + 1}';
      final customSpacingValue = customSpacing[spacingKey];

      if (customSpacingValue != null && customSpacingValue.isNotEmpty) {
        final spacingNum = int.tryParse(customSpacingValue) ?? 0;
        maxSpacing = maxSpacing > spacingNum ? maxSpacing : spacingNum;
      }
    }

    return maxSpacing;
  }

  /// בונה query מתקדם עם מילים חילופיות ואפשרויות חיפוש
  static List<String> buildAdvancedQuery(
      List<String> words,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions) {
    List<String> regexTerms = [];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordKey = '${word}_$i';

      // קבלת אפשרויות החיפוש למילה הזו
      final wordOptions = searchOptions?[wordKey] ?? {};
      final hasPrefix = wordOptions['קידומות'] == true;
      final hasSuffix = wordOptions['סיומות'] == true;
      final hasGrammaticalPrefixes = wordOptions['קידומות דקדוקיות'] == true;
      final hasGrammaticalSuffixes = wordOptions['סיומות דקדוקיות'] == true;
      final hasFullPartialSpelling = wordOptions['כתיב מלא/חסר'] == true;
      final hasPartialWord = wordOptions['חלק ממילה'] == true;

      // קבלת מילים חילופיות
      final alternatives = alternativeWords?[i];

      // בניית רשימת כל האפשרויות (מילה מקורית + חלופות)
      final allOptions = [word];
      if (alternatives != null && alternatives.isNotEmpty) {
        allOptions.addAll(alternatives);
      }

      // סינון אפשרויות ריקות
      final validOptions =
          allOptions.where((w) => w.trim().isNotEmpty).toList();

      if (validOptions.isNotEmpty) {
        // בניית רשימת כל האפשרויות לכל מילה
        final allVariations = <String>{};

        for (final option in validOptions) {
          // השתמש בפונקציה המשולבת החדשה
          final pattern = SearchRegexPatterns.createSearchPattern(
            option,
            hasPrefix: hasPrefix,
            hasSuffix: hasSuffix,
            hasGrammaticalPrefixes: hasGrammaticalPrefixes,
            hasGrammaticalSuffixes: hasGrammaticalSuffixes,
            hasPartialWord: hasPartialWord,
            hasFullPartialSpelling: hasFullPartialSpelling,
          );
          allVariations.add(pattern);
        }

        // הגבלה על מספר הוריאציות הכולל למילה אחת
        final limitedVariations = allVariations.length > 20
            ? allVariations.take(20).toList()
            : allVariations.toList();

        // במקום רגקס מורכב, נוסיף כל וריאציה בנפרד
        final finalPattern = limitedVariations.length == 1
            ? limitedVariations.first
            : '(${limitedVariations.join('|')})';

        regexTerms.add(finalPattern);
      } else {
        // fallback למילה המקורית
        regexTerms.add(word);
      }
    }

    return regexTerms;
  }

  /// מכין את הפרמטרים לשאילתת חיפוש
  static Map<String, dynamic> prepareQueryParams(
      String query,
      bool fuzzy,
      int distance,
      Map<String, String>? customSpacing,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions) {
    // ניקוי תווים מיוחדים שלא צריכים להיות בחיפוש
    final cleanedQuery = sanitizeQuery(query);

    final words = cleanedQuery
        .trim()
        .split(SearchRegexPatterns.wordSplitter)
        .where((w) => w.isNotEmpty)
        .toList();

    // בדיקה אם יש מרווחים מותאמים אישית, מילים חילופיות או אפשרויות חיפוש
    final hasCustomSpacing = customSpacing != null && customSpacing.isNotEmpty;
    final hasAlternativeWords =
        alternativeWords != null && alternativeWords.isNotEmpty;
    final hasSearchOptions = searchOptions != null &&
        searchOptions.isNotEmpty &&
        searchOptions.values.any((wordOptions) =>
            wordOptions.values.any((isEnabled) => isEnabled == true));

    // המרת החיפוש לפורמט המנוע החדש
    final List<String> regexTerms;
    final int effectiveSlop;

    if (hasAlternativeWords || hasSearchOptions) {
      // יש מילים חילופיות או אפשרויות חיפוש - נבנה queries מתקדמים
      regexTerms = SearchQueryBuilder.buildAdvancedQuery(
          words, alternativeWords, searchOptions);
      effectiveSlop = hasCustomSpacing
          ? SearchQueryBuilder.getMaxCustomSpacing(customSpacing, words.length)
          : (fuzzy ? distance : 0);
    } else if (fuzzy) {
      // חיפוש מקורב - נשתמש במילים בודדות
      regexTerms = words;
      effectiveSlop = distance;
    } else if (words.length == 1) {
      // מילה אחת - חיפוש פשוט
      regexTerms = [query];
      effectiveSlop = 0;
    } else if (hasCustomSpacing) {
      // מרווחים מותאמים אישית
      regexTerms = words;
      effectiveSlop =
          SearchQueryBuilder.getMaxCustomSpacing(customSpacing, words.length);
    } else {
      // חיפוש מדוייק של כמה מילים
      regexTerms = words;
      effectiveSlop = distance;
    }

    // חישוב maxExpansions בהתבסס על סוג החיפוש
    final int maxExpansions = SearchQueryBuilder.calculateMaxExpansions(
        fuzzy, regexTerms.length,
        searchOptions: searchOptions, words: words);

    return {
      'regexTerms': regexTerms,
      'effectiveSlop': effectiveSlop,
      'maxExpansions': maxExpansions,
    };
  }

  /// מחשב את maxExpansions בהתבסס על סוג החיפוש
  static int calculateMaxExpansions(bool fuzzy, int termCount,
      {Map<String, Map<String, bool>>? searchOptions, List<String>? words}) {
    // בדיקה אם יש חיפוש עם סיומות או קידומות ואיזה מילים
    bool hasSuffixOrPrefix = false;
    int shortestWordLength = 10; // ערך התחלתי גבוה

    if (searchOptions != null && words != null) {
      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        final wordKey = '${word}_$i';
        final wordOptions = searchOptions[wordKey] ?? {};

        if (wordOptions['סיומות'] == true ||
            wordOptions['קידומות'] == true ||
            wordOptions['קידומות דקדוקיות'] == true ||
            wordOptions['סיומות דקדוקיות'] == true ||
            wordOptions['חלק ממילה'] == true) {
          hasSuffixOrPrefix = true;
          shortestWordLength = math.min(shortestWordLength, word.length);
        }
      }
    }

    if (fuzzy) {
      return 50; // חיפוש מקורב
    } else if (hasSuffixOrPrefix) {
      // התאמת המגבלה לפי אורך המילה הקצרה ביותר עם אפשרויות מתקדמות
      if (shortestWordLength <= 1) {
        return 2000; // מילה של תו אחד - הגבלה קיצונית
      } else if (shortestWordLength <= 2) {
        return 3000; // מילה של 2 תווים - הגבלה בינונית
      } else if (shortestWordLength <= 3) {
        return 4000; // מילה של 3 תווים - הגבלה קלה
      } else {
        return 5000; // מילה ארוכה - הגבלה מלאה
      }
    } else if (termCount > 1) {
      return 100; // חיפוש של כמה מילים - צריך expansions גבוה יותר
    } else {
      return 10; // מילה אחת - expansions נמוך
    }
  }
}
