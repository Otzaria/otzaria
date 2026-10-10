import 'package:flutter/material.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

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

  /// סגנון החלפת שמות קדושים (יקוק / ה')
  final HolyNameStyle holyNameStyle;

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

  /// טווח הקרבה ומצב התאמת המילים של החיפוש — ראו [SearchMatchPolicy].
  final SearchMatchPolicy matchPolicy;

  /// האם השורה המרונדרת היא אחת מהשורות שחיפוש המנוע החזיר. במדיניות התאמה
  /// שאינה ברירת המחדל רק שורה כזו מודגשת (מילה-מילה), כי המנוע — ולא
  /// האפליקציה — הוא שמכריע אם השורה תוצאה.
  final bool isSearchResultLine;

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

  /// האם לאפשר הדגשת חלקי מילים (ללא דרישת גבולות אסימון)
  final bool partialWordHighlight;

  /// השורות הסמוכות כשגם הן שורות תוצאה: ביטוי שהמנוע מצא במעבר בין השורות
  /// מודגש גם בחלקו שבשורה הזו.
  final String? previousLineText;
  final String? nextLineText;

  const RenderSettings({
    this.removeNikud = false,
    this.removePunctuation = false,
    this.removeTeamim = false,
    this.replaceHolyNames = false,
    this.holyNameStyle = HolyNameStyle.kufKuf,
    this.searchText = '',
    this.currentSearchIndex = -1,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.isFuzzySearch = false,
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.isSearchResultLine = false,
    this.fontSize = 18.0,
    this.fontFamily,
    this.fontWeight,
    this.lineHeight = 1.5,
    this.enableInlineLinks = false,
    this.formatParentheses = true,
    this.justifyText = true,
    this.highlightYellowBackground = false,
    this.partialWordHighlight = false,
    this.previousLineText,
    this.nextLineText,
  });

  /// הגדרות רינדור מפרופיל תצוגה פתור — המסלול המועדף לכל צרכן חדש.
  /// שאר הפרמטרים זהים לבנאי הרגיל.
  factory RenderSettings.fromProfile(
    TextDisplayProfile profile, {
    String searchText = '',
    int currentSearchIndex = -1,
    Map<String, Map<String, bool>> searchOptions = const {},
    Map<int, List<String>> alternativeWords = const {},
    Map<String, String> spacingValues = const {},
    bool isFuzzySearch = false,
    SearchMode searchMode = SearchMode.exact,
    int searchDistance = 0,
    SearchMatchPolicy matchPolicy = SearchMatchPolicy.standard,
    bool isSearchResultLine = false,
    double fontSize = 18.0,
    String? fontFamily,
    FontWeight? fontWeight,
    double lineHeight = 1.5,
    bool enableInlineLinks = false,
    bool formatParentheses = true,
    bool justifyText = true,
    bool highlightYellowBackground = false,
    bool partialWordHighlight = false,
    String? previousLineText,
    String? nextLineText,
  }) {
    return RenderSettings(
      removeNikud: profile.removeNikud,
      removePunctuation: profile.removePunctuation,
      removeTeamim: profile.removeTeamim,
      replaceHolyNames: profile.replaceHolyNames,
      holyNameStyle: profile.holyNameStyle,
      searchText: searchText,
      currentSearchIndex: currentSearchIndex,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      isFuzzySearch: isFuzzySearch,
      searchMode: searchMode,
      searchDistance: searchDistance,
      matchPolicy: matchPolicy,
      isSearchResultLine: isSearchResultLine,
      fontSize: fontSize,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      lineHeight: lineHeight,
      enableInlineLinks: enableInlineLinks,
      formatParentheses: formatParentheses,
      justifyText: justifyText,
      highlightYellowBackground: highlightYellowBackground,
      partialWordHighlight: partialWordHighlight,
      previousLineText: previousLineText,
      nextLineText: nextLineText,
    );
  }

  /// Stable signature for reader content snapshots.
  ///
  /// Search query state and result highlighting are intentionally excluded:
  /// navigating search results is transient UI state, not a section-content
  /// or persistent rendering change.
  Object get sectionContentRenderingSignature => (
    removeNikud: removeNikud,
    removePunctuation: removePunctuation,
    removeTeamim: removeTeamim,
    replaceHolyNames: replaceHolyNames,
    holyNameStyle: holyNameStyle,
    fontSize: fontSize,
    fontFamily: fontFamily,
    fontWeight: fontWeight,
    lineHeight: lineHeight,
    enableInlineLinks: enableInlineLinks,
    formatParentheses: formatParentheses,
    justifyText: justifyText,
  );

  /// יוצר עותק עם שינויים
  RenderSettings copyWith({
    bool? removeNikud,
    bool? removePunctuation,
    bool? removeTeamim,
    bool? replaceHolyNames,
    HolyNameStyle? holyNameStyle,
    String? searchText,
    int? currentSearchIndex,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    bool? isFuzzySearch,
    SearchMode? searchMode,
    int? searchDistance,
    SearchMatchPolicy? matchPolicy,
    bool? isSearchResultLine,
    double? fontSize,
    String? fontFamily,
    FontWeight? fontWeight,
    double? lineHeight,
    bool? enableInlineLinks,
    bool? formatParentheses,
    bool? justifyText,
    bool? highlightYellowBackground,
    bool? partialWordHighlight,
    String? previousLineText,
    String? nextLineText,
  }) {
    return RenderSettings(
      removeNikud: removeNikud ?? this.removeNikud,
      removePunctuation: removePunctuation ?? this.removePunctuation,
      removeTeamim: removeTeamim ?? this.removeTeamim,
      replaceHolyNames: replaceHolyNames ?? this.replaceHolyNames,
      holyNameStyle: holyNameStyle ?? this.holyNameStyle,
      searchText: searchText ?? this.searchText,
      currentSearchIndex: currentSearchIndex ?? this.currentSearchIndex,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      isFuzzySearch: isFuzzySearch ?? this.isFuzzySearch,
      searchMode: searchMode ?? this.searchMode,
      searchDistance: searchDistance ?? this.searchDistance,
      matchPolicy: matchPolicy ?? this.matchPolicy,
      isSearchResultLine: isSearchResultLine ?? this.isSearchResultLine,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      enableInlineLinks: enableInlineLinks ?? this.enableInlineLinks,
      formatParentheses: formatParentheses ?? this.formatParentheses,
      justifyText: justifyText ?? this.justifyText,
      highlightYellowBackground:
          highlightYellowBackground ?? this.highlightYellowBackground,
      partialWordHighlight: partialWordHighlight ?? this.partialWordHighlight,
      previousLineText: previousLineText ?? this.previousLineText,
      nextLineText: nextLineText ?? this.nextLineText,
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
        holyNameStyle == other.holyNameStyle &&
        searchText == other.searchText &&
        currentSearchIndex == other.currentSearchIndex &&
        _searchOptionsEquals(searchOptions, other.searchOptions) &&
        _alternativeWordsEquals(alternativeWords, other.alternativeWords) &&
        _stringMapEquals(spacingValues, other.spacingValues) &&
        isFuzzySearch == other.isFuzzySearch &&
        searchMode == other.searchMode &&
        searchDistance == other.searchDistance &&
        matchPolicy == other.matchPolicy &&
        isSearchResultLine == other.isSearchResultLine &&
        fontSize == other.fontSize &&
        fontFamily == other.fontFamily &&
        fontWeight == other.fontWeight &&
        lineHeight == other.lineHeight &&
        enableInlineLinks == other.enableInlineLinks &&
        formatParentheses == other.formatParentheses &&
        justifyText == other.justifyText &&
        highlightYellowBackground == other.highlightYellowBackground &&
        partialWordHighlight == other.partialWordHighlight &&
        previousLineText == other.previousLineText &&
        nextLineText == other.nextLineText;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      removeNikud,
      removePunctuation,
      removeTeamim,
      replaceHolyNames,
      holyNameStyle,
      searchText,
      currentSearchIndex,
      _searchOptionsHash(searchOptions),
      _alternativeWordsHash(alternativeWords),
      _stringMapHash(spacingValues),
      isFuzzySearch,
      searchMode,
      searchDistance,
      matchPolicy,
      isSearchResultLine,
      fontSize,
      fontFamily,
      fontWeight,
      lineHeight,
      enableInlineLinks,
      formatParentheses,
      justifyText,
      highlightYellowBackground,
      partialWordHighlight,
      previousLineText,
      nextLineText,
    ]);
  }
}
