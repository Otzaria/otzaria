import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/services/plugin_section_text_map_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const service = PluginSectionTextMapService();
  final map = const TextSourceMapService().build(
    bookId: 'book',
    sectionIndex: 2,
    rawText: 'בְּרֵאשִׁית ברא עולם',
    settings: const RenderSettings(removeNikud: true),
  );
  final search = PluginNormalizeOptions.forProfile(
    PluginNormalizationProfile.search,
  );

  test('returns only the requested layer and optional source map', () {
    final result = service
        .build(
          map: map,
          layer: 'source',
          includeWords: false,
          includeChars: false,
          includeSourceMap: true,
          normalize: search,
          currentRef: 'פרק ב',
        )
        .toJson();

    expect(result['schemaVersion'], 1);
    expect(result['sourceText'], isNotNull);
    expect(result['sourceTextHash'], map.sourceTextHash);
    expect(result.containsKey('renderedText'), isFalse);
    expect(result['sourceMap']['schemaVersion'], 1);
    expect(result['currentRef'], 'פרק ב');
  });

  test('word tokens include offsets and source/rendered anchors', () {
    final result = service.build(
      map: map,
      layer: 'rendered',
      includeWords: true,
      includeChars: false,
      includeSourceMap: false,
      normalize: search,
    );

    expect(result.words, hasLength(3));
    final first = result.words!.first;
    expect(first.text, 'בראשית');
    expect(first.normalizedText, 'בראשית');
    expect(first.start.grapheme, 0);
    expect(first.end.grapheme, 6);
    expect(first.sourceRange?.exactText, 'בְּרֵאשִׁית');
    expect(first.renderedRange?.exactText, 'בראשית');
  });

  test('characters are grapheme clusters and paginate', () {
    final first = service.build(
      map: map,
      layer: 'source',
      includeWords: false,
      includeChars: true,
      includeSourceMap: false,
      normalize: search,
      limit: 2,
    );
    final second = service.build(
      map: map,
      layer: 'source',
      includeWords: false,
      includeChars: true,
      includeSourceMap: false,
      normalize: search,
      limit: 2,
      cursor: first.nextCursor,
    );

    expect(first.chars, hasLength(2));
    expect(first.chars!.first.text, 'בְּ');
    expect(first.chars!.first.start.utf16, 0);
    expect(first.chars!.first.end.utf16, greaterThan(1));
    expect(first.hasMore, isTrue);
    expect(second.chars!.first.charIndex, 2);
  });

  test('rejects unsupported layers and stale cursors', () {
    expect(
      () => service.build(
        map: map,
        layer: 'dom',
        includeWords: false,
        includeChars: false,
        includeSourceMap: false,
        normalize: search,
      ),
      throwsA(isA<PluginSectionTextMapException>()),
    );
    final first = service.build(
      map: map,
      layer: 'source',
      includeWords: false,
      includeChars: true,
      includeSourceMap: false,
      normalize: search,
      limit: 1,
    );
    expect(
      () => service.build(
        map: map,
        layer: 'rendered',
        includeWords: false,
        includeChars: true,
        includeSourceMap: false,
        normalize: search,
        cursor: first.nextCursor,
      ),
      throwsA(
        isA<PluginSectionTextMapException>().having(
          (error) => error.code,
          'code',
          'error.invalid_params',
        ),
      ),
    );
  });
}
