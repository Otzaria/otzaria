import 'dart:convert';

import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

/// התאמות של [query] בטקסט העמוד, באותו מתאם של הקורא הטקסטואלי: אותו
/// מרווח, אותם ווריאנטים ואותו "בכל סדר". כל התאמה היא רצף אחד.
// implements RegExp: PdfPageText.allMatches של pdfrx מקבל רק String או RegExp,
// ו-pdfrx מזהה הדגשה זהה רק לפי RegExp.pattern.
// ignore: deprecated_implement
class ProximityHighlightPattern implements RegExp {
  ProximityHighlightPattern(this.query, this.settings)
    : pattern = 'proximity:${_settingsKey(query, settings)}';

  final String query;
  final InBookSearchSettings settings;

  /// מפתח יציב, כדי ש-pdfrx יזהה הדגשה זהה ולא יתחיל את הסריקה מחדש.
  @override
  final String pattern;

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
  Iterable<RegExpMatch> allMatches(String input, [int start = 0]) => [
    for (final span in spans(input))
      if (span[0] >= start && span[1] > span[0])
        _SpanMatch(this, input, span[0], span[1]),
  ];

  @override
  RegExpMatch? firstMatch(String input) {
    final matches = allMatches(input);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  bool hasMatch(String input) => firstMatch(input) != null;

  @override
  String? stringMatch(String input) => firstMatch(input)?.group(0);

  @override
  Match? matchAsPrefix(String string, [int start = 0]) {
    for (final match in allMatches(string, start)) {
      if (match.start == start) return match;
    }
    return null;
  }

  @override
  bool get isCaseSensitive => false;

  @override
  bool get isMultiLine => false;

  @override
  bool get isUnicode => true;

  @override
  bool get isDotAll => false;
}

// ignore: deprecated_implement
class _SpanMatch implements RegExpMatch {
  _SpanMatch(this.pattern, this.input, this.start, this.end);

  @override
  final RegExp pattern;
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

  @override
  String? namedGroup(String name) => throw ArgumentError.value(name, 'name');

  @override
  Iterable<String> get groupNames => const [];
}
