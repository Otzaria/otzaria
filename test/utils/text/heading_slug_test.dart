import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/heading_slug.dart';

String _reference(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\s-]', unicode: true), '')
    .replaceAll(RegExp(r'\s'), '-');

void main() {
  test('equivalent to the regex implementation for every BMP code unit', () {
    for (var c = 0; c <= 0xFFFF; c++) {
      final input = 'a${String.fromCharCode(c)}b';
      expect(
        headingSlug(input),
        _reference(input),
        reason: 'code unit 0x${c.toRadixString(16)}',
      );
    }
  });

  test('equivalent on mixed strings', () {
    const samples = [
      '',
      '  ',
      'פרק א׳ - הקדמה',
      'בְּרֵאשִׁית בָּרָא',
      'Hello, World! Foo_bar-baz',
      'ערכי JSON ← מיפוי',
      'a b c　d﻿e\t\nf',
      'İstanbul ΣΑΣ',
      'emoji 😀 text 𝔘𝔫𝔦',
      '--a__b--',
    ];
    for (final s in samples) {
      expect(headingSlug(s), _reference(s), reason: s);
    }
  });

  test('regular Hebrew and English input never reaches the regex path', () {
    headingSlugRegexFallbackCount = 0;
    headingSlug('פרק א׳ - בְּרֵאשִׁית Hello, World!');
    headingSlug('Some English Title 123');
    expect(headingSlugRegexFallbackCount, 0);
  });

  test('surrogate pairs fall back to the regex path with same result', () {
    headingSlugRegexFallbackCount = 0;
    const s = 'emoji 😀 x';
    expect(headingSlug(s), _reference(s));
    expect(headingSlugRegexFallbackCount, 1);
  });
}
