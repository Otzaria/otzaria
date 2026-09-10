/// בניית העמודים (הטורים) לפי טבלת השיטה. פורט של `buildOfficialPages`
/// ו-`computeBookStartIndices` (navigation.js).
library;

import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';

/// אינדקס האסימון שבו מתחיל כל חומש (`book_break` מפריד ביניהם).
Map<String, int> computeBookStartIndices(
  List<TikkunToken> tokens, {
  List<String> order = const ['shemot', 'vayikra', 'bamidbar', 'devarim'],
  String firstBookId = 'bereshit',
}) {
  final indices = <String, int>{firstBookId: 0};
  var count = 0;
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].type == TikkunTokenType.bookBreak) {
      if (count < order.length) {
        indices[order[count]] = i + 1;
        count++;
      }
    }
  }
  return indices;
}

/// מפה מאינדקס אסימון לשורה שמכילה אותו (חיפוש בינארי על שורות תקינות).
class LineIndexLookup {
  final List<TikkunLine> _lines;
  final List<int> _validLines;

  LineIndexLookup(this._lines)
    : _validLines = [
        for (var i = 0; i < _lines.length; i++)
          if (_lines[i].startTokenIdx >= 0) i,
      ];

  /// אינדקס השורה האחרונה שה-startTokenIdx שלה ‎<= [tokenIdx]; ‎-1 כשאין.
  int find(int tokenIdx) {
    var lo = 0;
    var hi = _validLines.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_lines[_validLines[mid]].startTokenIdx <= tokenIdx) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi >= 0 ? _validLines[hi] : -1;
  }
}

/// מספר העמודים שמילתם האחרונה אינה `lastWord` שבטבלת השיטה — מדד הכיסוי
/// של גבולות העמודים, שרובם נקבעים בהתאמת `firstWord` או באינטרפולציה.
int countUnmatchedOfficialPages(
  List<TikkunPage> pages,
  List<PageDefinition> pageDefs,
) {
  var unmatched = 0;
  for (var pi = 0; pi < pages.length && pi < pageDefs.length; pi++) {
    final expected = pageDefs[pi].lastWord;
    if (expected == null) continue;
    String? actual;
    for (final line in pages[pi].lines) {
      for (final word in line.words) {
        if (word.isGap || word.isBigGap || word.stam.isEmpty) continue;
        actual = word.stam;
      }
    }
    if (actual != expected) unmatched++;
  }
  return unmatched;
}

/// מייצר בדיוק [pageDefs].length עמודים: גבול לפי `firstWord`, ומה שחסר —
/// באינטרפולציה בין הגבולות הידועים.
List<TikkunPage> buildOfficialPages(
  List<TikkunToken> tokens,
  List<TikkunLine> allLines,
  List<PageDefinition> pageDefs,
) {
  if (pageDefs.isEmpty) return [];

  // אינדקס המילים בלבד, ומפה ממילה בסת"ם למיקומיה.
  final wordTokenIdx = <int>[];
  final occurrences = <String, List<int>>{};
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].type != TikkunTokenType.word) continue;
    occurrences
        .putIfAbsent(stripNikud(tokens[i].value!), () => [])
        .add(wordTokenIdx.length);
    wordTokenIdx.add(i);
  }

  final tokenBoundaries = List<int>.filled(pageDefs.length, -1);
  tokenBoundaries[0] = 0;
  if (wordTokenIdx.isEmpty) return [];

  // מילת פתיחה שכיחה מופיעה עשרות פעמים בתוך עמוד אחד; בוחרים את
  // המופע הקרוב לצפייה לפי אורך עמוד ממוצע, לא את הראשון שנמצא.
  final avgWordsPerPage = wordTokenIdx.length / pageDefs.length;
  const searchTolerance = 0.35;
  var anchorWord = 0.0;
  var anchorPage = 0;
  for (var pi = 1; pi < pageDefs.length; pi++) {
    final firstWord = pageDefs[pi].firstWord;
    if (firstWord == null) continue;
    final candidates = occurrences[firstWord];
    if (candidates == null) continue;
    final span = (pi - anchorPage) * avgWordsPerPage;
    final expected = anchorWord + span;
    final tolerance = span * searchTolerance;
    int? best;
    for (final candidate in candidates) {
      final distance = (candidate - expected).abs();
      if (distance > tolerance) continue;
      if (best == null || distance < (best - expected).abs()) best = candidate;
    }
    if (best == null) continue;
    tokenBoundaries[pi] = wordTokenIdx[best];
    anchorWord = best.toDouble();
    anchorPage = pi;
  }

  for (var pi = 1; pi < pageDefs.length; pi++) {
    if (tokenBoundaries[pi] != -1) continue;
    var lo = pi - 1;
    while (lo > 0 && tokenBoundaries[lo] == -1) {
      lo--;
    }
    var hi = pi + 1;
    while (hi < pageDefs.length && tokenBoundaries[hi] == -1) {
      hi++;
    }
    final hiVal = hi < pageDefs.length ? tokenBoundaries[hi] : tokens.length;
    final nullCount = hi - lo - 1;
    for (var k = 1; k <= nullCount; k++) {
      tokenBoundaries[lo + k] =
          (tokenBoundaries[lo] +
                  k * (hiVal - tokenBoundaries[lo]) / (nullCount + 1))
              .round();
    }
  }

  final lookup = LineIndexLookup(allLines);
  final lineStarts = [
    for (final tb in tokenBoundaries)
      if (tb <= 0) 0 else (lookup.find(tb) < 0 ? 0 : lookup.find(tb)),
  ];

  return [
    for (var pi = 0; pi < pageDefs.length; pi++)
      () {
        final startLineIdx = lineStarts[pi];
        final endLineIdx = pi + 1 < pageDefs.length
            ? lineStarts[pi + 1]
            : allLines.length;
        return TikkunPage(
          startLineIdx: startLineIdx,
          endLineIdx: endLineIdx,
          lines: allLines.sublist(
            startLineIdx,
            endLineIdx < startLineIdx ? startLineIdx : endLineIdx,
          ),
        );
      }(),
  ];
}
