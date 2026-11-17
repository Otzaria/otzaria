import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/utils/grapheme_occurrences.dart';

class PluginHighlightAnchorResult {
  final String status;
  final PluginTextRangeAnchor? range;
  final String strategy;
  final double confidence;

  const PluginHighlightAnchorResult({
    required this.status,
    required this.range,
    required this.strategy,
    required this.confidence,
  });
}

class PluginHighlightAnchorService {
  final PluginTextNormalizationService _normalizationService;

  const PluginHighlightAnchorService({
    this._normalizationService = const PluginTextNormalizationService(),
  });

  PluginHighlightAnchorResult resolve({
    required PluginTextRangeAnchor anchor,
    required String sourceText,
  }) {
    if (anchor.layer != 'source' || anchor.exactText.isEmpty) {
      return const PluginHighlightAnchorResult(
        status: 'failed_to_anchor',
        range: null,
        strategy: 'unsupported-anchor',
        confidence: 0,
      );
    }

    final source = sourceText.characters.toList(growable: false);
    final exact = anchor.exactText.characters.toList(growable: false);
    final sourceHash = _hash(sourceText);
    final originalStart = anchor.start.grapheme;
    final originalEnd = originalStart + exact.length;
    if (_matches(source, exact, originalStart)) {
      return PluginHighlightAnchorResult(
        status: 'active',
        range: _rebuildAnchor(
          anchor: anchor,
          source: source,
          start: originalStart,
          end: originalEnd,
          sourceHash: sourceHash,
        ),
        strategy: anchor.sourceTextHash == sourceHash
            ? 'source-hash-offset'
            : 'exact-offset',
        confidence: 1,
      );
    }

    final exactCandidates = findGraphemeOccurrences(source, exact);
    if (exactCandidates.isNotEmpty) {
      final selected = _selectCandidate(
        candidates: exactCandidates,
        source: source,
        exactLength: exact.length,
        anchor: anchor,
      );
      if (selected != null) {
        return PluginHighlightAnchorResult(
          status: 'active',
          range: _rebuildAnchor(
            anchor: anchor,
            source: source,
            start: selected,
            end: selected + exact.length,
            sourceHash: sourceHash,
            occurrences: exactCandidates,
          ),
          strategy: exactCandidates.length == 1
              ? 'unique-exact-text'
              : 'context-or-occurrence',
          confidence: exactCandidates.length == 1 ? 0.95 : 0.85,
        );
      }
      return const PluginHighlightAnchorResult(
        status: 'stale',
        range: null,
        strategy: 'ambiguous-exact-text',
        confidence: 0.5,
      );
    }

    final normalized = _findNormalizedCandidates(anchor, sourceText);
    if (normalized.length == 1) {
      final candidate = normalized.single;
      return PluginHighlightAnchorResult(
        status: 'active',
        range: _rebuildAnchor(
          anchor: anchor,
          source: source,
          start: candidate.$1,
          end: candidate.$2,
          sourceHash: sourceHash,
        ),
        strategy: 'unique-normalized-text',
        confidence: 0.75,
      );
    }
    if (normalized.length > 1) {
      return const PluginHighlightAnchorResult(
        status: 'stale',
        range: null,
        strategy: 'ambiguous-normalized-text',
        confidence: 0.4,
      );
    }
    return const PluginHighlightAnchorResult(
      status: 'failed_to_anchor',
      range: null,
      strategy: 'text-not-found',
      confidence: 0,
    );
  }

  int? _selectCandidate({
    required List<int> candidates,
    required List<String> source,
    required int exactLength,
    required PluginTextRangeAnchor anchor,
  }) {
    final before = anchor.beforeText.raw.characters.toList(growable: false);
    final after = anchor.afterText.raw.characters.toList(growable: false);
    var bestScore = 0;
    int? bestStart;
    var tied = false;
    for (final start in candidates) {
      final score = _contextScore(
        source,
        start,
        start + exactLength,
        before,
        after,
      );
      if (score > bestScore) {
        bestScore = score;
        bestStart = start;
        tied = false;
      } else if (score == bestScore) {
        tied = true;
      }
    }
    if (bestScore > 0 && !tied) {
      return bestStart;
    }
    final occurrence = anchor.occurrenceIndexInSection;
    if (occurrence >= 0 && occurrence < candidates.length) {
      return candidates[occurrence];
    }
    return null;
  }

  int _contextScore(
    List<String> source,
    int start,
    int end,
    List<String> before,
    List<String> after,
  ) {
    var score = 0;
    for (
      var offset = 1;
      offset <= before.length && start - offset >= 0;
      offset++
    ) {
      if (source[start - offset] != before[before.length - offset]) break;
      score++;
    }
    for (
      var offset = 0;
      offset < after.length && end + offset < source.length;
      offset++
    ) {
      if (source[end + offset] != after[offset]) break;
      score++;
    }
    return score;
  }

  List<(int, int)> _findNormalizedCandidates(
    PluginTextRangeAnchor anchor,
    String sourceText,
  ) {
    final profile = PluginNormalizationProfile.parse(
      anchor.normalizationProfile,
    );
    final options = PluginNormalizeOptions.forProfile(profile);
    final normalizedSource = _normalizationService.normalize(
      sourceText,
      options,
    );
    final normalizedExact = _normalizationService
        .normalize(anchor.exactText, options)
        .text;
    if (normalizedExact.isEmpty) return const [];
    final haystack = normalizedSource.text.characters.toList(growable: false);
    final needle = normalizedExact.characters.toList(growable: false);
    return findGraphemeOccurrences(haystack, needle)
        .map(
          (start) => (
            normalizedSource.sourceBoundary(start),
            normalizedSource.sourceEndBoundary(start + needle.length),
          ),
        )
        .toSet()
        .toList();
  }

  PluginTextRangeAnchor _rebuildAnchor({
    required PluginTextRangeAnchor anchor,
    required List<String> source,
    required int start,
    required int end,
    required String sourceHash,
    List<int>? occurrences,
  }) {
    final selected = source.sublist(start, end);
    final matches = occurrences ?? findGraphemeOccurrences(source, selected);
    final offsets = _rangeOffsets(source, start, end);
    return PluginTextRangeAnchor(
      layer: 'source',
      sourceTextHash: sourceHash,
      start: offsets.start,
      end: offsets.end,
      exactText: selected.join(),
      beforeText: _context(source, start, before: true, anchor: anchor),
      afterText: _context(source, end, before: false, anchor: anchor),
      occurrenceIndexInSection: matches.indexOf(start),
      occurrenceCountInSection: matches.length,
      normalizationProfile: anchor.normalizationProfile,
    );
  }

  PluginAnchorContext _context(
    List<String> source,
    int boundary, {
    required bool before,
    required PluginTextRangeAnchor anchor,
  }) {
    final max = before
        ? anchor.beforeText.maxGraphemes
        : anchor.afterText.maxGraphemes;
    final start = before
        ? (boundary - max).clamp(0, boundary).toInt()
        : boundary;
    final end = before
        ? boundary
        : (boundary + max).clamp(boundary, source.length).toInt();
    final raw = source.sublist(start, end).join();
    final profile = PluginNormalizationProfile.parse(
      anchor.normalizationProfile,
    );
    return PluginAnchorContext(
      raw: raw,
      normalized: _normalizationService
          .normalize(raw, PluginNormalizeOptions.forProfile(profile))
          .text,
      maxGraphemes: max,
      actualGraphemes: end - start,
      truncatedAtBoundary: before ? start == 0 : end == source.length,
    );
  }

  ({PluginTextOffset start, PluginTextOffset end}) _rangeOffsets(
    List<String> source,
    int start,
    int end,
  ) {
    var codePoint = 0;
    var utf16 = 0;
    for (var index = 0; index < start; index++) {
      final grapheme = source[index];
      utf16 += grapheme.length;
      codePoint += grapheme.length == 1 ? 1 : grapheme.runes.length;
    }
    final startOffset = PluginTextOffset(
      grapheme: start,
      codePoint: codePoint,
      utf16: utf16,
    );
    for (var index = start; index < end; index++) {
      final grapheme = source[index];
      utf16 += grapheme.length;
      codePoint += grapheme.length == 1 ? 1 : grapheme.runes.length;
    }
    return (
      start: startOffset,
      end: PluginTextOffset(grapheme: end, codePoint: codePoint, utf16: utf16),
    );
  }

  bool _matches(List<String> source, List<String> exact, int start) {
    if (start < 0 || start + exact.length > source.length) return false;
    for (var index = 0; index < exact.length; index++) {
      if (source[start + index] != exact[index]) return false;
    }
    return true;
  }

  String _hash(String text) => sha256.convert(utf8.encode(text)).toString();
}
