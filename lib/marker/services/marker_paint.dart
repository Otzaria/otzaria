import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/theme/marker_colors.dart';

/// בעלים של הדגשות המרקר בצינור הציור. אינו מזהה תוסף, ולכן לא יופיע
/// בתפריטי `reader-highlight` של תוספים.
const String kMarkerHighlightOwner = 'otzaria.marker';

/// חלקי הסימונים בפסקה [sectionIndex] בלי חפיפה: כל אות מקבלת את החדש ביותר
/// שמכסה אותה, כך שאין ערבוב שקיפויות ומחיקה חושפת את מה שמתחת.
List<PluginHighlight> markerSectionPaint({
  required Iterable<MarkerHighlight> highlights,
  required int sectionIndex,
  required MarkerPalette palette,
  required Brightness brightness,
}) {
  final layers = <({MarkerHighlight mark, MarkerSegment segment})>[];
  for (final mark in highlights) {
    if (sectionIndex < mark.sectionStart || sectionIndex > mark.sectionEnd) {
      continue;
    }
    for (final segment in mark.segments) {
      if (segment.sectionIndex == sectionIndex &&
          segment.status == MarkerAnchorStatus.active &&
          segment.end > segment.start) {
        layers.add((mark: mark, segment: segment));
      }
    }
  }
  if (layers.isEmpty) return const [];
  layers.sort((a, b) {
    final created = a.mark.createdAt.compareTo(b.mark.createdAt);
    return created != 0 ? created : a.mark.id.compareTo(b.mark.id);
  });

  final boundaries = <int>{
    for (final layer in layers) ...[layer.segment.start, layer.segment.end],
  }.toList()..sort();
  final pieces = <({int layer, int start, int end})>[];
  for (var i = 0; i < boundaries.length - 1; i++) {
    final start = boundaries[i];
    final end = boundaries[i + 1];
    var top = -1;
    for (var l = layers.length - 1; l >= 0; l--) {
      final segment = layers[l].segment;
      if (segment.start <= start && segment.end >= end) {
        top = l;
        break;
      }
    }
    if (top < 0) continue;
    if (pieces.isNotEmpty &&
        pieces.last.layer == top &&
        pieces.last.end == start) {
      pieces[pieces.length - 1] = (
        layer: top,
        start: pieces.last.start,
        end: end,
      );
    } else {
      pieces.add((layer: top, start: start, end: end));
    }
  }

  return [
    for (final piece in pieces)
      _toPaint(
        layers[piece.layer].mark,
        layers[piece.layer].segment,
        piece.start,
        piece.end,
        palette,
        brightness,
      ),
  ];
}

PluginHighlight _toPaint(
  MarkerHighlight mark,
  MarkerSegment segment,
  int start,
  int end,
  MarkerPalette palette,
  Brightness brightness,
) {
  final color = palette.colorById(mark.colorId);
  final mode = color?.mode ?? MarkerStyleMode.background;
  return PluginHighlight(
    highlightId: mark.id,
    ownerPluginId: kMarkerHighlightOwner,
    bookId: mark.bookTitle,
    bookUid: mark.bookUid,
    sectionIndex: segment.sectionIndex,
    range: _subRange(segment.range, start, end),
    style: PluginHighlightStyle(
      backgroundColor: color?.hex ?? mark.colorHex,
      opacity: MarkerColors.fillOpacity(
        color?.opacity ?? MarkerColors.defaultOpacity,
        brightness,
      ),
      underline: mode == MarkerStyleMode.underline,
      borderRadius: color?.borderRadius ?? 3,
      markerMode: mode.wireName,
    ),
    createdAt: mark.createdAt,
    updatedAt: mark.updatedAt,
  );
}

const _noContext = PluginAnchorContext(
  raw: '',
  normalized: '',
  maxGraphemes: 0,
  actualGraphemes: 0,
  truncatedAtBoundary: true,
);

/// תת-טווח [start, end) של [range], בגבולות grapheme של הטקסט המקורי.
PluginTextRangeAnchor _subRange(
  PluginTextRangeAnchor range,
  int start,
  int end,
) {
  if (start == range.start.grapheme && end == range.end.grapheme) return range;
  final graphemes = range.exactText.characters.toList(growable: false);
  final from = start - range.start.grapheme;
  final to = end - range.start.grapheme;
  final before = graphemes.take(from).join();
  final text = graphemes.sublist(from, to).join();
  PluginTextOffset shift(String prefix, int grapheme) => PluginTextOffset(
    grapheme: grapheme,
    codePoint: range.start.codePoint + prefix.runes.length,
    utf16: range.start.utf16 + prefix.length,
  );
  return PluginTextRangeAnchor(
    layer: range.layer,
    sourceTextHash: range.sourceTextHash,
    start: shift(before, start),
    end: shift(before + text, end),
    exactText: text,
    beforeText: _noContext,
    afterText: _noContext,
    occurrenceIndexInSection: 0,
    occurrenceCountInSection: 1,
    normalizationProfile: range.normalizationProfile,
  );
}
