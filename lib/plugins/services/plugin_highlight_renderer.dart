import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';

class PluginHighlightRenderer {
  final TextSourceMapService _sourceMapService;

  const PluginHighlightRenderer({
    this._sourceMapService = const TextSourceMapService(),
  });

  String apply({
    required String bookId,
    required int sectionIndex,
    required String rawText,
    required String processedHtml,
    required List<PluginHighlight> highlights,
    String? revealedHighlightId,
  }) => renderWithRanges(
    bookId: bookId,
    sectionIndex: sectionIndex,
    rawText: rawText,
    processedHtml: processedHtml,
    highlights: highlights,
    revealedHighlightId: revealedHighlightId,
  ).html;

  /// מחיל הדגשות ומחזיר גם את טווחי הציור, תוך בניית מפת מקור פעם אחת.
  ({String html, List<PluginHighlightRenderedRange> ranges}) renderWithRanges({
    required String bookId,
    required int sectionIndex,
    required String rawText,
    required String processedHtml,
    required List<PluginHighlight> highlights,
    String? revealedHighlightId,
  }) {
    if (highlights.isEmpty) {
      return (html: processedHtml, ranges: const []);
    }
    final map = _sourceMapService.cachedFromProcessedHtml(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      processedHtml: processedHtml,
    );
    final intervals = _resolveIntervals(map, highlights);
    if (intervals.isEmpty) {
      return (html: processedHtml, ranges: const []);
    }

    return (
      html: _applyIntervals(
        processedHtml,
        intervals,
        revealedHighlightId: revealedHighlightId,
      ),
      ranges: intervals,
    );
  }

  String _applyIntervals(
    String processedHtml,
    List<PluginHighlightRenderedRange> intervals, {
    String? revealedHighlightId,
  }) {
    final fragment = html_parser.parseFragment(processedHtml);
    var renderedCursor = 0;
    final textNodes = fragment.nodes
        .expand(_descendantsAndSelf)
        .whereType<dom.Text>()
        .toList();
    for (final textNode in textNodes) {
      final graphemes = textNode.data.characters.toList(growable: false);
      final nodeStart = renderedCursor;
      final nodeEnd = nodeStart + graphemes.length;
      renderedCursor = nodeEnd;
      final localIntervals = intervals
          .where((range) => range.start < nodeEnd && range.end > nodeStart)
          .map(
            (range) => PluginHighlightRenderedRange(
              start: (range.start - nodeStart)
                  .clamp(0, graphemes.length)
                  .toInt(),
              end: (range.end - nodeStart).clamp(0, graphemes.length).toInt(),
              highlight: range.highlight,
            ),
          )
          .where((range) => range.start < range.end)
          .toList();
      if (localIntervals.isNotEmpty) {
        _replaceTextNode(
          textNode,
          graphemes,
          localIntervals,
          revealedHighlightId: revealedHighlightId,
        );
      }
    }
    return fragment.outerHtml;
  }

  List<PluginHighlightRenderedRange> resolveRenderedRanges({
    required String bookId,
    required int sectionIndex,
    required String rawText,
    required String processedHtml,
    required List<PluginHighlight> highlights,
  }) {
    if (highlights.isEmpty) return const [];
    final map = _sourceMapService.cachedFromProcessedHtml(
      bookId: bookId,
      sectionIndex: sectionIndex,
      rawText: rawText,
      processedHtml: processedHtml,
    );
    return _resolveIntervals(map, highlights)
        .map(
          (range) => PluginHighlightRenderedRange(
            start: range.start,
            end: range.end,
            highlight: range.highlight,
          ),
        )
        .toList(growable: false);
  }

  List<PluginHighlightRenderedRange> _resolveIntervals(
    PluginTextSourceMap map,
    List<PluginHighlight> highlights,
  ) {
    final ranges = <PluginHighlightRenderedRange>[];
    final sourceGraphemes = map.sourceText.characters.toList(growable: false);
    for (final highlight in highlights) {
      if (highlight.status != 'active' ||
          highlight.range.layer != 'source' ||
          highlight.range.exactText.isEmpty) {
        continue;
      }
      final sourceStart = highlight.range.start.grapheme;
      final sourceEnd = highlight.range.end.grapheme;
      if (sourceStart < 0 ||
          sourceEnd > sourceGraphemes.length ||
          sourceGraphemes.sublist(sourceStart, sourceEnd).join() !=
              highlight.range.exactText) {
        continue;
      }
      final start = _sourceMapService.sourceBoundaryToRendered(
        map,
        sourceStart,
      );
      final end = _sourceMapService.sourceBoundaryToRendered(
        map,
        sourceEnd,
      );
      if (start < end) {
        ranges.add(
          PluginHighlightRenderedRange(
            start: start,
            end: end,
            highlight: highlight,
          ),
        );
      }
    }
    return ranges;
  }

  void _replaceTextNode(
    dom.Text textNode,
    List<String> graphemes,
    List<PluginHighlightRenderedRange> intervals, {
    String? revealedHighlightId,
  }) {
    final boundaries = <int>{0, graphemes.length};
    for (final interval in intervals) {
      boundaries.add(interval.start);
      boundaries.add(interval.end);
    }
    final sorted = boundaries.toList()..sort();
    final replacements = <dom.Node>[];
    for (var index = 0; index < sorted.length - 1; index++) {
      final start = sorted[index];
      final end = sorted[index + 1];
      if (start == end) continue;
      final text = graphemes.sublist(start, end).join();
      final active =
          intervals
              .where((range) => range.start <= start && range.end >= end)
              .toList()
            // tie-break לפי createdAt — List.sort אינו יציב, ובלעדיו המנצח בין
            // הדגשות חופפות שוות-עדיפות מתחלף אקראית בין rebuild-ים.
            ..sort((a, b) {
              final priority = b.highlight.style.priority.compareTo(
                a.highlight.style.priority,
              );
              return priority != 0
                  ? priority
                  : a.highlight.createdAt.compareTo(b.highlight.createdAt);
            });
      if (active.isEmpty) {
        replacements.add(dom.Text(text));
        continue;
      }
      final winner = active.first.highlight;
      final span = dom.Element.tag('span')
        ..classes.add('otzaria-plugin-highlight')
        ..attributes['data-highlight-id'] = winner.highlightId
        ..attributes['style'] = _css(
          winner.style,
          revealed: winner.highlightId == revealedHighlightId,
        )
        ..append(dom.Text(text));
      replacements.add(span);
    }
    final fragment = dom.DocumentFragment();
    for (final replacement in replacements) {
      fragment.append(replacement);
    }
    textNode.replaceWith(fragment);
  }

  String _css(PluginHighlightStyle style, {bool revealed = false}) {
    final solid = _rgba(style.backgroundColor, 1);
    final declarations = <String>[
      'unicode-bidi: normal',
      'direction: inherit',
      // Background fills are painted by the overlay so rounded corners never
      // turn RTL text into separately laid-out widgets.
      if (style.markerMode == 'line-marker') 'color: $solid',
      // Four-sided boxes are painted by PluginHighlightFrameOverlay. Box CSS
      // can turn inline RTL text into independently positioned widgets.
      if (style.foregroundColor != null)
        'color: ${_rgba(style.foregroundColor!, 1)}',
      if (style.underline || style.markerMode == 'underline')
        'text-decoration: underline',
      if (style.underline || style.markerMode == 'underline')
        'text-decoration-thickness: 2px',
      if (style.underline || style.markerMode == 'underline')
        'text-decoration-color: ${_rgba(style.underlineColor ?? style.backgroundColor, 1)}',
      if (revealed) ...[
        'background-color: $solid',
        'text-decoration-line: underline overline',
        'text-decoration-color: $solid',
        'text-decoration-thickness: 3px',
      ],
    ];
    return declarations.join('; ');
  }

  String _rgba(String hex, double opacity) {
    final value = hex.substring(1);
    final red = int.parse(value.substring(0, 2), radix: 16);
    final green = int.parse(value.substring(2, 4), radix: 16);
    final blue = int.parse(value.substring(4, 6), radix: 16);
    final embeddedAlpha = value.length == 8
        ? int.parse(value.substring(6, 8), radix: 16) / 255
        : 1.0;
    final alpha = (embeddedAlpha * opacity).clamp(0, 1);
    return 'rgba($red, $green, $blue, ${alpha.toStringAsFixed(3)})';
  }
}

class PluginHighlightRenderedRange {
  final int start;
  final int end;
  final PluginHighlight highlight;

  const PluginHighlightRenderedRange({
    required this.start,
    required this.end,
    required this.highlight,
  });
}

Iterable<dom.Node> _descendantsAndSelf(dom.Node node) sync* {
  yield node;
  for (final child in node.nodes) {
    yield* _descendantsAndSelf(child);
  }
}
