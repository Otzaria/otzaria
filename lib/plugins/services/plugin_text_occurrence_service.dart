import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/plugin_text_normalization.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';

class PluginTextOccurrenceService {
  static const int defaultLimit = 50;
  static const int maxLimit = 200;
  static const int maxSectionGraphemes = 50000;

  final PluginTextNormalizationService _normalizationService;
  final ReaderSelectionService _selectionService;

  const PluginTextOccurrenceService({
    this._normalizationService = const PluginTextNormalizationService(),
    this._selectionService = const ReaderSelectionService(),
  });

  PluginFindTextOccurrencesResult find({
    required String bookId,
    required int sectionIndex,
    required String layer,
    required String text,
    required String textHash,
    required String query,
    required PluginNormalizeOptions normalize,
    String? currentRef,
    int limit = defaultLimit,
    String? cursor,
  }) {
    if (layer != 'source' && layer != 'rendered') {
      throw const PluginTextOccurrenceException(
        'error.unsupported_layer',
        'layer must be source or rendered',
      );
    }
    if (sectionIndex < 0 || limit < 1 || limit > maxLimit) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'sectionIndex or limit is invalid',
      );
    }
    if (text.characters.length > maxSectionGraphemes) {
      throw const PluginTextOccurrenceException(
        'error.section_too_large',
        'section exceeds the supported size',
      );
    }
    final normalizedText = _normalizationService.normalize(text, normalize);
    final normalizedQuery = _normalizationService.normalize(query, normalize);
    final needle = normalizedQuery.text.characters.toList(growable: false);
    if (needle.isEmpty) {
      throw const PluginTextOccurrenceException(
        'error.selection_empty',
        'query is empty after normalization',
      );
    }

    final fingerprint = _fingerprint(
      bookId: bookId,
      sectionIndex: sectionIndex,
      layer: layer,
      textHash: textHash,
      query: normalizedQuery.text,
      normalizationKey: [
        normalize.profile.name,
        normalize.ignoreNikud,
        normalize.ignoreTeamim,
        normalize.ignorePunctuation,
        normalize.normalizeWhitespace,
        normalize.normalizeFinalLetters,
      ].join(':'),
    );
    final offset = cursor == null ? 0 : _decodeCursor(cursor, fingerprint);
    final haystack = normalizedText.text.characters.toList(growable: false);
    final matches = _findMatches(haystack, needle);
    if (offset > matches.length) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'cursor offset is no longer valid',
      );
    }
    final page = matches.skip(offset).take(limit).toList(growable: false);
    final results = <PluginTextOccurrence>[];
    for (final normalizedStart in page) {
      final normalizedEnd = normalizedStart + needle.length;
      final start = normalizedText.sourceBoundary(normalizedStart);
      final end = normalizedText.sourceEndBoundary(normalizedEnd);
      final range = _selectionService.buildRangeAnchor(
        text: text,
        startGrapheme: start,
        endGrapheme: end,
        layer: layer,
        sourceTextHash: layer == 'source' ? textHash : null,
        renderedTextHash: layer == 'rendered' ? textHash : null,
        normalizationProfile: normalize.profile.name,
      );
      if (range == null) continue;
      results.add(
        PluginTextOccurrence(
          occurrenceId: _occurrenceId(
            bookId,
            sectionIndex,
            layer,
            start,
            end,
            textHash,
          ),
          bookId: bookId,
          sectionIndex: sectionIndex,
          currentRef: currentRef,
          layer: layer,
          text: range.exactText,
          normalizedText: normalizedQuery.text,
          range: range,
        ),
      );
    }
    final nextOffset = offset + page.length;
    final hasMore = nextOffset < matches.length;
    return PluginFindTextOccurrencesResult(
      results: List.unmodifiable(results),
      hasMore: hasMore,
      nextCursor: hasMore ? _encodeCursor(nextOffset, fingerprint) : null,
      totalCount: matches.length,
    );
  }

  List<int> _findMatches(List<String> haystack, List<String> needle) {
    if (needle.length > haystack.length) return const [];
    final matches = <int>[];
    for (var start = 0; start <= haystack.length - needle.length; start++) {
      var matchesNeedle = true;
      for (var index = 0; index < needle.length; index++) {
        if (haystack[start + index] != needle[index]) {
          matchesNeedle = false;
          break;
        }
      }
      if (matchesNeedle) matches.add(start);
    }
    return matches;
  }

  String _fingerprint({
    required String bookId,
    required int sectionIndex,
    required String layer,
    required String textHash,
    required String query,
    required String normalizationKey,
  }) => sha256
      .convert(
        utf8.encode(
          '$bookId\u0000$sectionIndex\u0000$layer\u0000$textHash\u0000$query\u0000$normalizationKey',
        ),
      )
      .toString()
      .substring(0, 24);

  String _occurrenceId(
    String bookId,
    int sectionIndex,
    String layer,
    int start,
    int end,
    String textHash,
  ) => sha256
      .convert(
        utf8.encode(
          '$bookId:$sectionIndex:$layer:$start:$end:$textHash',
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
      final cursorFingerprint = decoded.substring(separator + 1);
      if (offset < 0 || cursorFingerprint != fingerprint) {
        throw const FormatException();
      }
      return offset;
    } catch (_) {
      throw const PluginTextOccurrenceException(
        'error.invalid_params',
        'cursor is invalid for this query',
      );
    }
  }
}

class PluginTextOccurrence {
  final String occurrenceId;
  final String bookId;
  final int sectionIndex;
  final String? currentRef;
  final String layer;
  final String text;
  final String normalizedText;
  final PluginTextRangeAnchor range;

  const PluginTextOccurrence({
    required this.occurrenceId,
    required this.bookId,
    required this.sectionIndex,
    required this.currentRef,
    required this.layer,
    required this.text,
    required this.normalizedText,
    required this.range,
  });

  Map<String, dynamic> toJson() => {
    'occurrenceId': occurrenceId,
    'bookId': bookId,
    'sectionIndex': sectionIndex,
    'currentRef': currentRef,
    'layer': layer,
    'text': text,
    'normalizedText': normalizedText,
    'range': range.toJson(),
  };
}

class PluginFindTextOccurrencesResult {
  final List<PluginTextOccurrence> results;
  final bool hasMore;
  final String? nextCursor;
  final int totalCount;

  const PluginFindTextOccurrencesResult({
    required this.results,
    required this.hasMore,
    required this.nextCursor,
    required this.totalCount,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'results': results.map((result) => result.toJson()).toList(),
    'hasMore': hasMore,
    if (nextCursor != null) 'nextCursor': nextCursor,
    'totalCount': totalCount,
  };
}

class PluginTextOccurrenceException implements Exception {
  final String code;
  final String message;

  const PluginTextOccurrenceException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}
