import 'dart:convert';

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

  group('token pagination', () {
    final mixedMap = const TextSourceMapService().build(
      bookId: 'mixed',
      sectionIndex: 0,
      rawText: 'אָ 🙂 ב',
      settings: const RenderSettings(removeNikud: true),
    );

    PluginSectionTextMapResult page({
      String? cursor,
      int limit = 3,
      bool includeWords = true,
      bool includeChars = true,
    }) => service.build(
      map: mixedMap,
      layer: 'both',
      includeWords: includeWords,
      includeChars: includeChars,
      includeSourceMap: false,
      normalize: search,
      limit: limit,
      cursor: cursor,
    );

    test('keeps word, character and layer order across pages', () {
      final pages = <PluginSectionTextMapResult>[];
      String? cursor;
      do {
        final result = page(cursor: cursor);
        pages.add(result);
        cursor = result.nextCursor;
      } while (cursor != null);

      expect(
        [
          for (final result in pages)
            [
              [for (final word in result.words!) '${word.layer}:${word.text}'],
              [for (final char in result.chars!) '${char.layer}:${char.text}'],
              result.hasMore,
            ],
        ],
        [
          [
            ['source:אָ', 'source:ב'],
            ['source:אָ'],
            true,
          ],
          [
            <String>[],
            ['source: ', 'source:🙂', 'source: '],
            true,
          ],
          [
            ['rendered:א', 'rendered:ב'],
            ['source:ב'],
            true,
          ],
          [
            <String>[],
            ['rendered:א', 'rendered: ', 'rendered:🙂'],
            true,
          ],
          [
            <String>[],
            ['rendered: ', 'rendered:ב'],
            false,
          ],
        ],
      );
      final emoji = pages[1].chars![1];
      expect(emoji.charIndex, 2);
      expect(emoji.start.toJson(), {'grapheme': 2, 'codePoint': 3, 'utf16': 3});
      expect(emoji.end.toJson(), {'grapheme': 3, 'codePoint': 4, 'utf16': 5});
    });

    test('an exact final page has no next cursor', () {
      final first = page(limit: 7);
      final last = page(limit: 7, cursor: first.nextCursor);

      expect(first.hasMore, isTrue);
      expect(last.words, hasLength(2));
      expect(last.chars, hasLength(5));
      expect(last.hasMore, isFalse);
      expect(last.nextCursor, isNull);
    });

    test('accepts an end cursor but rejects one past the end', () {
      final cursor = page(limit: 1).nextCursor!;
      final atEnd = page(cursor: _cursorAt(cursor, 14));

      expect(atEnd.words, isEmpty);
      expect(atEnd.chars, isEmpty);
      expect(atEnd.hasMore, isFalse);
      expect(atEnd.nextCursor, isNull);
      expect(
        () => page(cursor: _cursorAt(cursor, 15)),
        throwsA(
          isA<PluginSectionTextMapException>()
              .having((error) => error.code, 'code', 'error.invalid_params')
              .having(
                (error) => error.message,
                'message',
                'cursor offset is no longer valid',
              ),
        ),
      );
    });

    test('returns a complete empty page when no tokens are requested', () {
      final result = page(includeWords: false, includeChars: false);

      expect(result.words, isNull);
      expect(result.chars, isNull);
      expect(result.hasMore, isFalse);
      expect(result.nextCursor, isNull);
    });

    test('rejects a cursor from a different token request', () {
      final first = page(limit: 1);

      expect(
        () => page(cursor: first.nextCursor, includeWords: false),
        throwsA(
          isA<PluginSectionTextMapException>().having(
            (error) => error.message,
            'message',
            'cursor is invalid for this request',
          ),
        ),
      );
    });
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

String _cursorAt(String cursor, int offset) {
  final decoded = utf8.decode(base64Url.decode(base64Url.normalize(cursor)));
  return encodePluginTextCursor(
    offset,
    decoded.substring(decoded.indexOf(':') + 1),
  );
}
