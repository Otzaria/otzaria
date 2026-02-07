// ignore_for_file: avoid_print

import 'package:otzaria/search/utils/regex_patterns.dart';
import 'package:flutter/foundation.dart';

/// דוגמאות שימוש ברגקסים המרכזיים
///
/// קובץ זה מכיל דוגמאות מעשיות לשימוש ברגקסים
/// שרוכזו בקובץ regex_patterns.dart
///
/// הערה: קובץ זה מיועד לדוגמאות ובדיקות בלבד
/// ולא נועד לשימוש בקוד הייצור

class RegexExamples {
  /// דוגמאות לעיבוד טקסט בסיסי
  static void basicTextProcessing() {
    const text = 'שלום עולם! איך הולך?';

    // פיצול למילים
    final words = text.split(SearchRegexPatterns.wordSplitter);
    debugPrint('מילים: $words'); // ['שלום', 'עולם!', 'איך', 'הולך?']

    // ניקוי טקסט
    final cleanText = SearchRegexPatterns.cleanText(text);
    debugPrint('טקסט נקי: $cleanText'); // 'שלום עולם איך הולך'

    // בדיקת שפה
    debugPrint('עברית: ${SearchRegexPatterns.isHebrew(text)}'); // true
    debugPrint('אנגלית: ${SearchRegexPatterns.isEnglish(text)}'); // false
  }

  /// דוגמאות להסרת HTML וניקוד
  static void htmlAndVowelProcessing() {
    const htmlText = '<p>שָׁלוֹם <b>עוֹלָם</b></p>';

    // הסרת HTML
    final withoutHtml =
        htmlText.replaceAll(SearchRegexPatterns.htmlStripper, '');
    debugPrint('ללא HTML: $withoutHtml'); // 'שָׁלוֹם עוֹלָם'

    // הסרת ניקוד
    final withoutVowels =
        withoutHtml.replaceAll(SearchRegexPatterns.vowelsAndCantillation, '');
    debugPrint('ללא ניקוד: $withoutVowels'); // 'שלום עולם'
  }

  /// דוגמאות למורפולוגיה עברית
  static void hebrewMorphology() {
    const word = 'ובספרים';

    // בדיקת קידומות וסיומות
    debugPrint(
        'יש קידומת: ${SearchRegexPatterns.hasGrammaticalPrefix(word)}'); // true
    debugPrint(
        'יש סיומת: ${SearchRegexPatterns.hasGrammaticalSuffix(word)}'); // true

    // חילוץ שורש
    final root = SearchRegexPatterns.extractRoot(word);
    debugPrint('שורש: $root'); // 'ספר'

    // יצירת דפוסי חיפוש
    final prefixPattern = SearchRegexPatterns.createPrefixPattern('ספר');
    debugPrint('דפוס קידומות: $prefixPattern');

    final suffixPattern = SearchRegexPatterns.createSuffixPattern('ספר');
    debugPrint('דפוס סיומות: $suffixPattern');

    final fullPattern =
        SearchRegexPatterns.createFullMorphologicalPattern('ספר');
    debugPrint('דפוס מלא: $fullPattern');
  }

  /// דוגמאות לחיפוש מתקדם
  static void advancedSearch() {
    const word = 'ראשי';

    // חיפוש עם קידומות רגילות
    final prefixSearch = SearchRegexPatterns.createPrefixSearchPattern(word);
    debugPrint('חיפוש קידומות: $prefixSearch');

    // חיפוש עם סיומות רגילות
    final suffixSearch = SearchRegexPatterns.createSuffixSearchPattern(word);
    debugPrint('חיפוש סיומות: $suffixSearch');

    // חיפוש חלק ממילה (משמש גם לקידומות+סיומות יחד)
    final partialSearch = SearchRegexPatterns.createPartialWordPattern(word);
    debugPrint('חיפוש חלקי (או קידומות+סיומות): $partialSearch');
    debugPrint('דוגמה: "$word" ימצא "בראשית" כי "ראשי" נמצא בתוך המילה');

    // כתיב מלא/חסר
    final spellingVariations =
        SearchRegexPatterns.generateFullPartialSpellingVariations(word);
    debugPrint('וריאציות כתיב: $spellingVariations');
  }

  /// דוגמאות לזיהוי תבניות מיוחדות
  static void specialPatterns() {
    const text = 'רמב"ם פרק א\' דף כ"ג "זה ציטוט" 123';

    // זיהוי קיצורים
    final abbreviations = SearchRegexPatterns.abbreviations.allMatches(text);
    debugPrint(
        'קיצורים: ${abbreviations.map((m) => m.group(0)).toList()}'); // ['רמב"ם']

    // זיהוי מספרים עבריים
    final hebrewNums = SearchRegexPatterns.hebrewNumbers.allMatches(text);
    debugPrint(
        'מספרים עבריים: ${hebrewNums.map((m) => m.group(0)).toList()}'); // ['א\'', 'כ"ג']

    // זיהוי מספרים לועזיים
    final latinNums = SearchRegexPatterns.latinNumbers.allMatches(text);
    debugPrint(
        'מספרים לועזיים: ${latinNums.map((m) => m.group(0)).toList()}'); // ['123']

    // זיהוי ציטוטים
    final quotes = SearchRegexPatterns.quotations.allMatches(text);
    debugPrint(
        'ציטוטים: ${quotes.map((m) => m.group(0)).toList()}'); // ['"זה ציטוט"']
  }

  /// דוגמה מקיפה לעיבוד טקסט חיפוש
  static Map<String, dynamic> processSearchQuery(String query) {
    final result = <String, dynamic>{};

    // פיצול למילים
    final words = query.trim().split(SearchRegexPatterns.wordSplitter);
    result['words'] = words;

    // ניתוח כל מילה
    final wordAnalysis = <Map<String, dynamic>>[];
    for (final word in words) {
      final analysis = <String, dynamic>{
        'original': word,
        'hasPrefix': SearchRegexPatterns.hasGrammaticalPrefix(word),
        'hasSuffix': SearchRegexPatterns.hasGrammaticalSuffix(word),
        'root': SearchRegexPatterns.extractRoot(word),
        'isHebrew': SearchRegexPatterns.isHebrew(word),
        'isEnglish': SearchRegexPatterns.isEnglish(word),
      };

      // הוספת דפוסי חיפוש
      analysis['patterns'] = {
        'prefix': SearchRegexPatterns.createPrefixPattern(word),
        'suffix': SearchRegexPatterns.createSuffixPattern(word),
        'full': SearchRegexPatterns.createFullMorphologicalPattern(word),
        'partial': SearchRegexPatterns.createPartialWordPattern(word),
      };

      wordAnalysis.add(analysis);
    }

    result['analysis'] = wordAnalysis;
    result['cleanQuery'] = SearchRegexPatterns.cleanText(query);

    return result;
  }

  /// דוגמה לפונקציה החכמה שבוחרת את סוג החיפוש
  static void smartSearchPattern() {
    const word = 'ראשי';

    debugPrint('=== דוגמאות לפונקציה החכמה ===');

    // רק קידומות
    final prefixOnly =
        SearchRegexPatterns.createSearchPattern(word, hasPrefix: true);
    debugPrint('רק קידומות: $prefixOnly');

    // רק סיומות
    final suffixOnly =
        SearchRegexPatterns.createSearchPattern(word, hasSuffix: true);
    debugPrint('רק סיומות: $suffixOnly');

    // קידומות + סיומות (יהפוך לחלק ממילה!)
    final prefixAndSuffix = SearchRegexPatterns.createSearchPattern(word,
        hasPrefix: true, hasSuffix: true);
    debugPrint('קידומות + סיומות (חלק ממילה): $prefixAndSuffix');
    debugPrint('זה ימצא "בראשית" כי "ראשי" נמצא בתוך המילה');

    // קידומות דקדוקיות + סיומות דקדוקיות
    final grammatical = SearchRegexPatterns.createSearchPattern(word,
        hasGrammaticalPrefixes: true, hasGrammaticalSuffixes: true);
    debugPrint('קידומות + סיומות דקדוקיות: $grammatical');

    // חיפוש מדויק
    final exact = SearchRegexPatterns.createSearchPattern(word);
    debugPrint('חיפוש מדויק: $exact');
  }

  /// הרצת כל הדוגמאות
  static void runAllExamples() {
    debugPrint('=== עיבוד טקסט בסיסי ===');
    basicTextProcessing();

    debugPrint('\n=== הסרת HTML וניקוד ===');
    htmlAndVowelProcessing();

    debugPrint('\n=== מורפולוגיה עברית ===');
    hebrewMorphology();

    debugPrint('\n=== חיפוש מתקדם ===');
    advancedSearch();

    debugPrint('\n=== תבניות מיוחדות ===');
    specialPatterns();

    debugPrint('\n=== פונקציה חכמה לבחירת סוג חיפוש ===');
    smartSearchPattern();

    debugPrint('\n=== עיבוד שאילתת חיפוש ===');
    final analysis = processSearchQuery('ובספרים הקדושים');
    debugPrint('ניתוח: $analysis');
  }
}
