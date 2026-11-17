import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/services/plugin_text_occurrence_service.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';

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

  test('dense normalized pages preserve individual anchors and pagination', () {
    final text = List.filled(205, 'אָב ').join();
    final first = service.find(
      bookId: 'book',
      sectionIndex: 2,
      layer: 'source',
      text: text,
      textHash: 'hash',
      query: 'אב',
      normalize: options(PluginNormalizationProfile.search),
      limit: 200,
    );
    final second = service.find(
      bookId: 'book',
      sectionIndex: 2,
      layer: 'source',
      text: text,
      textHash: 'hash',
      query: 'אב',
      normalize: options(PluginNormalizationProfile.search),
      limit: 200,
      cursor: first.nextCursor,
    );

    expect(first.totalCount, 205);
    expect(first.results, hasLength(200));
    expect(first.hasMore, isTrue);
    expect(second.results, hasLength(5));
    expect(second.hasMore, isFalse);
    expect(second.nextCursor, isNull);
    final all = [...first.results, ...second.results];
    expect(all.map((item) => item.occurrenceId).toSet(), hasLength(205));
    for (var i = 0; i < all.length; i++) {
      final range = all[i].range;
      expect(range.start.grapheme, i * 3);
      expect(range.end.grapheme, i * 3 + 2);
      expect(range.exactText, 'אָב');
      expect(range.occurrenceIndexInSection, i);
      expect(range.occurrenceCountInSection, 205);
      final individual = const ReaderSelectionService().buildRangeAnchor(
        text: text,
        startGrapheme: i * 3,
        endGrapheme: i * 3 + 2,
        layer: 'source',
        sourceTextHash: 'hash',
        normalizationProfile: 'search',
      );
      expect(range.toJson(), individual!.toJson());
    }
  });

  test('normalized overlapping matches keep their source boundaries', () {
    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'rendered',
      text: 'אָאָאָ',
      textHash: 'rendered-hash',
      query: 'אא',
      normalize: options(PluginNormalizationProfile.search),
    );

    expect(result.totalCount, 2);
    expect(result.results.map((item) => item.range.start.grapheme), [0, 1]);
    expect(result.results.map((item) => item.range.end.grapheme), [2, 3]);
    expect(result.results.map((item) => item.text), ['אָאָ', 'אָאָ']);
    expect(result.results.first.range.renderedTextHash, 'rendered-hash');
    expect(result.results.first.range.sourceTextHash, isNull);
  });

  test('long repeated queries keep the correct anchor occurrence indices', () {
    final prefix = List.filled(512, 'א').join();
    final query = '$prefixב';
    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: '$prefix$query $prefix$query',
      textHash: 'hash',
      query: query,
      normalize: options(PluginNormalizationProfile.strict),
    );

    expect(result.totalCount, 2);
    expect(result.results.map((item) => item.text), [query, query]);
    expect(result.results.map((item) => item.range.start.grapheme), [
      512,
      1538,
    ]);
    expect(result.results.map((item) => item.range.end.grapheme), [1025, 2051]);
    expect(result.results.map((item) => item.range.occurrenceIndexInSection), [
      0,
      1,
    ]);
    expect(result.results.map((item) => item.range.occurrenceCountInSection), [
      2,
      2,
    ]);
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

  test('preserves overlapping occurrences in repeated text', () {
    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: 'אאאא',
      textHash: 'hash',
      query: 'אא',
      normalize: options(PluginNormalizationProfile.strict),
    );

    expect(result.totalCount, 3);
    expect(result.results.map((item) => item.range.start.grapheme), [0, 1, 2]);
  });

  test('handles repeated-prefix searches with no match', () {
    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: '${List.filled(5000, 'א').join()}ב',
      textHash: 'hash',
      query: '${List.filled(300, 'א').join()}ג',
      normalize: options(PluginNormalizationProfile.strict),
    );

    expect(result.totalCount, 0);
    expect(result.results, isEmpty);
  });

  test('checks grapheme rather than UTF-16 length for oversized text', () {
    final text = List.filled(25001, 'א\u05B0').join();
    expect(
      text.length,
      greaterThan(PluginTextOccurrenceService.maxSectionGraphemes),
    );

    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: text,
      textHash: 'hash',
      query: 'ת',
      normalize: options(PluginNormalizationProfile.strict),
    );

    expect(result.totalCount, 0);
  });

  test('accepts exactly the grapheme limit', () {
    final text = List.filled(
      PluginTextOccurrenceService.maxSectionGraphemes,
      'א',
    ).join();
    final result = service.find(
      bookId: 'book',
      sectionIndex: 0,
      layer: 'source',
      text: text,
      textHash: 'hash',
      query: 'ת',
      normalize: options(PluginNormalizationProfile.strict),
    );
    expect(result.totalCount, 0);
  });
}
