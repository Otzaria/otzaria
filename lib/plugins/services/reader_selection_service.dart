import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

class ReaderSelectionService {
  static const int contextLength = 30;
  final TextSourceMapService _sourceMapService;

  const ReaderSelectionService({
    this._sourceMapService = const TextSourceMapService(),
  });

  /// Locates a selection inside one rendered section. Restricting the search
  /// to the section chosen by the context menu prevents an identical phrase
  /// in an earlier visible section from stealing the anchor.
  ({int start, int end})? locateRenderedRange({
    required String renderedText,
    required String selectedText,
    int? startHint,
  }) {
    if (selectedText.isEmpty) return null;
    final starts = <int>[];
    var from = 0;
    while (from <= renderedText.length - selectedText.length) {
      final found = renderedText.indexOf(selectedText, from);
      if (found < 0) break;
      starts.add(found);
      from = found + 1;
    }
    if (starts.isEmpty) return null;
    final start = startHint == null
        ? starts.first
        : (starts..sort(
                (a, b) =>
                    (a - startHint).abs().compareTo((b - startHint).abs()),
              ))
              .first;
    return (start: start, end: start + selectedText.length);
  }

  Map<String, dynamic> buildPayload({
    required String bookId,
    required String bookTitle,
    required int sectionIndex,
    required String rawText,
    required RenderSettings settings,
    required String selectedText,
    required int? renderedStartUtf16,
    required int? renderedEndUtf16,
    String? currentRef,
  }) {
    final legacy = <String, dynamic>{
      'text': selectedText,
      'start': renderedStartUtf16,
      'end': renderedEndUtf16,
      'currentRef': currentRef,
      'currentBook': bookTitle,
      'currentBookId': bookId,
      'currentIndex': sectionIndex,
    };
    if (renderedStartUtf16 == null || renderedEndUtf16 == null) return legacy;
    final selection = build(
      bookId: bookId,
      bookTitle: bookTitle,
      sectionIndex: sectionIndex,
      rawText: rawText,
      settings: settings,
      renderedStartUtf16: renderedStartUtf16,
      renderedEndUtf16: renderedEndUtf16,
      currentRef: currentRef,
    );
    return selection == null ? legacy : {...legacy, ...selection.toJson()};
  }

  PluginReaderSelection? build({
    required String bookId,
    required String bookTitle,
    required int sectionIndex,
    required String rawText,
    required RenderSettings settings,
    required int renderedStartUtf16,
    required int renderedEndUtf16,
    String? currentRef,
    String? tabId,
    DateTime? createdAt,
  }) {
    final map = _sourceMapService.build(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      settings: settings,
    );
    final rendered = _GraphemeBoundaries(map.renderedText);
    final renderedStart = rendered.graphemeAtUtf16(renderedStartUtf16);
    final renderedEnd = rendered.graphemeAtUtf16(renderedEndUtf16);
    if (renderedStart == null ||
        renderedEnd == null ||
        renderedStart >= renderedEnd) {
      return null;
    }

    final sourceStart = _sourceMapService.renderedBoundaryToSource(
      map,
      renderedStart,
    );
    final sourceEnd = _sourceMapService.renderedBoundaryToSource(
      map,
      renderedEnd,
    );
    if (sourceStart >= sourceEnd) return null;

    final source = _GraphemeBoundaries(map.sourceText);
    final renderedText = rendered.slice(renderedStart, renderedEnd);
    final sourceText = source.slice(sourceStart, sourceEnd);
    final timestamp = createdAt ?? DateTime.now().toUtc();
    final selectionId = sha256
        .convert(
          utf8.encode(
            '$bookId:$sectionIndex:$sourceStart:$sourceEnd:${timestamp.microsecondsSinceEpoch}',
          ),
        )
        .toString()
        .substring(0, 24);

    return PluginReaderSelection(
      selectionId: selectionId,
      bookId: bookId,
      bookTitle: bookTitle,
      tabId: tabId,
      sectionIndex: sectionIndex,
      currentRef: currentRef,
      renderedSelectedText: renderedText,
      sourceSelectedText: sourceText,
      normalizedSelectedText: _normalize(sourceText),
      sourceRange: _anchor(
        text: source,
        start: sourceStart,
        end: sourceEnd,
        layer: 'source',
        sourceTextHash: map.sourceTextHash,
      ),
      renderedRange: _anchor(
        text: rendered,
        start: renderedStart,
        end: renderedEnd,
        layer: 'rendered',
        renderedTextHash: map.renderedTextHash,
      ),
      direction: _direction(renderedText),
      createdAt: timestamp,
    );
  }

  PluginTextRangeAnchor? buildRangeAnchor({
    required String text,
    required int startGrapheme,
    required int endGrapheme,
    required String layer,
    String? sourceTextHash,
    String? renderedTextHash,
    String? normalizationProfile,
  }) => buildRangeAnchors(
    text: text,
    ranges: [(startGrapheme: startGrapheme, endGrapheme: endGrapheme)],
    layer: layer,
    sourceTextHash: sourceTextHash,
    renderedTextHash: renderedTextHash,
    normalizationProfile: normalizationProfile,
  ).single;

  /// בונה קבוצת עוגנים לאותו טקסט תוך שיתוף חישובי הגבולות והמופעים.
  List<PluginTextRangeAnchor?> buildRangeAnchors({
    required String text,
    required List<({int startGrapheme, int endGrapheme})> ranges,
    required String layer,
    String? sourceTextHash,
    String? renderedTextHash,
    String? normalizationProfile,
  }) {
    if (ranges.isEmpty) return const [];
    final boundaries = _GraphemeBoundaries(text);
    final exactByRange = <int, String>{};
    for (final entry in ranges.asMap().entries) {
      final range = entry.value;
      if (range.startGrapheme < 0 ||
          range.endGrapheme > boundaries.length ||
          range.startGrapheme >= range.endGrapheme) {
        continue;
      }
      exactByRange[entry.key] = boundaries.slice(
        range.startGrapheme,
        range.endGrapheme,
      );
    }
    final occurrences = boundaries.occurrencesFor(exactByRange.values);
    final wordIndices = boundaries.wordIndices();
    return [
      for (final entry in ranges.asMap().entries)
        if (exactByRange[entry.key] case final exact?)
          _anchor(
            text: boundaries,
            start: entry.value.startGrapheme,
            end: entry.value.endGrapheme,
            layer: layer,
            sourceTextHash: sourceTextHash,
            renderedTextHash: renderedTextHash,
            normalizationProfile: normalizationProfile ?? 'strict',
            occurrences: occurrences[exact],
            wordIndices: wordIndices,
          )
        else
          null,
    ];
  }

  PluginTextRangeAnchor _anchor({
    required _GraphemeBoundaries text,
    required int start,
    required int end,
    required String layer,
    String? sourceTextHash,
    String? renderedTextHash,
    String? normalizationProfile,
    List<int>? occurrences,
    List<int>? wordIndices,
  }) {
    final exact = text.slice(start, end);
    final exactOccurrences = occurrences ?? text.occurrences(exact);
    return PluginTextRangeAnchor(
      layer: layer,
      sourceTextHash: sourceTextHash,
      renderedTextHash: renderedTextHash,
      start: text.offsetAt(start),
      end: text.offsetAt(end),
      exactText: exact,
      beforeText: _context(
        text,
        (start - contextLength).clamp(0, start).toInt(),
        start,
      ),
      afterText: _context(
        text,
        end,
        (end + contextLength).clamp(end, text.length).toInt(),
      ),
      occurrenceIndexInSection: exactOccurrences.indexOf(start),
      occurrenceCountInSection: exactOccurrences.length,
      startWordIndex: wordIndices?[start] ?? _wordIndex(text.slice(0, start)),
      endWordIndex: wordIndices?[end] ?? _wordIndex(text.slice(0, end)),
      normalizationProfile: normalizationProfile ?? 'strict',
    );
  }

  PluginAnchorContext _context(
    _GraphemeBoundaries text,
    int start,
    int end,
  ) {
    final raw = text.slice(start, end);
    return PluginAnchorContext(
      raw: raw,
      normalized: _normalize(raw),
      maxGraphemes: contextLength,
      actualGraphemes: end - start,
      truncatedAtBoundary: start == 0 || end == text.length,
    );
  }

  int _wordIndex(String prefix) {
    // trimLeft בלבד: רווח בסוף ה-prefix הוא המפריד שלפני המילה הנוכחית,
    // ומחיקתו (trim מלא) החזירה את אינדקס המילה הקודמת.
    final trimmed = prefix.trimLeft();
    if (trimmed.isEmpty) return 0;
    return RegExp(r'\s+').allMatches(trimmed).length;
  }

  String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _direction(String value) {
    final hasRtl = RegExp(r'[\u0590-\u08FF]').hasMatch(value);
    final hasLtr = RegExp(r'[A-Za-z]').hasMatch(value);
    if (hasRtl && hasLtr) return 'mixed';
    return hasLtr ? 'ltr' : 'rtl';
  }
}

class _GraphemeBoundaries {
  static final RegExp _whitespace = RegExp(r'^\s+$');

  final List<String> values;
  final List<PluginTextOffset> offsets;

  _GraphemeBoundaries(String text)
    : values = text.characters.toList(growable: false),
      offsets = _offsets(text);

  int get length => values.length;

  PluginTextOffset offsetAt(int index) => offsets[index];

  int? graphemeAtUtf16(int utf16) {
    for (var index = 0; index < offsets.length; index++) {
      if (offsets[index].utf16 == utf16) return index;
    }
    return null;
  }

  String slice(int start, int end) => values.sublist(start, end).join();

  List<int> occurrences(String query) {
    final needle = query.characters.toList(growable: false);
    if (needle.isEmpty || needle.length > values.length) return const [];
    final result = <int>[];
    for (var start = 0; start <= values.length - needle.length; start++) {
      var matches = true;
      for (var offset = 0; offset < needle.length; offset++) {
        if (values[start + offset] != needle[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) result.add(start);
    }
    return result;
  }

  Map<String, List<int>> occurrencesFor(Iterable<String> queries) {
    final uniqueQueries = queries.toSet();
    final result = {for (final query in uniqueQueries) query: <int>[]};
    final root = _GraphemeTrieNode();
    for (final query in uniqueQueries) {
      final needle = query.characters.toList(growable: false);
      if (needle.isEmpty || needle.length > values.length) continue;
      var node = root;
      for (final grapheme in needle) {
        node = node.children.putIfAbsent(grapheme, _GraphemeTrieNode.new);
      }
      node.queries.add(query);
    }
    for (var start = 0; start < values.length; start++) {
      var node = root;
      for (var offset = start; offset < values.length; offset++) {
        final child = node.children[values[offset]];
        if (child == null) break;
        node = child;
        for (final query in node.queries) {
          result[query]!.add(start);
        }
      }
    }
    return result;
  }

  List<int> wordIndices() {
    final result = List<int>.filled(values.length + 1, 0);
    var hasText = false;
    var inWhitespace = false;
    var wordIndex = 0;
    for (var index = 0; index < values.length; index++) {
      final isWhitespace = _whitespace.hasMatch(values[index]);
      if (isWhitespace) {
        if (hasText && !inWhitespace) wordIndex++;
        inWhitespace = true;
      } else {
        hasText = true;
        inWhitespace = false;
      }
      result[index + 1] = wordIndex;
    }
    return result;
  }

  static List<PluginTextOffset> _offsets(String text) {
    final result = <PluginTextOffset>[
      const PluginTextOffset(grapheme: 0, codePoint: 0, utf16: 0),
    ];
    var grapheme = 0;
    var codePoint = 0;
    var utf16 = 0;
    for (final cluster in text.characters) {
      result.add(
        PluginTextOffset(
          grapheme: ++grapheme,
          codePoint: codePoint += cluster.runes.length,
          utf16: utf16 += cluster.length,
        ),
      );
    }
    return result;
  }
}

class _GraphemeTrieNode {
  final Map<String, _GraphemeTrieNode> children = {};
  final List<String> queries = [];
}
