import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/title_break_opportunities.dart';

void main() {
  test('short titles are returned unchanged', () {
    expect(
      insertGraphemeBreakOpportunities('abcdefghijkl', 12),
      'abcdefghijkl',
    );
    expect(insertGraphemeBreakOpportunities('שלום', 12), 'שלום');
  });

  test('long words wrap without appending trailing invisible characters', () {
    expect(
      insertGraphemeBreakOpportunities('abcdefghijklmnopqrstuvwx', 12),
      'abcdefghijkl\u200Bmnopqrstuvwx',
    );
    expect(
      insertGraphemeBreakOpportunities('abcdefghijklm', 12),
      'abcdefghijkl\u200Bm',
    );
  });

  test('Hebrew vowel marks are never separated from their base letters', () {
    expect(
      insertGraphemeBreakOpportunities('א\u05B7ב\u05B0ג', 2),
      'א\u05B7ב\u05B0\u200Bג',
    );
    expect(
      insertGraphemeBreakOpportunities('א\u05B7\u05B0\u05B1', 2),
      'א\u05B7\u05B0\u05B1',
    );
  });

  test('supplementary Unicode grapheme clusters are preserved', () {
    const flag = '\u{1F1EE}\u{1F1F1}';
    final twoFlags = [flag, flag].join();
    expect(
      insertGraphemeBreakOpportunities(twoFlags + 'ג', 2),
      twoFlags + '\u200Bג',
    );
  });

  test('the number of graphemes per run must be positive', () {
    expect(() => insertGraphemeBreakOpportunities('abc', 0), throwsRangeError);
  });
}
