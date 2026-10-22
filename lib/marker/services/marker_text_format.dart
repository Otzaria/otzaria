import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/marker/services/marker_paint.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';

/// העיצוב של הטקסט המסומן כפי שהוצג בספר, ב-HTML מצומצם: `b`, `i`, `u`,
/// `big` ו-`small` בלבד (כותרת היא מודגש וגדול). הרשימות מציגות רק את תחילת
/// הסימון, ולכן נשמרים עד [maxChars] graphemes.
///
/// [rawText] הוא שורת המקור ו-[processedHtml] התצוגה שלה, כמו בציור הסימון.
/// null כשהעוגן אינו תואם לשורה.
String? markerSegmentHtml({
  required String bookId,
  required int sectionIndex,
  required String rawText,
  required String processedHtml,
  required PluginTextRangeAnchor range,
  int maxChars = 400,
}) {
  final epoch = DateTime.utc(2000);
  final rendered = const PluginHighlightRenderer().renderWithRanges(
    bookId: bookId,
    sectionIndex: sectionIndex,
    rawText: rawText,
    processedHtml: processedHtml,
    highlights: [
      PluginHighlight(
        highlightId: 'marker-format',
        ownerPluginId: kMarkerHighlightOwner,
        bookId: bookId,
        sectionIndex: sectionIndex,
        range: range,
        style: const PluginHighlightStyle(backgroundColor: '#000000'),
        createdAt: epoch,
        updatedAt: epoch,
      ),
    ],
  );
  if (rendered.ranges.isEmpty) return null;

  final pieces = <({String text, _Style style})>[];
  var length = 0;
  void walk(dom.Node node, _Style style, bool marked) {
    if (length >= maxChars) return;
    if (node is dom.Text) {
      if (!marked) return;
      final cut = node.data
          .replaceAll(RegExp(r'\s+'), ' ')
          .characters
          .take(maxChars - length);
      length += cut.length;
      if (pieces.isNotEmpty && pieces.last.style == style) {
        pieces.last = (text: pieces.last.text + cut.string, style: style);
      } else {
        pieces.add((text: cut.string, style: style));
      }
      return;
    }
    if (node is dom.Element) {
      if (node.localName == 'br') {
        if (marked) walk(dom.Text(' '), style, true);
        return;
      }
      final inner = style.inside(node.localName ?? '');
      final insideMark =
          marked || node.classes.contains('otzaria-plugin-highlight');
      for (final child in node.nodes) {
        walk(child, inner, insideMark);
      }
      return;
    }
    for (final child in node.nodes) {
      walk(child, style, marked);
    }
  }

  walk(html_parser.parseFragment(rendered.html), const _Style(), false);
  final html = StringBuffer();
  for (final piece in pieces) {
    html.write(piece.style.wrap(_escape(piece.text)));
  }
  return html.toString().trim();
}

/// הטקסט המסומן בעיצובו, כשהוא ידוע לכל המקטעים ויש בו עיצוב; אחרת null,
/// והטקסט מוצג כפי שהוא.
String? markerFormattedText(Iterable<String?> segmentHtml) {
  final parts = segmentHtml.toList();
  if (parts.isEmpty || parts.any((html) => html == null)) return null;
  if (!parts.any((html) => html!.contains('<'))) return null;
  return parts.join(' ');
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

class _Style {
  const _Style({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.size = 0,
  });

  final bool bold;
  final bool italic;
  final bool underline;

  /// 1 גדול, ‎-1 קטן.
  final int size;

  _Style inside(String tag) => switch (tag) {
    'b' || 'strong' => _with(bold: true),
    'i' || 'em' => _with(italic: true),
    'u' => _with(underline: true),
    'big' => _with(size: 1),
    'small' => _with(size: -1),
    'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => _with(bold: true, size: 1),
    _ => this,
  };

  _Style _with({bool? bold, bool? italic, bool? underline, int? size}) =>
      _Style(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        size: size ?? this.size,
      );

  String wrap(String text) {
    var html = text;
    if (size > 0) html = '<big>$html</big>';
    if (size < 0) html = '<small>$html</small>';
    if (underline) html = '<u>$html</u>';
    if (italic) html = '<i>$html</i>';
    if (bold) html = '<b>$html</b>';
    return html;
  }

  @override
  bool operator ==(Object other) =>
      other is _Style &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.size == size;

  @override
  int get hashCode => Object.hash(bold, italic, underline, size);
}
