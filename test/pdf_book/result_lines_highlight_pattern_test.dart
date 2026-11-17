import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/result_lines_highlight_pattern.dart';

List<(int, int)> spans(Pattern pattern, String text, [int start = 0]) => [
  for (final match in pattern.allMatches(text, start)) (match.start, match.end),
];

void main() {
  test('only emits matches on lines satisfying a complete term set', () {
    final pattern = ResultLinesHighlightPattern.build(
      ['a', 'b'],
      [
        {0, 1},
      ],
    )!;
    expect(spans(pattern, 'a\na b\nb'), [(2, 3), (4, 5)]);
    expect(spans(pattern, 'a b\nb a'), [(0, 1), (2, 3), (4, 5), (6, 7)]);
  });

  test('start in a line only counts terms at or after start', () {
    final pattern = ResultLinesHighlightPattern.build(
      ['a', 'b'],
      [
        {0, 1},
      ],
    )!;
    expect(spans(pattern, 'a b\na b', 2), [(4, 5), (6, 7)]);
    expect(pattern.matchAsPrefix('a b', 2), isNull);
    expect(pattern.matchAsPrefix('a b')?.start, 0);
    expect(pattern.matchAsPrefix(' a b'), isNull);
  });

  test('overlapping term sources and final lines preserve match spans', () {
    final pattern = ResultLinesHighlightPattern.build(
      ['ab', 'a'],
      [
        {0, 1},
      ],
    )!;
    expect(spans(pattern, 'ab\nab'), [(0, 2), (3, 5)]);
    expect(spans(pattern, 'ab\nab\n'), [(0, 2), (3, 5)]);
    expect(spans(pattern, ''), isEmpty);
  });

  test('invalid start throws immediately when creating matches', () {
    final pattern = ResultLinesHighlightPattern.build(
      ['a'],
      [
        {0},
      ],
    )!;
    expect(() => pattern.allMatches('a', -1), throwsRangeError);
    expect(() => pattern.allMatches('a', 2), throwsRangeError);
    expect(() => pattern.allMatches('', 1), throwsRangeError);
    expect(pattern.allMatches('a', 1), isEmpty);
    expect(pattern.allMatches('', 0), isEmpty);
  });

  test('multiple iterations independently produce the same results', () {
    final pattern = ResultLinesHighlightPattern.build(
      ['a'],
      [
        {0},
      ],
    )!;
    final matches = pattern.allMatches('a\na');
    expect(matches.first.start, 0);
    expect(matches.map((match) => match.start), [0, 2]);
    expect(matches.map((match) => match.start), [0, 2]);
  });
}
