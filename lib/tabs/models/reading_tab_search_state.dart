import 'package:otzaria/search/models/search_configuration.dart';

/// תצורת חיפוש של טאב קריאה, לשכפול ולשמירה.
class ReadingTabSearchState {
  const ReadingTabSearchState({
    this.searchText = '',
    this.searchOrigin = InBookSearchOrigin.inBook,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
  });

  final String searchText;
  final InBookSearchOrigin searchOrigin;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final SearchMatchPolicy matchPolicy;

  /// מעתיק גם אוספים פנימיים כדי שטאבים לא יחלקו הגדרות ניתנות לשינוי.
  ReadingTabSearchState copy({String? searchText}) => ReadingTabSearchState(
    searchText: searchText ?? this.searchText,
    searchOrigin: searchOrigin,
    searchOptions: {
      for (final entry in searchOptions.entries)
        entry.key: Map<String, bool>.of(entry.value),
    },
    alternativeWords: {
      for (final entry in alternativeWords.entries)
        entry.key: List<String>.of(entry.value),
    },
    spacingValues: Map<String, String>.of(spacingValues),
    searchMode: searchMode,
    searchDistance: searchDistance,
    matchPolicy: matchPolicy,
  );

  /// שדות ה-JSON נוספים למפת הטאב הקיימת, ולכן השמות מקודמת `search`.
  /// שאילתה ריקה אינה נשמרת בכלל, ולכן טאב בלי חיפוש אינו מקבל שדות אלה.
  Map<String, dynamic> toJson() {
    if (searchText.isEmpty) return const {};
    return {
      'searchText': searchText,
      if (searchOrigin != InBookSearchOrigin.inBook)
        'searchOrigin': searchOrigin.name,
      if (searchOptions.isNotEmpty) 'searchOptions': searchOptions,
      if (alternativeWords.isNotEmpty)
        'searchAlternativeWords': {
          for (final entry in alternativeWords.entries)
            entry.key.toString(): entry.value,
        },
      if (spacingValues.isNotEmpty) 'searchSpacingValues': spacingValues,
      'searchMode': searchMode.name,
      'searchDistance': searchDistance,
      if (!matchPolicy.isStandard || matchPolicy.wordMatchCount != 2)
        'searchMatchPolicy': matchPolicy.toJson(),
    };
  }

  /// קריאה סובלנית: כל שדה חסר או פגום חוזר לברירת המחדל, כדי ששמירה ישנה
  /// (או מהגרסה שלפני השימור) תיטען בלי לאבד את הטאב עצמו.
  factory ReadingTabSearchState.fromJson(Map<String, dynamic> json) {
    return ReadingTabSearchState(
      searchText: json['searchText'] is String ? json['searchText'] : '',
      searchOrigin: json['searchOrigin'] == InBookSearchOrigin.globalResult.name
          ? InBookSearchOrigin.globalResult
          : InBookSearchOrigin.inBook,
      searchOptions: _decodeSearchOptions(json['searchOptions']),
      alternativeWords: _decodeAlternativeWords(json['searchAlternativeWords']),
      spacingValues: _decodeSpacingValues(json['searchSpacingValues']),
      searchMode: _decodeSearchMode(json['searchMode']),
      searchDistance: json['searchDistance'] is int
          ? json['searchDistance'] as int
          : 0,
      matchPolicy: SearchMatchPolicy.fromJson(json['searchMatchPolicy']),
    );
  }

  static Map<String, Map<String, bool>> _decodeSearchOptions(Object? raw) {
    if (raw is! Map) return const {};
    final decoded = <String, Map<String, bool>>{};
    for (final entry in raw.entries) {
      final options = entry.value;
      if (options is! Map) continue;
      decoded['${entry.key}'] = {
        for (final option in options.entries)
          if (option.value is bool) '${option.key}': option.value as bool,
      };
    }
    return decoded;
  }

  static Map<int, List<String>> _decodeAlternativeWords(Object? raw) {
    if (raw is! Map) return const {};
    final decoded = <int, List<String>>{};
    for (final entry in raw.entries) {
      final index = int.tryParse('${entry.key}');
      final words = entry.value;
      if (index == null || words is! List) continue;
      decoded[index] = [
        for (final word in words)
          if (word is String) word,
      ];
    }
    return decoded;
  }

  static Map<String, String> _decodeSpacingValues(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is String) '${entry.key}': entry.value as String,
    };
  }

  static SearchMode _decodeSearchMode(Object? raw) {
    if (raw is! String) return SearchMode.exact;
    return SearchMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => SearchMode.exact,
    );
  }
}
