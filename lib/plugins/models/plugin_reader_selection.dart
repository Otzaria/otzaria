import 'package:characters/characters.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';

class PluginAnchorContext {
  static const int maxSupportedGraphemes = 128;

  final String raw;
  final String normalized;
  final int maxGraphemes;
  final int actualGraphemes;
  final bool truncatedAtBoundary;

  const PluginAnchorContext({
    required this.raw,
    required this.normalized,
    required this.maxGraphemes,
    required this.actualGraphemes,
    required this.truncatedAtBoundary,
  });

  factory PluginAnchorContext.fromJson(Map<String, dynamic> json) {
    final raw = json['raw'];
    final max = json['maxGraphemes'];
    final actual = json['actualGraphemes'];
    final normalized = json['normalized'];
    final truncated = json['truncatedAtBoundary'];
    if (raw is! String ||
        normalized is! String ||
        max is! int ||
        actual is! int ||
        truncated is! bool ||
        max < 0 ||
        max > maxSupportedGraphemes ||
        actual < 0 ||
        actual > max ||
        raw.characters.length != actual) {
      throw const FormatException('invalid anchor context');
    }
    return PluginAnchorContext(
      raw: raw,
      normalized: normalized,
      maxGraphemes: max,
      actualGraphemes: actual,
      truncatedAtBoundary: truncated,
    );
  }

  Map<String, dynamic> toJson() => {
    'raw': raw,
    'normalized': normalized,
    'maxGraphemes': maxGraphemes,
    'actualGraphemes': actualGraphemes,
    'truncatedAtBoundary': truncatedAtBoundary,
  };
}

class PluginTextRangeAnchor {
  static const int maxExactTextGraphemes = 10000;

  final String layer;
  final String? sourceTextHash;
  final String? renderedTextHash;
  final PluginTextOffset start;
  final PluginTextOffset end;
  final String exactText;
  final PluginAnchorContext beforeText;
  final PluginAnchorContext afterText;
  final int occurrenceIndexInSection;
  final int occurrenceCountInSection;
  final int? startWordIndex;
  final int? endWordIndex;
  final String normalizationProfile;

  const PluginTextRangeAnchor({
    required this.layer,
    this.sourceTextHash,
    this.renderedTextHash,
    required this.start,
    required this.end,
    required this.exactText,
    required this.beforeText,
    required this.afterText,
    required this.occurrenceIndexInSection,
    required this.occurrenceCountInSection,
    this.startWordIndex,
    this.endWordIndex,
    this.normalizationProfile = 'strict',
  });

  factory PluginTextRangeAnchor.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> object(String key) {
      final value = json[key];
      if (value is! Map) throw FormatException('$key must be an object');
      return Map<String, dynamic>.from(value);
    }

    final layer = json['layer'];
    final exactText = json['exactText'];
    final occurrenceIndex = json['occurrenceIndexInSection'];
    final occurrenceCount = json['occurrenceCountInSection'];
    final sourceTextHash = json['sourceTextHash'];
    final renderedTextHash = json['renderedTextHash'];
    final startWordIndex = json['startWordIndex'];
    final endWordIndex = json['endWordIndex'];
    final normalizationProfile = json['normalizationProfile'];
    if (json['type'] != 'text-range-v1' ||
        json['schemaVersion'] != 1 ||
        (layer != 'source' && layer != 'rendered') ||
        exactText is! String ||
        exactText.isEmpty ||
        exactText.characters.length > maxExactTextGraphemes ||
        occurrenceIndex is! int ||
        occurrenceCount is! int ||
        occurrenceIndex < 0 ||
        occurrenceCount <= occurrenceIndex ||
        (sourceTextHash != null && !_isSha256(sourceTextHash)) ||
        (renderedTextHash != null && !_isSha256(renderedTextHash)) ||
        (layer == 'source' && renderedTextHash != null) ||
        (layer == 'rendered' && sourceTextHash != null) ||
        (startWordIndex != null &&
            (startWordIndex is! int || startWordIndex < 0)) ||
        (endWordIndex != null && (endWordIndex is! int || endWordIndex < 0)) ||
        (startWordIndex is int &&
            endWordIndex is int &&
            endWordIndex < startWordIndex) ||
        (normalizationProfile != null && normalizationProfile is! String)) {
      throw const FormatException('invalid text range anchor');
    }
    final start = PluginTextOffset.fromJson(object('start'));
    final end = PluginTextOffset.fromJson(object('end'));
    if (end.grapheme - start.grapheme != exactText.characters.length ||
        end.codePoint - start.codePoint != exactText.runes.length ||
        end.utf16 - start.utf16 != exactText.length) {
      throw const FormatException(
        'anchor offsets must match the exactText boundaries',
      );
    }
    return PluginTextRangeAnchor(
      layer: layer as String,
      sourceTextHash: sourceTextHash as String?,
      renderedTextHash: renderedTextHash as String?,
      start: start,
      end: end,
      exactText: exactText,
      beforeText: PluginAnchorContext.fromJson(object('beforeText')),
      afterText: PluginAnchorContext.fromJson(object('afterText')),
      occurrenceIndexInSection: occurrenceIndex,
      occurrenceCountInSection: occurrenceCount,
      startWordIndex: startWordIndex as int?,
      endWordIndex: endWordIndex as int?,
      normalizationProfile: normalizationProfile as String? ?? 'strict',
    );
  }

  static bool _isSha256(Object value) =>
      value is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  Map<String, dynamic> toJson() => {
    'type': 'text-range-v1',
    'schemaVersion': 1,
    'layer': layer,
    if (sourceTextHash != null) 'sourceTextHash': sourceTextHash,
    if (renderedTextHash != null) 'renderedTextHash': renderedTextHash,
    'start': start.toJson(),
    'end': end.toJson(),
    'exactText': exactText,
    'beforeText': beforeText.toJson(),
    'afterText': afterText.toJson(),
    'occurrenceIndexInSection': occurrenceIndexInSection,
    'occurrenceCountInSection': occurrenceCountInSection,
    if (startWordIndex != null) 'startWordIndex': startWordIndex,
    if (endWordIndex != null) 'endWordIndex': endWordIndex,
    'normalizationProfile': normalizationProfile,
  };
}

class PluginReaderSelection {
  final String selectionId;
  final String bookId;
  final int? id;
  final String? type;
  final String? source;
  final String? bookTitle;
  final String? tabId;
  final int sectionIndex;
  final String? sectionId;
  final String? currentRef;
  final String renderedSelectedText;
  final String sourceSelectedText;
  final String normalizedSelectedText;
  final PluginTextRangeAnchor sourceRange;
  final PluginTextRangeAnchor renderedRange;
  final String direction;
  final DateTime createdAt;

  const PluginReaderSelection({
    required this.selectionId,
    required this.bookId,
    this.id,
    this.type,
    this.source,
    this.bookTitle,
    this.tabId,
    required this.sectionIndex,
    this.sectionId,
    this.currentRef,
    required this.renderedSelectedText,
    required this.sourceSelectedText,
    required this.normalizedSelectedText,
    required this.sourceRange,
    required this.renderedRange,
    required this.direction,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'selectionId': selectionId,
    'bookId': bookId,
    if (id != null) 'id': id,
    if (type != null) 'type': type,
    if (source != null) 'source': source,
    if (bookTitle != null) 'bookTitle': bookTitle,
    if (tabId != null) 'tabId': tabId,
    'sectionIndex': sectionIndex,
    if (sectionId != null) 'sectionId': sectionId,
    'currentRef': currentRef,
    'renderedSelectedText': renderedSelectedText,
    'sourceSelectedText': sourceSelectedText,
    'normalizedSelectedText': normalizedSelectedText,
    'sourceRange': sourceRange.toJson(),
    'renderedRange': renderedRange.toJson(),
    'direction': direction,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
