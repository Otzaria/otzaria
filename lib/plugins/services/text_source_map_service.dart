import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// בונה מיפוי דו־כיווני בין טקסט הספר הקנוני לבין הטקסט המוצג.
class TextSourceMapService {
  static const int _resyncWindow = 64;

  const TextSourceMapService();

  /// מתרגם גבול grapheme מהטקסט המוצג לגבול המקביל בטקסט המקור.
  int renderedBoundaryToSource(
    PluginTextSourceMap map,
    int renderedGrapheme,
  ) {
    final boundary = renderedGrapheme
        .clamp(0, map.renderedText.characters.length)
        .toInt();
    for (final segment in map.mappings) {
      final renderedStart = segment.renderedStart.grapheme;
      final renderedEnd = segment.renderedEnd.grapheme;
      if (boundary < renderedStart || boundary > renderedEnd) continue;

      final sourceStart = segment.sourceStart.grapheme;
      final sourceEnd = segment.sourceEnd.grapheme;
      final renderedLength = renderedEnd - renderedStart;
      final sourceLength = sourceEnd - sourceStart;
      if (renderedLength == 0) return sourceEnd;
      if (segment.kind == PluginTextSourceMapKind.identity) {
        return sourceStart + (boundary - renderedStart);
      }
      final progress = (boundary - renderedStart) / renderedLength;
      return sourceStart + (sourceLength * progress).round();
    }
    return map.sourceText.characters.length;
  }

  /// מתרגם גבול grapheme מהמקור לגבול המקביל בטקסט המוצג.
  int sourceBoundaryToRendered(
    PluginTextSourceMap map,
    int sourceGrapheme,
  ) {
    final boundary = sourceGrapheme
        .clamp(0, map.sourceText.characters.length)
        .toInt();
    for (final segment in map.mappings) {
      final sourceStart = segment.sourceStart.grapheme;
      final sourceEnd = segment.sourceEnd.grapheme;
      if (boundary < sourceStart || boundary > sourceEnd) continue;

      final renderedStart = segment.renderedStart.grapheme;
      final renderedEnd = segment.renderedEnd.grapheme;
      final sourceLength = sourceEnd - sourceStart;
      final renderedLength = renderedEnd - renderedStart;
      if (sourceLength == 0) return renderedEnd;
      if (segment.kind == PluginTextSourceMapKind.identity) {
        return renderedStart + (boundary - sourceStart);
      }
      final progress = (boundary - sourceStart) / sourceLength;
      return renderedStart + (renderedLength * progress).round();
    }
    return map.renderedText.characters.length;
  }

  PluginTextSourceMap build({
    required String bookId,
    required int sectionIndex,
    required String rawText,
    required RenderSettings settings,
  }) {
    return buildFromProcessedHtml(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      processedHtml: TextRendererService.processText(rawText, settings),
    );
  }

  PluginTextSourceMap buildFromProcessedHtml({
    required String bookId,
    required int sectionIndex,
    required String rawText,
    required String processedHtml,
  }) {
    final sourceText = TextRendererService.stripHtml(rawText);
    final renderedText = TextRendererService.stripHtml(
      processedHtml,
    );
    final source = _GraphemeText(sourceText);
    final rendered = _GraphemeText(renderedText);

    return PluginTextSourceMap(
      bookId: bookId,
      sectionIndex: sectionIndex,
      sourceText: sourceText,
      renderedText: renderedText,
      sourceTextHash: _hash(sourceText),
      renderedTextHash: _hash(renderedText),
      mappings: _buildSegments(source, rendered),
    );
  }

  List<PluginTextSourceMapSegment> _buildSegments(
    _GraphemeText source,
    _GraphemeText rendered,
  ) {
    final result = <PluginTextSourceMapSegment>[];
    var sourceIndex = 0;
    var renderedIndex = 0;

    while (sourceIndex < source.length && renderedIndex < rendered.length) {
      if (source.values[sourceIndex] == rendered.values[renderedIndex]) {
        final sourceStart = sourceIndex;
        final renderedStart = renderedIndex;
        while (sourceIndex < source.length &&
            renderedIndex < rendered.length &&
            source.values[sourceIndex] == rendered.values[renderedIndex]) {
          sourceIndex++;
          renderedIndex++;
        }
        result.add(
          _segment(
            source,
            rendered,
            sourceStart,
            sourceIndex,
            renderedStart,
            renderedIndex,
            PluginTextSourceMapKind.identity,
          ),
        );
        continue;
      }

      final resync = _findResync(source, rendered, sourceIndex, renderedIndex);
      if (resync == null) {
        result.add(
          _changedSegment(
            source,
            rendered,
            sourceIndex,
            source.length,
            renderedIndex,
            rendered.length,
          ),
        );
        break;
      }

      result.add(
        _changedSegment(
          source,
          rendered,
          sourceIndex,
          resync.$1,
          renderedIndex,
          resync.$2,
        ),
      );
      sourceIndex = resync.$1;
      renderedIndex = resync.$2;
    }

    if (sourceIndex < source.length || renderedIndex < rendered.length) {
      result.add(
        _changedSegment(
          source,
          rendered,
          sourceIndex,
          source.length,
          renderedIndex,
          rendered.length,
        ),
      );
    }
    return result;
  }

  (int, int)? _findResync(
    _GraphemeText source,
    _GraphemeText rendered,
    int sourceStart,
    int renderedStart,
  ) {
    (int, int)? best;
    var bestCost = 1 << 30;
    final sourceEnd = (sourceStart + _resyncWindow)
        .clamp(0, source.length)
        .toInt();
    final renderedEnd = (renderedStart + _resyncWindow)
        .clamp(0, rendered.length)
        .toInt();

    for (
      var sourceIndex = sourceStart;
      sourceIndex < sourceEnd;
      sourceIndex++
    ) {
      for (
        var renderedIndex = renderedStart;
        renderedIndex < renderedEnd;
        renderedIndex++
      ) {
        if (source.values[sourceIndex] != rendered.values[renderedIndex]) {
          continue;
        }
        final cost =
            (sourceIndex - sourceStart) + (renderedIndex - renderedStart);
        if (cost < bestCost) {
          best = (sourceIndex, renderedIndex);
          bestCost = cost;
        }
      }
    }
    return best;
  }

  PluginTextSourceMapSegment _changedSegment(
    _GraphemeText source,
    _GraphemeText rendered,
    int sourceStart,
    int sourceEnd,
    int renderedStart,
    int renderedEnd,
  ) {
    final kind = sourceStart == sourceEnd
        ? PluginTextSourceMapKind.inserted
        : renderedStart == renderedEnd
        ? PluginTextSourceMapKind.hidden
        : PluginTextSourceMapKind.substitution;
    return _segment(
      source,
      rendered,
      sourceStart,
      sourceEnd,
      renderedStart,
      renderedEnd,
      kind,
    );
  }

  PluginTextSourceMapSegment _segment(
    _GraphemeText source,
    _GraphemeText rendered,
    int sourceStart,
    int sourceEnd,
    int renderedStart,
    int renderedEnd,
    PluginTextSourceMapKind kind,
  ) {
    return PluginTextSourceMapSegment(
      sourceStart: source.offsetAt(sourceStart),
      sourceEnd: source.offsetAt(sourceEnd),
      renderedStart: rendered.offsetAt(renderedStart),
      renderedEnd: rendered.offsetAt(renderedEnd),
      kind: kind,
    );
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
}

class _GraphemeText {
  final List<String> values;
  final List<PluginTextOffset> boundaries;

  _GraphemeText(String text)
    : values = text.characters.toList(growable: false),
      boundaries = _buildBoundaries(text);

  int get length => values.length;

  PluginTextOffset offsetAt(int index) => boundaries[index];

  static List<PluginTextOffset> _buildBoundaries(String text) {
    final result = <PluginTextOffset>[
      const PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
    ];
    var grapheme = 0;
    var codePoint = 0;
    var utf16 = 0;
    for (final cluster in text.characters) {
      grapheme++;
      codePoint += cluster.runes.length;
      utf16 += cluster.length;
      result.add(
        PluginTextOffset(
          grapheme: grapheme,
          codePoint: codePoint,
          utf16: utf16,
        ),
      );
    }
    return result;
  }
}
