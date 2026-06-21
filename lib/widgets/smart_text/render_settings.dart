import 'package:flutter/material.dart';
import 'package:otzaria/search/models/search_configuration.dart';

bool _searchOptionsEquals(
  Map<String, Map<String, bool>> first,
  Map<String, Map<String, bool>> second,
) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;

  for (final key in first.keys) {
    final firstValue = first[key];
    final secondValue = second[key];
    if (firstValue == null || secondValue == null) return false;
    if (firstValue.length != secondValue.length) return false;

    for (final optionKey in firstValue.keys) {
      if (firstValue[optionKey] != secondValue[optionKey]) return false;
    }
  }

  return true;
}

bool _alternativeWordsEquals(
  Map<int, List<String>> first,
  Map<int, List<String>> second,
) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;

  for (final key in first.keys) {
    final firstValue = first[key];
    final secondValue = second[key];
    if (firstValue == null || secondValue == null) return false;
    if (firstValue.length != secondValue.length) return false;

    for (var i = 0; i < firstValue.length; i++) {
      if (firstValue[i] != secondValue[i]) return false;
    }
  }

  return true;
}

bool _stringMapEquals(
  Map<String, String> first,
  Map<String, String> second,
) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;

  for (final key in first.keys) {
    if (first[key] != second[key]) return false;
  }

  return true;
}

int _searchOptionsHash(Map<String, Map<String, bool>> options) {
  final keys = options.keys.toList()..sort();
  return Object.hashAll(
    keys.map((key) {
      final inner = options[key]!;
      final innerKeys = inner.keys.toList()..sort();
      return Object.hash(
        key,
        Object.hashAll(
          innerKeys.map((innerKey) => Object.hash(innerKey, inner[innerKey])),
        ),
      );
    }),
  );
}

int _alternativeWordsHash(Map<int, List<String>> words) {
  final keys = words.keys.toList()..sort();
  return Object.hashAll(
    keys.map((key) => Object.hash(key, Object.hashAll(words[key]!))),
  );
}

int _stringMapHash(Map<String, String> values) {
  final keys = values.keys.toList()..sort();
  return Object.hashAll(keys.map((key) => Object.hash(key, values[key])));
}

/// הגדרות לרינדור טקסט
///
/// מחלקה זו מכילה את כל הפרמטרים הדרושים לעיבוד והצגת טקסט,
/// כולל הגדרות חיפוש, עיצוב, והסרת סימנים מיוחדים.
@immutable
class RenderSettings {
  /// האם להסיר ניקוד מהטקסט
  final bool removeNikud;

  /// האם להסיר סימני פיסוק מהטקסט
  final bool removePunctuation;

  /// האם להסיר טעמים מהטקסט
  final bool removeTeamim;

  /// האם להחליף שמות קדושים
  final bool replaceHolyNames;

  /// טקסט לחיפוש והדגשה
  final String searchText;

  /// אינדקס תוצאת החיפוש הנוכחית (-1 להדגשת הכל)
  final int currentSearchIndex;

  /// אפשרויות חיפוש מתקדמות (כתיב מלא/חסר וכו')
  final Map<String, Map<String, bool>> searchOptions;

  /// מילים חילופיות לחיפוש
  final Map<int, List<String>> alternativeWords;

  /// ערכי מרווח לחיפוש
  final Map<String, String> spacingValues;

  /// האם זה חיפוש fuzzy
  final bool isFuzzySearch;

  /// מצב החיפוש
  final SearchMode searchMode;

  /// מרחק חיפוש בין מילים כאשר לא הוגדר spacing מפורש
  final int searchDistance;

  /// גודל הטקסט
  final double fontSize;

  /// משפחת הגופן
  final String? fontFamily;

  /// משקל הגופן (null = רגיל / ברירת מחדל w400)
  final FontWeight? fontWeight;

  /// גובה השורה
  final double lineHeight;

  /// האם להפעיל קישורים inline
  final bool enableInlineLinks;

  /// האם לעצב סוגריים
  final bool formatParentheses;

  /// האם ליישר טקסט ב-justify
  final bool justifyText;

  /// האם להשתמש ברקע צהוב להדגשה (במקום צבע אדום)
  final bool highlightYellowBackground;

  const RenderSettings({
    this.removeNikud = false,
    this.removePunctuation = false,
    this.removeTeamim = true,
    this.replaceHolyNames = false,
    this.searchText = '',
    this.currentSearchIndex = -1,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.isFuzzySearch = false,
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.fontSize = 18.0,
    this.fontFamily,
    this.fontWeight,
    this.lineHeight = 1.5,
    this.enableInlineLinks = false,
    this.formatParentheses = true,
    this.justifyText = true,
    this.highlightYellowBackground = false,
  });

  /// יוצר עותק עם שינויים
  RenderSettings copyWith({
    bool? removeNikud,
    bool? removePunctuation,
    bool? removeTeamim,
    bool? replaceHolyNames,
    String? searchText,
    int? currentSearchIndex,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    bool? isFuzzySearch,
    SearchMode? searchMode,
    int? searchDistance,
    double? fontSize,
    String? fontFamily,
    FontWeight? fontWeight,
    double? lineHeight,
    bool? enableInlineLinks,
    bool? formatParentheses,
    bool? justifyText,
    bool? highlightYellowBackground,
  }) {
    return RenderSettings(
      removeNikud: removeNikud ?? this.removeNikud,
      removePunctuation: removePunctuation ?? this.removePunctuation,
      removeTeamim: removeTeamim ?? this.removeTeamim,
      replaceHolyNames: replaceHolyNames ?? this.replaceHolyNames,
      searchText: searchText ?? this.searchText,
      currentSearchIndex: currentSearchIndex ?? this.currentSearchIndex,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      isFuzzySearch: isFuzzySearch ?? this.isFuzzySearch,
      searchMode: searchMode ?? this.searchMode,
      searchDistance: searchDistance ?? this.searchDistance,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      enableInlineLinks: enableInlineLinks ?? this.enableInlineLinks,
      formatParentheses: formatParentheses ?? this.formatParentheses,
      justifyText: justifyText ?? this.justifyText,
      highlightYellowBackground:
          highlightYellowBackground ?? this.highlightYellowBackground,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RenderSettings) return false;
    return removeNikud == other.removeNikud &&
        removePunctuation == other.removePunctuation &&
        removeTeamim == other.removeTeamim &&
        replaceHolyNames == other.replaceHolyNames &&
        searchText == other.searchText &&
        currentSearchIndex == other.currentSearchIndex &&
        _searchOptionsEquals(searchOptions, other.searchOptions) &&
        _alternativeWordsEquals(alternativeWords, other.alternativeWords) &&
        _stringMapEquals(spacingValues, other.spacingValues) &&
        isFuzzySearch == other.isFuzzySearch &&
        searchMode == other.searchMode &&
        searchDistance == other.searchDistance &&
        fontSize == other.fontSize &&
        fontFamily == other.fontFamily &&
        fontWeight == other.fontWeight &&
        lineHeight == other.lineHeight &&
        enableInlineLinks == other.enableInlineLinks &&
        formatParentheses == other.formatParentheses &&
        justifyText == other.justifyText &&
        highlightYellowBackground == other.highlightYellowBackground;
  }

  @override
  int get hashCode {
    return Object.hash(
      removeNikud,
      removePunctuation,
      removeTeamim,
      replaceHolyNames,
      searchText,
      currentSearchIndex,
      _searchOptionsHash(searchOptions),
      _alternativeWordsHash(alternativeWords),
      _stringMapHash(spacingValues),
      isFuzzySearch,
      searchMode,
      searchDistance,
      fontSize,
      fontFamily,
      fontWeight,
      lineHeight,
      enableInlineLinks,
      formatParentheses,
      justifyText,
      highlightYellowBackground,
    );
  }
}
