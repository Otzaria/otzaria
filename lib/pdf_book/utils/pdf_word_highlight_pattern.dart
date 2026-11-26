import 'package:otzaria/pdf_book/utils/proximity_highlight_pattern.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class PdfWordHighlightPattern implements Pattern {
  const PdfWordHighlightPattern(
    this.matcher,
    this.boundaries,
    this.wordMatchMode,
    this.wordMatchCount,
  );

  final HighlightMatcher matcher;
  final List<bool> boundaries;
  final WordMatchMode wordMatchMode;
  final int wordMatchCount;

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) sync* {
    RangeError.checkValueInInterval(start, 0, string.length, 'start');
    for (final match in matcher.findPdfWordMatches(
      data: string,
      requireTokenBoundaries: boundaries,
      wordMatchMode: wordMatchMode,
      wordMatchCount: wordMatchCount,
    )) {
      if (match.start >= start) {
        yield PdfSpanMatch(this, string, match.start, match.end);
      }
    }
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) {
    final match = allMatches(string, start).firstOrNull;
    return match?.start == start ? match : null;
  }
}
