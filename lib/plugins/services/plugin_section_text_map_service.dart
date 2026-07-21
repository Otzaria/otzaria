import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';

class PluginSectionTextMapService {
  static const int defaultLimit = 500;
  static const int maxLimit = 2000;
  static const int maxSectionGraphemes = 50000;

  const PluginSectionTextMapService();

  PluginSectionTextMapResult build({
    required PluginTextSourceMap map,
    required String layer,
    required bool includeWords,
    required bool includeChars,
    required bool includeSourceMap,
    required PluginNormalizeOptions normalize,
    String? currentRef,
    int limit = defaultLimit,
    String? cursor,
  }) {
    if (!{'source', 'rendered', 'both'}.contains(layer)) {
      throw const PluginSectionTextMapException(
        'error.unsupported_layer',
        'layer must be source, rendered, or both',
      );
    }
    if (limit < 1 || limit > maxLimit) {
      throw const PluginSectionTextMapException(
        'error.invalid_params',
        'limit must be between 1 and 2000',
      );
    }
    if (map.sourceText.characters.length > maxSectionGraphemes ||
        map.renderedText.characters.length > maxSectionGraphemes) {
      throw const PluginSectionTextMapException(
        'error.section_too_large',
        'section exceeds the supported size',
      );
    }
    final layers = layer == 'both' ? const ['source', 'rendered'] : [layer];
    final descriptors = <_TokenDescriptor>[];
    for (final currentLayer in layers) {
      final text = currentLayer == 'source' ? map.sourceText : map.renderedText;
      if (includeWords) descriptors.addAll(_words(text, currentLayer));
      if (includeChars) descriptors.addAll(_chars(text, currentLayer));
    }
    final fingerprint = _fingerprint(
      map,
      layer,
      includeWords,
      includeChars,
      includeSourceMap,
      normalize,
    );
    final offset = cursor == null ? 0 : _decodeCursor(cursor, fingerprint);
    if (offset > descriptors.length) {
      throw const PluginSectionTextMapException(
        'error.invalid_params',
        'cursor offset is no longer valid',
      );
    }
    final page = descriptors.skip(offset).take(limit).toList(growable: false);
    final words = includeWords ? <PluginWordToken>[] : null;
    final chars = includeChars ? <PluginCharToken>[] : null;
    final offsets = {
      for (final currentLayer in layers)
        currentLayer: _GraphemeOffsets(
          currentLayer == 'source' ? map.sourceText : map.renderedText,
        ),
    };
    final wordDescriptors = page
        .where((descriptor) => descriptor.isWord)
        .toList(growable: false);
    const sourceMapService = TextSourceMapService();
    final mappedRanges = [
      for (final descriptor in wordDescriptors)
        _mappedWordRanges(map, descriptor, sourceMapService),
    ];
    const anchorService = ReaderSelectionService();
    final sourceAnchors = anchorService.buildRangeAnchors(
      text: map.sourceText,
      ranges: [for (final ranges in mappedRanges) ranges.source],
      layer: 'source',
      sourceTextHash: map.sourceTextHash,
    );
    final renderedAnchors = anchorService.buildRangeAnchors(
      text: map.renderedText,
      ranges: [for (final ranges in mappedRanges) ranges.rendered],
      layer: 'rendered',
      renderedTextHash: map.renderedTextHash,
    );
    var wordOffset = 0;
    for (final descriptor in page) {
      final normalized = const PluginTextNormalizationService()
          .normalize(descriptor.text, normalize)
          .text;
      if (descriptor.isWord) {
        words!.add(
          _wordToken(
            descriptor,
            normalized,
            offsets[descriptor.layer]!,
            sourceAnchors[wordOffset],
            renderedAnchors[wordOffset],
          ),
        );
        wordOffset++;
      } else {
        chars!.add(
          PluginCharToken(
            charIndex: descriptor.index,
            layer: descriptor.layer,
            text: descriptor.text,
            normalizedText: normalized,
            start: offsets[descriptor.layer]!.at(descriptor.start),
            end: offsets[descriptor.layer]!.at(descriptor.end),
          ),
        );
      }
    }
    final nextOffset = offset + page.length;
    final hasMore = nextOffset < descriptors.length;
    return PluginSectionTextMapResult(
      bookId: map.bookId,
      sectionIndex: map.sectionIndex,
      currentRef: currentRef,
      sourceText: layer == 'rendered' ? null : map.sourceText,
      renderedText: layer == 'source' ? null : map.renderedText,
      sourceTextHash: layer == 'rendered' ? null : map.sourceTextHash,
      renderedTextHash: layer == 'source' ? null : map.renderedTextHash,
      sourceMap: includeSourceMap ? map : null,
      words: words == null ? null : List.unmodifiable(words),
      chars: chars == null ? null : List.unmodifiable(chars),
      hasMore: hasMore,
      nextCursor: hasMore ? _encodeCursor(nextOffset, fingerprint) : null,
    );
  }

  PluginWordToken _wordToken(
    _TokenDescriptor descriptor,
    String normalized,
    _GraphemeOffsets offsets,
    PluginTextRangeAnchor? sourceRange,
    PluginTextRangeAnchor? renderedRange,
  ) {
    return PluginWordToken(
      wordIndex: descriptor.index,
      layer: descriptor.layer,
      text: descriptor.text,
      normalizedText: normalized,
      start: offsets.at(descriptor.start),
      end: offsets.at(descriptor.end),
      sourceRange: sourceRange,
      renderedRange: renderedRange,
    );
  }

  _MappedWordRanges _mappedWordRanges(
    PluginTextSourceMap map,
    _TokenDescriptor descriptor,
    TextSourceMapService sourceMapService,
  ) {
    final sourceStart = descriptor.layer == 'source'
        ? descriptor.start
        : sourceMapService.renderedBoundaryToSource(map, descriptor.start);
    final sourceEnd = descriptor.layer == 'source'
        ? descriptor.end
        : sourceMapService.renderedBoundaryToSource(map, descriptor.end);
    final renderedStart = descriptor.layer == 'rendered'
        ? descriptor.start
        : sourceMapService.sourceBoundaryToRendered(map, descriptor.start);
    final renderedEnd = descriptor.layer == 'rendered'
        ? descriptor.end
        : sourceMapService.sourceBoundaryToRendered(map, descriptor.end);
    return (
      source: (startGrapheme: sourceStart, endGrapheme: sourceEnd),
      rendered: (startGrapheme: renderedStart, endGrapheme: renderedEnd),
    );
  }

  List<_TokenDescriptor> _words(String text, String layer) {
    final graphemes = text.characters.toList(growable: false);
    final result = <_TokenDescriptor>[];
    var start = -1;
    var wordIndex = 0;
    for (var index = 0; index <= graphemes.length; index++) {
      final isWord = index < graphemes.length && _isWord(graphemes[index]);
      if (isWord && start < 0) start = index;
      if (!isWord && start >= 0) {
        result.add((
          index: wordIndex++,
          layer: layer,
          text: graphemes.sublist(start, index).join(),
          start: start,
          end: index,
          isWord: true,
        ));
        start = -1;
      }
    }
    return result;
  }

  List<_TokenDescriptor> _chars(String text, String layer) => [
    for (final entry in text.characters.toList(growable: false).asMap().entries)
      (
        index: entry.key,
        layer: layer,
        text: entry.value,
        start: entry.key,
        end: entry.key + 1,
        isWord: false,
      ),
  ];

  bool _isWord(String grapheme) => grapheme.runes.any(
    (rune) =>
        (rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x0590 &&
            rune <= 0x05FF &&
            !{0x05BE, 0x05C0, 0x05C3, 0x05C6, 0x05F3, 0x05F4}.contains(rune)),
  );

  String _fingerprint(
    PluginTextSourceMap map,
    String layer,
    bool words,
    bool chars,
    bool sourceMap,
    PluginNormalizeOptions options,
  ) => sha256
      .convert(
        utf8.encode(
          [
            map.bookId,
            map.sectionIndex,
            map.sourceTextHash,
            map.renderedTextHash,
            layer,
            words,
            chars,
            sourceMap,
            options.profile.name,
            options.ignoreNikud,
            options.ignoreTeamim,
            options.ignorePunctuation,
            options.normalizeWhitespace,
            options.normalizeFinalLetters,
          ].join('\u0000'),
        ),
      )
      .toString()
      .substring(0, 24);

  String _encodeCursor(int offset, String fingerprint) =>
      base64Url.encode(utf8.encode('$offset:$fingerprint')).replaceAll('=', '');

  int _decodeCursor(String cursor, String fingerprint) {
    try {
      final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64Url.decode(padded));
      final separator = decoded.indexOf(':');
      final offset = int.parse(decoded.substring(0, separator));
      if (offset < 0 || decoded.substring(separator + 1) != fingerprint) {
        throw const FormatException();
      }
      return offset;
    } catch (_) {
      throw const PluginSectionTextMapException(
        'error.invalid_params',
        'cursor is invalid for this request',
      );
    }
  }
}

typedef _TokenDescriptor = ({
  int index,
  String layer,
  String text,
  int start,
  int end,
  bool isWord,
});

typedef _MappedWordRanges = ({
  ({int startGrapheme, int endGrapheme}) source,
  ({int startGrapheme, int endGrapheme}) rendered,
});

class PluginWordToken {
  final int wordIndex;
  final String layer;
  final String text;
  final String normalizedText;
  final PluginTextOffset start;
  final PluginTextOffset end;
  final PluginTextRangeAnchor? sourceRange;
  final PluginTextRangeAnchor? renderedRange;

  const PluginWordToken({
    required this.wordIndex,
    required this.layer,
    required this.text,
    required this.normalizedText,
    required this.start,
    required this.end,
    required this.sourceRange,
    required this.renderedRange,
  });

  Map<String, dynamic> toJson() => {
    'wordIndex': wordIndex,
    'layer': layer,
    'text': text,
    'normalizedText': normalizedText,
    'start': start.toJson(),
    'end': end.toJson(),
    if (sourceRange != null) 'sourceRange': sourceRange!.toJson(),
    if (renderedRange != null) 'renderedRange': renderedRange!.toJson(),
  };
}

class PluginCharToken {
  final int charIndex;
  final String layer;
  final String text;
  final String normalizedText;
  final PluginTextOffset start;
  final PluginTextOffset end;

  const PluginCharToken({
    required this.charIndex,
    required this.layer,
    required this.text,
    required this.normalizedText,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() => {
    'charIndex': charIndex,
    'layer': layer,
    'text': text,
    'normalizedText': normalizedText,
    'start': start.toJson(),
    'end': end.toJson(),
  };
}

class PluginSectionTextMapResult {
  final String bookId;
  final int sectionIndex;
  final String? currentRef;
  final String? sourceText;
  final String? renderedText;
  final String? sourceTextHash;
  final String? renderedTextHash;
  final PluginTextSourceMap? sourceMap;
  final List<PluginWordToken>? words;
  final List<PluginCharToken>? chars;
  final bool hasMore;
  final String? nextCursor;

  const PluginSectionTextMapResult({
    required this.bookId,
    required this.sectionIndex,
    required this.currentRef,
    required this.sourceText,
    required this.renderedText,
    required this.sourceTextHash,
    required this.renderedTextHash,
    required this.sourceMap,
    required this.words,
    required this.chars,
    required this.hasMore,
    required this.nextCursor,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'bookId': bookId,
    'sectionIndex': sectionIndex,
    'currentRef': currentRef,
    if (sourceText != null) 'sourceText': sourceText,
    if (renderedText != null) 'renderedText': renderedText,
    if (sourceTextHash != null) 'sourceTextHash': sourceTextHash,
    if (renderedTextHash != null) 'renderedTextHash': renderedTextHash,
    if (sourceMap != null) 'sourceMap': sourceMap!.toJson(),
    if (words != null) 'words': words!.map((word) => word.toJson()).toList(),
    if (chars != null) 'chars': chars!.map((char) => char.toJson()).toList(),
    'hasMore': hasMore,
    if (nextCursor != null) 'nextCursor': nextCursor,
  };
}

class PluginSectionTextMapException implements Exception {
  final String code;
  final String message;

  const PluginSectionTextMapException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class _GraphemeOffsets {
  final List<PluginTextOffset> values;

  _GraphemeOffsets(String text) : values = _build(text);

  PluginTextOffset at(int boundary) => values[boundary];

  static List<PluginTextOffset> _build(String text) {
    final values = <PluginTextOffset>[
      const PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
    ];
    var grapheme = 0;
    var codePoint = 0;
    var utf16 = 0;
    for (final value in text.characters) {
      values.add(
        PluginTextOffset(
          grapheme: ++grapheme,
          codePoint: codePoint += value.runes.length,
          utf16: utf16 += value.length,
        ),
      );
    }
    return values;
  }
}
