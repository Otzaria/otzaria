import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

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

/// טווח של מילת-מנוע אחת ([SearchQueryBuilder.splitQueryWords]) בתוך
/// טקסט השאילתה הגולמי, לצורכי UI (איתור המילה שתחת הסמן, ניווט).
class QueryWordSpan {
  /// מילת המנוע המנורמלת (כפי שמופיעה במפתחות `"{word}_{index}"`).
  final String word;

  /// האינדקס בפיצול המלא של השאילתה.
  final int index;

  /// גבולות UTF-16 מדויקים בטקסט הגולמי, כפי שהטוקנייזר מחזיר.
  final int start;
  final int end;

  const QueryWordSpan(this.word, this.index, this.start, this.end);
}

/// מחלקת שירות לריכוז עיבוד קלט החיפוש בצד האפליקציה.
///
/// המחלקה מטפלת רק בפעולות UI כגון ניקוי טקסט, פיצול מילים לצורך
/// מפתחות הגדרות, ונרמול בחירות המשתמש. בניית שאילתות מנוע מתבצעת
/// בחבילת `search_engine`.
class SearchQueryBuilder {
  SearchQueryBuilder._();

  static const String typoToleranceOptionKey = 'שגיאות כתיב';
  static const List<String> availableWordOptionKeys = [
    'קידומות דקדוקיות',
    'סיומות דקדוקיות',
    'קידומות',
    'סיומות',
    'כתיב מלא/חסר',
    'חלק ממילה',
    typoToleranceOptionKey,
  ];

  /// הסבר קצר לכל אפשרות מילה, לחלונית הרחיפה על התיבה.
  static const Map<String, String> wordOptionDescriptions = {
    'קידומות דקדוקיות':
        'אותיות השימוש (ו, ה, ב, כ, ל, מ, ש, ד וצירופיהן) לפני המילה: תורה ימצא גם והתורה, בתורה.',
    'סיומות דקדוקיות':
        'סיומות רבים וכינוי (ים, ות, יו, ינו, יהם...) אחרי המילה: ספר ימצא גם ספרים, ספריו.',
    'קידומות':
        'כל אותיות שהן לפני המילה, עד 3 (במילה קצרה עד 5). רחב יותר מקידומות דקדוקיות.',
    'סיומות':
        'כל אותיות שהן אחרי המילה, עד 5 (במילה קצרה עד 7). רחב יותר מסיומות דקדוקיות.',
    'כתיב מלא/חסר':
        'הוספה או השמטה של י/ו בתוך המילה: מצות ימצא גם מצוות, ולהפך.',
    'חלק ממילה':
        'המילה שהוקלדה נמצאת בתוך מילה ארוכה יותר, עם עד 2-3 אותיות מכל צד: ספר ימצא גם מספרים.',
    typoToleranceOptionKey:
        'הבדל של אות אחת (החלפה, הוספה או השמטה). יחד עם "חלק ממילה" החיפוש רחב מאוד ואיטי יותר.',
  };

  /// אפשרויות המילה המוצגות בחיפוש הרגיל (מדויק) — ללא "קידומות"/"סיומות"
  /// הכלליות, שנשארות בלעדיות למצב המתקדם.
  static const List<String> exactWordOptionKeys = [
    'קידומות דקדוקיות',
    'סיומות דקדוקיות',
    'כתיב מלא/חסר',
    'חלק ממילה',
    typoToleranceOptionKey,
  ];

  /// אפשרויות המילה הבלעדיות למצב המתקדם — הרחבות מבוססות-מילון/אינדקס
  /// של המנוע שאינן מוצעות בחיפוש הרגיל. המחרוזות חייבות להיות זהות
  /// תו-בתו לקבועי ה-Rust (`OPT_ARAMAIC_PREFIX` / `OPT_ARAMAIC_SUFFIX` /
  /// `OPT_IGNORE_QUOTES` / `OPT_TRANSLATION` / `OPT_ACRONYM`
  /// ב-hebrew_query.rs). בכוונה אינן חלק מ-[availableWordOptionKeys]:
  /// סינון המצב הרגיל ([normalizeParametersForMode]) נשען על רשימות
  /// המפתחות, ואלו חייבות להישאר במתקדם בלבד.
  static const List<String> advancedOnlyWordOptionKeys = [
    'קידומות ארמיות',
    'סיומות ארמיות',
    'התעלם מגרשיים',
    'תרגום ארמי',
    'ראשי תיבות',
  ];

  static const String matchNikudOptionKey = 'ניקוד';
  static const String matchTaamimOptionKey = 'טעמים';

  /// מפתחות "ניקוד"/"טעמים": תיבות סימון כמו שאר האפשרויות (גלובלי או
  /// פר-מילה), אך סימון שלהן מעביר את החיפוש לשדה המנוקד במנוע ומחייב את
  /// הסימנים שהוקלדו במילים המסומנות (המנוע מפרש את המפתחות פר-מילה).
  /// אינן חלק מ-[availableWordOptionKeys] כי הן מוצגות רק במסלולים שמריצים
  /// חיפוש אינדקס — חיפוש בתוך ספר פתוח אינו תומך בהתאמת ניקוד.
  static const List<String> vocalizedWordOptionKeys = [
    matchNikudOptionKey,
    matchTaamimOptionKey,
  ];

  /// מזהים יציבים לתוספים עבור אפשרויות המילה הניתנות להשבתה בדיאלוג.
  ///
  /// הכותרות בעברית נשארות פרט מימוש של הממשק; תוסף אינו מפנה אליהן.
  static const Map<String, String> pluginOptionIdByWordOptionKey = {
    'קידומות דקדוקיות': 'word.grammatical-prefixes',
    'סיומות דקדוקיות': 'word.grammatical-suffixes',
    'קידומות': 'word.prefixes',
    'סיומות': 'word.suffixes',
    'כתיב מלא/חסר': 'word.full-or-defective-spelling',
    'חלק ממילה': 'word.partial',
    typoToleranceOptionKey: 'word.typo-tolerance',
    'קידומות ארמיות': 'word.aramaic-prefixes',
    'סיומות ארמיות': 'word.aramaic-suffixes',
    'התעלם מגרשיים': 'word.ignore-quotes',
    'תרגום ארמי': 'word.aramaic-translation',
    'ראשי תיבות': 'word.acronyms',
    matchNikudOptionKey: 'word.nikud',
    matchTaamimOptionKey: 'word.taamim',
  };

  static bool isPluginControllableOptionId(String id) =>
      pluginOptionIdByWordOptionKey.containsValue(id);

  /// האם אפשרויות פר-מילה מבקשות חיפוש מנוקד (מפתח ניקוד/טעמים דלוק
  /// באחת המילים). קובע אם מותר למחוק ניקוד מהשאילתה לפני החיפוש.
  static bool optionsRequestVocalized(Map<String, Map<String, bool>> options) {
    return options.values.any(
      (map) => vocalizedWordOptionKeys.any((key) => map[key] == true),
    );
  }

  /// כמו [optionsRequestVocalized] עבור מפת האפשרויות הגלובלית.
  static bool globalOptionsRequestVocalized(Map<String, bool> options) =>
      vocalizedWordOptionKeys.any((key) => options[key] == true);

  static String buildWordKey(String word, int index) => '${word}_$index';

  static Map<String, bool> disabledWordOptionsTemplate() => {
    for (final option in availableWordOptionKeys) option: false,
    for (final option in vocalizedWordOptionKeys) option: false,
  };

  /// פיצול שאילתה למילות חיפוש. מאציל למנוע ה-Rust
  /// ([`engine.splitQueryWords`]) שהוא מקור האמת היחיד, כך שהטוקניזציה
  /// בצד האפליקציה זהה תו-בתו לזו של האינדוקס והשאילתה במנוע:
  /// - `"` בין אותיות הוא חלק מהמילה (`רמב"ם`, `ז"ל` — מילה אחת);
  ///   בקצה מילה — מפריד.
  /// - `'` בין אותיות או בסוף מילה נשמר בטוקן (`ג'ורג'`, `תוס'`).
  /// - `''` בין אותיות מאוחד ל-`"` (מוסכמת `רמב''ם` בקבצים ישנים);
  ///   ״/׳ עבריים מנורמלים ל-"/' לפני הפיצול.
  static List<String> splitQueryWords(String query) =>
      engine.splitQueryWords(query: query);

  /// הטוקנייזר ממפה את השאילתה כולה, כולל קרי/כתיב ונרמול משנה-אורך.
  static List<QueryWordSpan> queryWordSpans(String text) {
    final words = engine.queryWordSpans(query: text);
    return [
      for (var i = 0; i < words.length; i++)
        QueryWordSpan(words[i].word, i, words[i].start, words[i].end),
    ];
  }

  /// אימות state פר-מילה משוחזר (סשן/היסטוריה) מול הפיצול הנוכחי:
  /// המפות נבנו על `splitQueryWords` של הגרסה ששמרה אותן, ואם חוקי
  /// הפיצול השתנו מאז (למשל `רמב"ם` שהפך משתי מילים לאחת) המפתחות
  /// נופלים בשקט או זולגים למילה הלא-נכונה. מחזיר true כשכל המפתחות
  /// עקביים עם הפיצול הנוכחי של השאילתה.
  static bool restoredPerWordStateMatches(
    String query, {
    Map<String, Map<String, bool>> searchOptions = const {},
    Map<int, List<String>> alternativeWords = const {},
    Map<String, String> spacingValues = const {},
  }) {
    final words = splitQueryWords(query);
    for (final key in searchOptions.keys) {
      final sep = key.lastIndexOf('_');
      if (sep <= 0) return false;
      final word = key.substring(0, sep);
      final index = int.tryParse(key.substring(sep + 1));
      if (index == null ||
          index < 0 ||
          index >= words.length ||
          words[index] != word) {
        return false;
      }
    }
    for (final index in alternativeWords.keys) {
      if (index < 0 || index >= words.length) return false;
    }
    for (final key in spacingValues.keys) {
      final parts = key.split('-');
      if (parts.length != 2) return false;
      final from = int.tryParse(parts[0]);
      final to = int.tryParse(parts[1]);
      if (from == null || to == null || to != from + 1 || to >= words.length) {
        return false;
      }
    }
    return true;
  }

  /// בונה מפת אפשרויות חיפוש אפקטיבית מתוך הגדרות גלובליות.
  /// יוצרת מפתח לכל מילה בשאילתה עם אותן אפשרויות.
  static Map<String, Map<String, bool>> expandGlobalOptionsToWords(
    String query,
    Map<String, bool> globalOptions,
  ) {
    if (globalOptions.isEmpty ||
        !globalOptions.values.any((enabled) => enabled)) {
      return const {};
    }
    final words = splitQueryWords(query);
    final result = <String, Map<String, bool>>{};
    for (var i = 0; i < words.length; i++) {
      result[buildWordKey(words[i], i)] = Map<String, bool>.from(globalOptions);
    }
    return result;
  }

  /// כמו [normalizeParametersForMode] עבור מפת אפשרויות גלובלית אחת:
  /// משאיר רק אפשרויות פעילות שהמצב תומך בהן (מקורב — ללא אפשרויות כלל).
  static Map<String, bool> normalizeGlobalOptionsForMode(
    SearchMode searchMode,
    Map<String, bool> options,
  ) {
    final normalized = normalizeParametersForMode(
      searchMode,
      searchOptions: {'global_0': options},
    ).searchOptions;
    return normalized['global_0'] ?? const {};
  }

  /// ההופכית של [expandGlobalOptionsToWords]: אפשרויות פר-מילה שכולן זהות
  /// מקורן במפה גלובלית אחת ומוחזרות אליה. null כשהן נבדלות בין מילים
  /// (מצב פר-מילה אמיתי) או כשאין אפשרויות כלל.
  static Map<String, bool>? globalOptionsFromPerWord(
    Map<String, Map<String, bool>> perWordOptions,
  ) {
    if (perWordOptions.isEmpty) return null;
    final first = perWordOptions.values.first;
    for (final options in perWordOptions.values.skip(1)) {
      if (!mapEquals(options, first)) return null;
    }
    return Map<String, bool>.from(first);
  }

  /// בוחר את מפת אפשרויות החיפוש האפקטיבית לפי המצב.
  /// במצב גלובלי - מרחיב את ההגדרות הגלובליות לכל מילה בשאילתה.
  /// במצב פר-מילה - מחזיר את ההגדרות הפר-מיליות כמות שהן.
  static Map<String, Map<String, bool>> effectiveSearchOptions({
    required String query,
    required bool useGlobalOptions,
    required Map<String, bool> globalOptions,
    required Map<String, Map<String, bool>> perWordOptions,
  }) {
    if (useGlobalOptions) {
      return expandGlobalOptionsToWords(query, globalOptions);
    }
    return perWordOptions;
  }

  /// מצמצם את פרמטרי החיפוש למה שהמצב הנבחר תומך בו:
  /// - מתקדם — הכל (אפשרויות, מילים חלופיות, מרווחים ידניים);
  /// - רגיל (מדויק) — אפשרויות המילה בלבד (שגיאות כתיב, קידומות/סיומות,
  ///   כתיב מלא/חסר, חלק ממילה); בקשה עם אפשרויות פעילות רצה בפועל דרך
  ///   המסלול המתקדם של המנוע (ראה gateway);
  /// - מקורב — ללא פרמטרים (המרחק שם הוא מרחק עריכה).
  static SearchModeScopedParameters normalizeParametersForMode(
    SearchMode searchMode, {
    Map<String, String>? customSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
  }) {
    if (searchMode == SearchMode.fuzzy) {
      return const SearchModeScopedParameters();
    }
    if (searchMode == SearchMode.exact) {
      // רק חמש אפשרויות המילה של המצב הרגיל ([exactWordOptionKeys]);
      // "ניקוד"/"טעמים", קידומות/סיומות כלליות והאפשרויות הבלעדיות למתקדם
      // מסוננים — גם כשהם מגיעים ממצב משוחזר/קונפיגורציה קיימת שה-UI
      // כבר לא מציג (ברירת מחדל שמורה עם ניקוד לא תהפוך חיפוש רגיל למנוקד).
      final wordOptionsOnly = <String, Map<String, bool>>{};
      for (final entry in _normalizeSearchOptions(searchOptions).entries) {
        final kept = <String, bool>{
          for (final option in entry.value.entries)
            if (exactWordOptionKeys.contains(option.key))
              option.key: option.value,
        };
        if (kept.isNotEmpty) {
          wordOptionsOnly[entry.key] = kept;
        }
      }
      return SearchModeScopedParameters(searchOptions: wordOptionsOnly);
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

    return SearchModeScopedParameters(
      customSpacing: normalizedSpacing,
      alternativeWords: normalizedAlternatives,
      searchOptions: _normalizeSearchOptions(searchOptions),
    );
  }

  /// משאיר רק אפשרויות מסומנות; מילה בלי אף אפשרות פעילה נשמטת מהמפה.
  static Map<String, Map<String, bool>> _normalizeSearchOptions(
    Map<String, Map<String, bool>>? searchOptions,
  ) {
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
    return normalizedOptions;
  }

  /// ניקוי שאילתה מתווים מיוחדים שיכולים להפריע לחיפוש. מאציל למנוע ה-Rust
  /// ([`engine.sanitizeQuery`]) שהוא מקור האמת היחיד, כך שנרמול השאילתה
  /// ונרמול האינדוקס לא יכולים להיפרד:
  /// גרשיים וגרש עבריים (״ ׳) מומרים לגרשיים וגרש לועזיים (" ');
  /// המקף העברי (־) והמקף הלועזי (-) מומרים לרווח; רווחים מרובים מצומצמים.
  static String sanitizeQuery(String query) =>
      engine.sanitizeQuery(query: query);

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
}
