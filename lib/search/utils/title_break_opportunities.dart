// Copyright (c) 2026, the Otzaria contributors.
//
// Insert optional line-break opportunities without splitting grapheme
// clusters or adding invisible characters to the end of a title.

import 'package:characters/characters.dart';

/// Adds a zero-width break between runs of [maxGraphemes] graphemes.
///
/// For short words, the UTF-16 length is an inexpensive upper bound; for
/// longer words, only the first [maxGraphemes] + 1 clusters need to be checked
/// before deciding that any insertion is necessary.
String insertGraphemeBreakOpportunities(String word, int maxGraphemes) {
  if (maxGraphemes <= 0) {
    throw RangeError.value(maxGraphemes, 'maxGraphemes', 'Must be positive');
  }
  if (word.length <= maxGraphemes) return word;

  final probe = word.characters.iterator;
  if (!probe.moveNext(maxGraphemes + 1)) return word;

  final buffer = StringBuffer();
  var runLength = 0;
  for (final grapheme in word.characters) {
    if (runLength == maxGraphemes) {
      buffer.write('\u200B');
      runLength = 0;
    }
    buffer.write(grapheme);
    runLength++;
  }
  return buffer.toString();
}
