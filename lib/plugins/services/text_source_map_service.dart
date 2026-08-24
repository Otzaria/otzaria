import 'dart:collection';
import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// בונה מיפוי דו־כיווני בין טקסט הספר הקנוני לבין הטקסט המוצג.
class TextSourceMapService {
  static const int _resyncWindow = 64;
  static const int _maxResyncRunProbe = 8;
  static const int _mapCacheMaxChars = 2 * 1024 * 1024;

  static final LinkedHashMap<_MapCacheKey, PluginTextSourceMap> _mapCache =
      LinkedHashMap<_MapCacheKey, PluginTextSourceMap>();
  static int _mapCacheChars = 0;

  const TextSourceMapService();

  @visibleForTesting
  static void clearCacheForTesting() {
    _mapCache.clear();
    _mapCacheChars = 0;
  }

  @visibleForTesting
  static int get cachedMapCount => _mapCache.length;

  /// מתרגם גבול grapheme מהטקסט המוצג לגבול המקביל בטקסט המקור.
  int renderedBoundaryToSource(
    PluginTextSourceMap map,
    int renderedGrapheme,
  ) {
    final boundary = renderedGrapheme
        .clamp(0, map.renderedGraphemeLength)
        .toInt();
    final index = _firstSegmentEndingAtOrAfter(
      map.mappings,
      boundary,
      rendered: true,
    );
    if (index >= map.mappings.length) return map.sourceGraphemeLength;
    final segment = map.mappings[index];
    final renderedStart = segment.renderedStart.grapheme;
    if (boundary < renderedStart) return map.sourceGraphemeLength;

    final sourceStart = segment.sourceStart.grapheme;
    final sourceEnd = segment.sourceEnd.grapheme;
    final renderedLength = segment.renderedEnd.grapheme - renderedStart;
    final sourceLength = sourceEnd - sourceStart;
    if (renderedLength == 0) return sourceEnd;
    if (segment.kind == PluginTextSourceMapKind.identity) {
      return sourceStart + (boundary - renderedStart);
    }
    final progress = (boundary - renderedStart) / renderedLength;
    return sourceStart + (sourceLength * progress).round();
  }

  /// מתרגם גבול grapheme מהמקור לגבול המקביל בטקסט המוצג.
  int sourceBoundaryToRendered(
    PluginTextSourceMap map,
    int sourceGrapheme,
  ) {
    final boundary = sourceGrapheme.clamp(0, map.sourceGraphemeLength).toInt();
    final index = _firstSegmentEndingAtOrAfter(
      map.mappings,
      boundary,
      rendered: false,
    );
    if (index >= map.mappings.length) return map.renderedGraphemeLength;
    final segment = map.mappings[index];
    final sourceStart = segment.sourceStart.grapheme;
    if (boundary < sourceStart) return map.renderedGraphemeLength;

    final renderedStart = segment.renderedStart.grapheme;
    final renderedEnd = segment.renderedEnd.grapheme;
    final sourceLength = segment.sourceEnd.grapheme - sourceStart;
    final renderedLength = renderedEnd - renderedStart;
    if (sourceLength == 0) return renderedEnd;
    if (segment.kind == PluginTextSourceMapKind.identity) {
      return renderedStart + (boundary - sourceStart);
    }
    final progress = (boundary - sourceStart) / sourceLength;
    return renderedStart + (renderedLength * progress).round();
  }

  /// האינדקס הראשון שסופו ≥ [boundary]. ה-segments רציפים ועולים, ולכן זהו
  /// גם ה-segment הראשון שמכיל את הגבול — התנהגות זהה לסריקה לינארית.
  int _firstSegmentEndingAtOrAfter(
    List<PluginTextSourceMapSegment> segments,
    int boundary, {
    required bool rendered,
  }) {
    var low = 0;
    var high = segments.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final segment = segments[mid];
      final end = rendered
          ? segment.renderedEnd.grapheme
          : segment.sourceEnd.grapheme;
      if (end < boundary) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
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

  /// כמו [buildFromProcessedHtml], אך מוגש ממטמון כשהקלט זהה.
  ///
  /// נתיב ההדגשות בונה את המפה בכל פריים גלילה; המפתח נושא את שני הטקסטים,
  /// ולכן כל שינוי תוכן או הגדרת תצוגה מייצר מפתח אחר ואין פסילה ידנית.
  PluginTextSourceMap cachedFromProcessedHtml({
    required String bookId,
    required int sectionIndex,
    required String rawText,
    required String processedHtml,
  }) {
    final key = _MapCacheKey(bookId, sectionIndex, rawText, processedHtml);
    final cached = _mapCache.remove(key);
    if (cached != null) {
      _mapCache[key] = cached;
      return cached;
    }
    final map = buildFromProcessedHtml(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      processedHtml: processedHtml,
    );
    _mapCache[key] = map;
    _mapCacheChars += rawText.length + processedHtml.length;
    while (_mapCacheChars > _mapCacheMaxChars && _mapCache.length > 1) {
      final oldest = _mapCache.keys.first;
      _mapCache.remove(oldest);
      _mapCacheChars -= oldest.rawText.length + oldest.processedHtml.length;
    }
    return map;
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
      sourceGraphemeLength: source.length,
      renderedGraphemeLength: rendered.length,
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

  /// מאתר את נקודת ההיסנכרון הטובה ביותר: העלות היא המרחק פחות אורך הרצף
  /// הרצוף שנמשך ממנה.
  ///
  /// לפי המרחק בלבד, גרפמה בודדת שמזדמנת קרוב (רווח, אות שכיחה) מנצחת התאמה
  /// אמיתית ורצופה, וההיסנכרון השגוי מזיז את כל המיפוי שאחריו.
  (int, int)? _findResync(
    _GraphemeText source,
    _GraphemeText rendered,
    int sourceStart,
    int renderedStart,
  ) {
    final sourceSpan =
        (sourceStart + _resyncWindow).clamp(0, source.length).toInt() -
        sourceStart;
    final renderedSpan =
        (renderedStart + _resyncWindow).clamp(0, rendered.length).toInt() -
        renderedStart;
    if (sourceSpan <= 0 || renderedSpan <= 0) return null;

    (int, int)? best;
    var bestScore = 1 << 30;
    // איטרציה באלכסונים = מרחק עולה, ולכן אלכסון שאף רצף מלא בו לא יוכל
    // לשפר את התוצאה מסיים את החיפוש.
    for (
      var distance = 0;
      distance <= sourceSpan + renderedSpan - 2;
      distance++
    ) {
      if (distance - _maxResyncRunProbe > bestScore) break;
      final lowest = distance - renderedSpan + 1;
      final from = lowest < 0 ? 0 : lowest;
      final to = distance < sourceSpan - 1 ? distance : sourceSpan - 1;
      for (var sourceOffset = from; sourceOffset <= to; sourceOffset++) {
        final sourceIndex = sourceStart + sourceOffset;
        final renderedIndex = renderedStart + distance - sourceOffset;
        if (source.values[sourceIndex] != rendered.values[renderedIndex]) {
          continue;
        }
        final score =
            distance - _runLength(source, rendered, sourceIndex, renderedIndex);
        if (score < bestScore) {
          best = (sourceIndex, renderedIndex);
          bestScore = score;
        }
      }
    }
    return best;
  }

  int _runLength(
    _GraphemeText source,
    _GraphemeText rendered,
    int sourceIndex,
    int renderedIndex,
  ) {
    var run = 0;
    while (run < _maxResyncRunProbe &&
        sourceIndex + run < source.length &&
        renderedIndex + run < rendered.length &&
        source.values[sourceIndex + run] ==
            rendered.values[renderedIndex + run]) {
      run++;
    }
    return run;
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

class _MapCacheKey {
  final String bookId;
  final int sectionIndex;
  final String rawText;
  final String processedHtml;

  const _MapCacheKey(
    this.bookId,
    this.sectionIndex,
    this.rawText,
    this.processedHtml,
  );

  @override
  bool operator ==(Object other) =>
      other is _MapCacheKey &&
      other.sectionIndex == sectionIndex &&
      other.bookId == bookId &&
      other.rawText == rawText &&
      other.processedHtml == processedHtml;

  @override
  int get hashCode => Object.hash(bookId, sectionIndex, rawText, processedHtml);
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
