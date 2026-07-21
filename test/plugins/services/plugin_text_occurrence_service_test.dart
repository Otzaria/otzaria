import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/services/plugin_text_occurrence_service.dart';

void main() {
  const service = PluginTextOccurrenceService();
  const source = 'אני אומר שאני יודע שאני צריך לבדוק.';
  final sourceHash = sha256.convert(utf8.encode(source)).toString();

  PluginNormalizeOptions options(PluginNormalizationProfile profile) =>
      PluginNormalizeOptions.forProfile(profile);

  test('finds repeated occurrences with distinct source anchors', () {
    final result = service.find(
      bookId: 'book',
      sectionIndex: 3,
      layer: 'source',
      text: source,
      textHash: sourceHash,
      query: 'שאני',
      normalize: options(PluginNormalizationProfile.strict),
      currentRef: 'ספר ג',
    );

    expect(result.totalCount, 2);
    expect(result.results.map((item) => item.text), ['שאני', 'שאני']);
    expect(result.results.map((item) => item.range.start.grapheme), [9, 19]);
    expect(
      result.results.map((item) => item.occurrenceId).toSet(),
      hasLength(2),
    );
    expect(result.results.first.range.sourceTextHash, sourceHash);
    expect(result.results.first.currentRef, 'ספר ג');
  });

  test('search profile maps an unpointed query back to pointed source', () {
    const pointed = 'בְּרֵאשִׁ֖ית בָּרָא';
    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: pointed,
      textHash: 'source-hash',
      query: 'בראשית',
      normalize: options(PluginNormalizationProfile.search),
    );

    expect(result.results.single.text, 'בְּרֵאשִׁ֖ית');
    expect(result.results.single.normalizedText, 'בראשית');
    expect(result.results.single.range.normalizationProfile, 'search');
  });

  test('paginates with a query-bound opaque cursor', () {
    final first = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: 'אב אב אב',
      textHash: 'hash',
      query: 'אב',
      normalize: options(PluginNormalizationProfile.strict),
      limit: 2,
    );
    final second = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: 'אב אב אב',
      textHash: 'hash',
      query: 'אב',
      normalize: options(PluginNormalizationProfile.strict),
      limit: 2,
      cursor: first.nextCursor,
    );

    expect(first.results, hasLength(2));
    expect(first.hasMore, isTrue);
    expect(first.totalCount, 3);
    expect(second.results.single.range.start.grapheme, 6);
    expect(second.hasMore, isFalse);
    expect(second.nextCursor, isNull);
  });

  test('rejects a cursor reused for another query', () {
    final first = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: 'אב אב אב',
      textHash: 'hash',
      query: 'אב',
      normalize: options(PluginNormalizationProfile.strict),
      limit: 1,
    );

    expect(
      () => service.find(
        bookId: 'book',
        sectionIndex: 0,
        layer: 'source',
        text: 'אב אב אב',
        textHash: 'hash',
        query: 'א',
        normalize: options(PluginNormalizationProfile.strict),
        cursor: first.nextCursor,
      ),
      throwsA(
        isA<PluginTextOccurrenceException>().having(
          (error) => error.code,
          'code',
          'error.invalid_params',
        ),
      ),
    );
  });

  test('validates empty queries, layers, limits, and section size', () {
    void expectCode(void Function() callback, String code) {
      expect(
        callback,
        throwsA(
          isA<PluginTextOccurrenceException>().having(
            (error) => error.code,
            'code',
            code,
          ),
        ),
      );
    }

    expectCode(
      () => service.find(
        bookId: 'book',
        sectionIndex: 0,
        layer: 'source',
        text: source,
        textHash: sourceHash,
        query: 'ְ֖',
        normalize: options(PluginNormalizationProfile.search),
      ),
      'error.selection_empty',
    );
    expectCode(
      () => service.find(
        bookId: 'book',
        sectionIndex: 0,
        layer: 'dom',
        text: source,
        textHash: sourceHash,
        query: 'אני',
        normalize: options(PluginNormalizationProfile.strict),
      ),
      'error.unsupported_layer',
    );
    expectCode(
      () => service.find(
        bookId: 'book',
        sectionIndex: 0,
        layer: 'source',
        text: source,
        textHash: sourceHash,
        query: 'אני',
        normalize: options(PluginNormalizationProfile.strict),
        limit: 201,
      ),
      'error.invalid_params',
    );
    expectCode(
      () => service.find(
        bookId: 'book',
        sectionIndex: 0,
        layer: 'source',
        text: List.filled(50001, 'א').join(),
        textHash: sourceHash,
        query: 'א',
        normalize: options(PluginNormalizationProfile.strict),
      ),
      'error.section_too_large',
    );
  });
}
