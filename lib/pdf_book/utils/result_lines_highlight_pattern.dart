import 'dart:convert';

import 'package:otzaria/pdf_book/utils/proximity_highlight_pattern.dart';

/// המונחים שהמנוע סימן, רק בשורות העמוד שמכילות את כל המונחים של קטע תוצאה
/// אחד: כל שורת PDF היא מסמך באינדקס, וכשההתאמה אינה רצף היא השורה כולה.
class ResultLinesHighlightPattern implements Pattern {
  ResultLinesHighlightPattern._(this._terms, this._termSets, this.key);

  /// [termSources] – מקור הרגקס של כל מונח; [termSets] – לכל קטע תוצאה, אינדקסי
  /// המונחים שסומנו בו. null כשאין מונחים.
  static ResultLinesHighlightPattern? build(
    List<String> termSources,
    Iterable<Set<int>> termSets,
  ) {
    if (termSources.isEmpty || termSources.length > _maxTerms) return null;
    final masks = <int>{
      for (final set in termSets)
        if (set.isNotEmpty) set.fold<int>(0, (mask, i) => mask | (1 << i)),
    };
    // שורה שמכילה קבוצה קטנה יותר כבר עומדת בתנאי, ולכן נשמרות רק המינימליות.
    final minimal = [
      for (final mask in masks)
        if (!masks.any((other) => other != mask && other & mask == other)) mask,
    ]..sort();
    if (minimal.isEmpty) return null;
    final combined = RegExp(
      [
        for (var i = 0; i < termSources.length; i++)
          '(?<$_groupPrefix$i>${termSources[i]})',
      ].join('|'),
      caseSensitive: false,
      unicode: true,
    );
    return ResultLinesHighlightPattern._(
      combined,
      minimal,
      jsonEncode([termSources, minimal]),
    );
  }

  /// התקרה נובעת ממסכת הסיביות של [_termSets], ב-int של 64 סיביות.
  static const int _maxTerms = 50;
  static const String _groupPrefix = 'otzt';

  final RegExp _terms;
  final List<int> _termSets;

  /// מפתח יציב: pdfrx משווה תבניות ב-`==`, ותבנית זהה אינה מתחילה סריקה מחדש.
  final String key;

  bool get requiresWholeLines =>
      _termSets.any((mask) => mask & (mask - 1) != 0);

  int _termOf(RegExpMatch match) {
    for (final name in match.groupNames) {
      if (match.namedGroup(name) != null) {
        return int.parse(name.substring(_groupPrefix.length));
      }
    }
    return -1;
  }

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) {
    final result = <Match>[];
    final line = <RegExpMatch>[];
    var lineMask = 0;
    var lineEnd = -1;
    void flushLine() {
      if (line.isEmpty) return;
      if (_termSets.any((mask) => lineMask & mask == mask)) {
        for (final match in line) {
          result.add(PdfSpanMatch(this, string, match.start, match.end));
        }
      }
      line.clear();
      lineMask = 0;
    }

    for (final match in _terms.allMatches(string, start)) {
      if (match.end <= match.start) continue;
      if (match.start >= lineEnd) {
        flushLine();
        lineEnd = string.indexOf('\n', match.start);
        if (lineEnd < 0) lineEnd = string.length;
      }
      final term = _termOf(match);
      if (term >= 0) lineMask |= 1 << term;
      line.add(match);
    }
    flushLine();
    return result;
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) {
    for (final match in allMatches(string, start)) {
      if (match.start == start) return match;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ResultLinesHighlightPattern && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
