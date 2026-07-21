import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_anchor_service.dart';

void main() {
  const service = PluginHighlightAnchorService();

  test('keeps an exact offset active when source hash is unchanged', () {
    const source = 'לפני מטרה אחרי';
    final result = service.resolve(
      anchor: _anchor(source, 'מטרה'),
      sourceText: source,
    );

    expect(result.status, 'active');
    expect(result.strategy, 'source-hash-offset');
    expect(result.range?.exactText, 'מטרה');
  });

  test('reanchors shifted exact text using its context', () {
    const oldSource = 'פתיחה לפני מטרה אחרי סוף';
    const newSource = 'נוסף בתחילה פתיחה לפני מטרה אחרי סוף';
    final result = service.resolve(
      anchor: _anchor(oldSource, 'מטרה'),
      sourceText: newSource,
    );

    expect(result.status, 'active');
    expect(result.strategy, 'unique-exact-text');
    expect(
      result.range?.start.grapheme,
      newSource.characters.toList().indexOf('מ'),
    );
    expect(result.range?.sourceTextHash, isNot(_hash(oldSource)));
  });

  test('uses context to choose between repeated exact text', () {
    const oldSource = 'א לפני מטרה אחרי ב ועוד מטרה אחרת';
    const newSource = 'מטרה אחרת וגם א לפני מטרה אחרי ב';
    final result = service.resolve(
      anchor: _anchor(oldSource, 'מטרה'),
      sourceText: newSource,
    );

    expect(result.status, 'active');
    expect(result.strategy, 'context-or-occurrence');
    final start = result.range!.start.grapheme;
    expect(newSource.characters.skip(start).take(4).join(), 'מטרה');
    expect(start, greaterThan(0));
  });

  test(
    'marks repeated text stale when context and occurrence cannot decide',
    () {
      final anchor = _anchor('לפני מטרה אחרי', 'מטרה', occurrenceIndex: 9);
      final result = service.resolve(
        anchor: anchor,
        sourceText: 'מטרה וגם מטרה',
      );

      expect(result.status, 'stale');
      expect(result.range, isNull);
      expect(result.strategy, 'ambiguous-exact-text');
    },
  );

  test('finds one normalized match when nikud changed', () {
    const oldSource = 'אמר שָׁלוֹם לך';
    const newSource = 'נוסף אמר שלום לך';
    final result = service.resolve(
      anchor: _anchor(
        oldSource,
        'שָׁלוֹם',
        normalizationProfile: 'search',
      ),
      sourceText: newSource,
    );

    expect(result.status, 'active');
    expect(result.strategy, 'unique-normalized-text');
    expect(result.range?.exactText, 'שלום');
  });

  test('marks missing text as failed_to_anchor', () {
    final result = service.resolve(
      anchor: _anchor('לפני מטרה אחרי', 'מטרה'),
      sourceText: 'טקסט אחר לחלוטין',
    );

    expect(result.status, 'failed_to_anchor');
    expect(result.range, isNull);
    expect(result.confidence, 0);
  });
}

PluginTextRangeAnchor _anchor(
  String source,
  String exact, {
  int occurrenceIndex = 0,
  String normalizationProfile = 'strict',
}) {
  final sourceGraphemes = source.characters.toList(growable: false);
  final exactGraphemes = exact.characters.toList(growable: false);
  final start = _indexOf(sourceGraphemes, exactGraphemes);
  final end = start + exactGraphemes.length;
  final beforeStart = (start - 8).clamp(0, start).toInt();
  final afterEnd = (end + 8).clamp(end, sourceGraphemes.length).toInt();
  return PluginTextRangeAnchor(
    layer: 'source',
    sourceTextHash: _hash(source),
    start: _offset(sourceGraphemes, start),
    end: _offset(sourceGraphemes, end),
    exactText: exact,
    beforeText: PluginAnchorContext(
      raw: sourceGraphemes.sublist(beforeStart, start).join(),
      normalized: sourceGraphemes.sublist(beforeStart, start).join(),
      maxGraphemes: 8,
      actualGraphemes: start - beforeStart,
      truncatedAtBoundary: beforeStart == 0,
    ),
    afterText: PluginAnchorContext(
      raw: sourceGraphemes.sublist(end, afterEnd).join(),
      normalized: sourceGraphemes.sublist(end, afterEnd).join(),
      maxGraphemes: 8,
      actualGraphemes: afterEnd - end,
      truncatedAtBoundary: afterEnd == sourceGraphemes.length,
    ),
    occurrenceIndexInSection: occurrenceIndex,
    occurrenceCountInSection: 1,
    normalizationProfile: normalizationProfile,
  );
}

PluginTextOffset _offset(List<String> graphemes, int boundary) {
  final prefix = graphemes.take(boundary).join();
  return PluginTextOffset(
    grapheme: boundary,
    codePoint: prefix.runes.length,
    utf16: prefix.length,
  );
}

int _indexOf(List<String> source, List<String> exact) {
  for (var start = 0; start <= source.length - exact.length; start++) {
    if (source.skip(start).take(exact.length).join() == exact.join()) {
      return start;
    }
  }
  return -1;
}

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
