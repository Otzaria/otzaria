import 'dart:convert';

import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// התאמות של [query] בטקסט העמוד, באותו מתאם של הקורא הטקסטואלי: אותו
/// מרווח, אותם ווריאנטים ואותו "בכל סדר". כל התאמה היא רצף אחד.
class ProximityHighlightPattern implements Pattern {
  ProximityHighlightPattern(this.query, this.settings)
    : key = _settingsKey(query, settings);

  final String query;
  final InBookSearchSettings settings;

  /// מפתח יציב: pdfrx משווה תבניות ב-`==`, ותבנית זהה אינה מתחילה סריקה מחדש.
  final String key;

  static String _settingsKey(String query, InBookSearchSettings settings) {
    final policy = settings.matchPolicy;
    return jsonEncode([
      query,
      settings.searchMode.name,
      settings.distance,
      settings.searchOptions,
      {
        for (final entry in settings.alternativeWords.entries)
          '${entry.key}': entry.value,
      },
      settings.spacingValues,
      policy.querySemantics.name,
      policy.proximityScope.name,
      policy.wordMatchMode.name,
      policy.wordMatchCount,
      policy.anyOrder,
    ]);
  }

  /// טווחי ההתאמות ב-[text], כזוגות [start, end].
  List<List<int>> spans(String text) => utils.computeHighlightSpans(
    text,
    query,
    searchOptions: settings.searchOptions,
    alternativeWords: settings.alternativeWords,
    spacingValues: settings.spacingValues,
    isFuzzy: settings.searchMode == SearchMode.fuzzy,
    searchDistance: settings.distance,
    matchPolicy: settings.matchPolicy,
  );

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) => [
    for (final span in spans(string))
      if (span[0] >= start && span[1] > span[0])
        _SpanMatch(this, string, span[0], span[1]),
  ];

  @override
  Match? matchAsPrefix(String string, [int start = 0]) {
    for (final match in allMatches(string, start)) {
      if (match.start == start) return match;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ProximityHighlightPattern && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

class _SpanMatch implements Match {
  _SpanMatch(this.pattern, this.input, this.start, this.end);

  @override
  final Pattern pattern;
  @override
  final String input;
  @override
  final int start;
  @override
  final int end;

  @override
  int get groupCount => 0;

  @override
  String? group(int group) {
    if (group != 0) throw RangeError.range(group, 0, 0);
    return input.substring(start, end);
  }

  @override
  String? operator [](int group) => this.group(group);

  @override
  List<String?> groups(List<int> groupIndices) => [
    for (final index in groupIndices) group(index),
  ];
}
