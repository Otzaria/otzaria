import 'package:flutter/material.dart';
import 'package:otzaria/search/models/search_configuration.dart';

/// הגדרות לרינדור טקסט
///
/// מחלקה זו מכילה את כל הפרמטרים הדרושים לעיבוד והצגת טקסט,
/// כולל הגדרות חיפוש, עיצוב, והסרת סימנים מיוחדים.
@immutable
class RenderSettings {
  /// האם להסיר ניקוד מהטקסט
  final bool removeNikud;

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

  /// גודל הטקסט
  final double fontSize;

  /// משפחת הגופן
  final String? fontFamily;

  /// גובה השורה
  final double lineHeight;

  /// האם להפעיל קישורים inline
  final bool enableInlineLinks;

  /// האם לעצב סוגריים
  final bool formatParentheses;

  const RenderSettings({
    this.removeNikud = false,
    this.removeTeamim = true,
    this.replaceHolyNames = false,
    this.searchText = '',
    this.currentSearchIndex = -1,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.isFuzzySearch = false,
    this.searchMode = SearchMode.exact,
    this.fontSize = 18.0,
    this.fontFamily,
    this.lineHeight = 1.5,
    this.enableInlineLinks = false,
    this.formatParentheses = true,
  });

  /// יוצר עותק עם שינויים
  RenderSettings copyWith({
    bool? removeNikud,
    bool? removeTeamim,
    bool? replaceHolyNames,
    String? searchText,
    int? currentSearchIndex,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    bool? isFuzzySearch,
    SearchMode? searchMode,
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    bool? enableInlineLinks,
    bool? formatParentheses,
  }) {
    return RenderSettings(
      removeNikud: removeNikud ?? this.removeNikud,
      removeTeamim: removeTeamim ?? this.removeTeamim,
      replaceHolyNames: replaceHolyNames ?? this.replaceHolyNames,
      searchText: searchText ?? this.searchText,
      currentSearchIndex: currentSearchIndex ?? this.currentSearchIndex,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      isFuzzySearch: isFuzzySearch ?? this.isFuzzySearch,
      searchMode: searchMode ?? this.searchMode,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      enableInlineLinks: enableInlineLinks ?? this.enableInlineLinks,
      formatParentheses: formatParentheses ?? this.formatParentheses,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RenderSettings) return false;
    return removeNikud == other.removeNikud &&
        removeTeamim == other.removeTeamim &&
        replaceHolyNames == other.replaceHolyNames &&
        searchText == other.searchText &&
        currentSearchIndex == other.currentSearchIndex &&
        isFuzzySearch == other.isFuzzySearch &&
        searchMode == other.searchMode &&
        fontSize == other.fontSize &&
        fontFamily == other.fontFamily &&
        lineHeight == other.lineHeight &&
        enableInlineLinks == other.enableInlineLinks &&
        formatParentheses == other.formatParentheses;
  }

  @override
  int get hashCode {
    return Object.hash(
      removeNikud,
      removeTeamim,
      replaceHolyNames,
      searchText,
      currentSearchIndex,
      isFuzzySearch,
      searchMode,
      fontSize,
      fontFamily,
      lineHeight,
      enableInlineLinks,
      formatParentheses,
    );
  }
}
