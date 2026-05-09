import 'dart:math' as math;
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/regex_patterns.dart';

class SearchModeScopedParameters {
  final Map<String, String> customSpacing;
  final Map<int, List<String>> alternativeWords;
  final Map<String, Map<String, bool>> searchOptions;

  const SearchModeScopedParameters({
    this.customSpacing = const {},
    this.alternativeWords = const {},
    this.searchOptions = const {},
  });
}

/// מחלקת שירות לריכוז לוגיקת בניית שאילתות החיפוש.
///
/// מחלקה זו מאחדת את הלוגיקה המשותפת לבניית שאילתות חיפוש מתקדמות,
/// הכוללת מילים חילופיות ואפשרויות חיפוש שונות.
/// משמשת הן עבור חיפוש והן עבור ספירת תוצאות.
class SearchQueryBuilder {
  SearchQueryBuilder._();

  static const String typoToleranceOptionKey = 'שגיאות כתיב';

  static String buildWordKey(String word, int index) => '${word}_$index';

  static List<String> splitQueryWords(String query) {
    final cleanedQuery = sanitizeQuery(query);
    return cleanedQuery
        .trim()
        .split(SearchRegexPatterns.wordSplitter)
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static bool usesAdvancedParameters(SearchMode searchMode) {
    return searchMode == SearchMode.advanced;
  }

  static bool hasEnabledSearchOptions(
    Map<String, Map<String, bool>>? searchOptions,
  ) {
    return searchOptions != null &&
        searchOptions.isNotEmpty &&
        searchOptions.values.any(
          (wordOptions) => wordOptions.values.any((isEnabled) => isEnabled),
        );
  }

  static SearchModeScopedParameters normalizeParametersForMode(
    SearchMode searchMode, {
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
  }) {
    if (!usesAdvancedParameters(searchMode)) {
      return const SearchModeScopedParameters();
    }

    final normalizedSpacing = <String, String>{};
    if (customSpacing != null) {
      for (final entry in customSpacing.entries) {
        final trimmedValue = entry.value.trim();
        if (trimmedValue.isNotEmpty) {
          normalizedSpacing[entry.key] = trimmedValue;
        }
      }
    }

    final normalizedAlternatives = <int, List<String>>{};
    if (alternativeWords != null) {
      for (final entry in alternativeWords.entries) {
        final cleanedWords = entry.value
            .map((word) => word.trim())
            .where((word) => word.isNotEmpty)
            .toList(growable: false);
        if (cleanedWords.isNotEmpty) {
          normalizedAlternatives[entry.key] = cleanedWords;
        }
      }
    }

    final normalizedOptions = <String, Map<String, bool>>{};
    if (searchOptions != null) {
      for (final entry in searchOptions.entries) {
        final enabledOptions = <String, bool>{};
        for (final optionEntry in entry.value.entries) {
          if (optionEntry.value) {
            enabledOptions[optionEntry.key] = true;
          }
        }
        if (enabledOptions.isNotEmpty) {
          normalizedOptions[entry.key] = enabledOptions;
        }
      }
    }

    return SearchModeScopedParameters(
      customSpacing: normalizedSpacing,
      alternativeWords: normalizedAlternatives,
      searchOptions: normalizedOptions,
    );
  }

  static bool hasTypoToleranceEnabled(
    Map<String, Map<String, bool>>? searchOptions,
  ) {
    if (!hasEnabledSearchOptions(searchOptions)) {
      return false;
    }

    return searchOptions!.values.any(
      (wordOptions) => wordOptions[typoToleranceOptionKey] == true,
    );
  }

  /// ניקוי שאילתה מתווים מיוחדים שיכולים להפריע לחיפוש
  /// מסירים גם פסיקים וגרשיים/גרש
  /// המקף העברי (־) מומר לרווח רגיל כדי שיתפצל למילים נפרדות בחיפוש
  static String sanitizeQuery(String query) {
    return query
        .replaceAll('־', ' ')
        .replaceAll(RegExp(r"""[,!?'"״׳":*\(\)\[\]\{\}\^\$\|\\+.~`]"""), '')
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

  static Map<String, String> effectiveSpacingValues({
    required int wordCount,
    required Map<String, String> spacingValues,
    required int searchDistance,
  }) {
    if (spacingValues.isNotEmpty || searchDistance <= 0 || wordCount < 2) {
      return spacingValues;
    }

    return {
      for (var index = 0; index < wordCount - 1; index++)
        '$index-${index + 1}': '$searchDistance',
    };
  }

  /// בונה query מתקדם עם מילים חילופיות ואפשרויות חיפוש
  static List<String> buildAdvancedQuery(
      List<String> words,
      Map<int, List<String>>? alternativeWords,
      Map<String, Map<String, bool>>? searchOptions,
      {bool fuzzy = false}) {
    List<String> regexTerms = [];

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordKey = buildWordKey(word, i);

      // קבלת אפשרויות החיפוש למילה הזו
      final wordOptions = searchOptions?[wordKey] ?? {};
      final hasPrefix = wordOptions['קידומות'] == true;
      final hasSuffix = wordOptions['סיומות'] == true;
      final hasGrammaticalPrefixes = wordOptions['קידומות דקדוקיות'] == true;
      final hasGrammaticalSuffixes = wordOptions['סיומות דקדוקיות'] == true;
      final hasTypoTolerance =
          fuzzy || wordOptions[typoToleranceOptionKey] == true;
      final hasFullPartialSpelling =
          !fuzzy && wordOptions['כתיב מלא/חסר'] == true;
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
        final maxVariationsPerWord = fuzzy
            ? 96
            : hasTypoTolerance
                ? 48
                : 20;
        final allVariations = <String>{};

        for (final option in validOptions) {
          final expandedOptions = fuzzy
              ? SearchRegexPatterns.generateFuzzyLiteralVariations(option)
              : hasTypoTolerance
                  ? SearchRegexPatterns.generateTypoToleranceVariations(
                      option,
                    )
                  : [option];

          for (final expandedOption in expandedOptions) {
            final pattern = SearchRegexPatterns.createSearchPattern(
              expandedOption,
              hasPrefix: hasPrefix,
              hasSuffix: hasSuffix,
              hasGrammaticalPrefixes: hasGrammaticalPrefixes,
              hasGrammaticalSuffixes: hasGrammaticalSuffixes,
              hasPartialWord: hasPartialWord,
              hasFullPartialSpelling: hasFullPartialSpelling,
            );
            allVariations.add(pattern);
          }
        }

        final limitedVariations = (allVariations.length > maxVariationsPerWord
                ? allVariations.take(maxVariationsPerWord)
                : allVariations)
            .where((v) => v.trim().isNotEmpty)
            .toList();

        if (limitedVariations.isEmpty) continue;

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
    final words = splitQueryWords(query);

    // בדיקה אם יש מרווחים מותאמים אישית, מילים חילופיות או אפשרויות חיפוש
    final hasCustomSpacing =
        !fuzzy && customSpacing != null && customSpacing.isNotEmpty;
    final hasAlternativeWords =
        alternativeWords != null && alternativeWords.isNotEmpty;
    final hasSearchOptions = hasEnabledSearchOptions(searchOptions);

    // המרת החיפוש לפורמט המנוע החדש
    final List<String> regexTerms;
    final int effectiveSlop;

    if (fuzzy || hasAlternativeWords || hasSearchOptions) {
      // יש מילים חילופיות או אפשרויות חיפוש - נבנה queries מתקדמים
      regexTerms = SearchQueryBuilder.buildAdvancedQuery(
          words, alternativeWords, searchOptions,
          fuzzy: fuzzy);
      effectiveSlop = words.length <= 1
          ? 0
          : hasCustomSpacing
              ? SearchQueryBuilder.getMaxCustomSpacing(
                  customSpacing, words.length)
              : distance;
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
      // מרווח כללי בין מילים לכל מצבי החיפוש שאין בהם override ספציפי
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
        final wordKey = buildWordKey(word, i);
        final wordOptions = searchOptions[wordKey] ?? {};
        final hasTypoTolerance = wordOptions[typoToleranceOptionKey] == true;

        if (wordOptions['סיומות'] == true ||
            wordOptions['קידומות'] == true ||
            wordOptions['קידומות דקדוקיות'] == true ||
            wordOptions['סיומות דקדוקיות'] == true ||
            wordOptions['חלק ממילה'] == true) {
          hasSuffixOrPrefix = true;
          shortestWordLength = math.min(shortestWordLength, word.length);
        } else if (hasTypoTolerance) {
          shortestWordLength = math.min(shortestWordLength, word.length);
        }
      }
    }

    if (fuzzy) {
      return 50; // חיפוש מקורב
    } else if (hasTypoToleranceEnabled(searchOptions)) {
      return termCount > 1 ? 100 : 50;
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
