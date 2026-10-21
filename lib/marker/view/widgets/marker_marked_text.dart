import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/services/marker_text_format.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';

/// הטקסט המסומן ברשימות, בעיצוב שהיה לו בספר (מודגש, נטוי, כותרת) כשהוא
/// ידוע. [maxChars] מקצר את הטקסט כמו [markerQuote].
class MarkerMarkedText extends StatelessWidget {
  const MarkerMarkedText(
    this.mark, {
    super.key,
    this.style,
    this.maxLines,
    this.maxChars,
  });

  final MarkerHighlight mark;
  final TextStyle? style;
  final int? maxLines;
  final int? maxChars;

  @override
  Widget build(BuildContext context) {
    final plain = mark.text.isEmpty ? 'סימון' : mark.text;
    final html = markerFormattedText(mark.segments.map((s) => s.html));
    if (html == null) {
      return Text(
        maxChars == null ? plain : markerQuote(plain, maxChars!),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final base = DefaultTextStyle.of(context).style.merge(style);
    return Text.rich(
      TextSpan(children: markerTextSpans(html, base, maxChars: maxChars)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// [html] של [markerSegmentHtml] כ-spans, יחסית ל-[base]. [maxChars] סופר
/// graphemes, כדי לא לחתוך אות מהניקוד שלה.
@visibleForTesting
List<InlineSpan> markerTextSpans(
  String html,
  TextStyle base, {
  int? maxChars,
}) {
  final pieces = <({String text, TextStyle style})>[];
  void walk(dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      pieces.add((text: node.data, style: style));
      return;
    }
    final size = style.fontSize ?? base.fontSize ?? 14;
    final inner = switch (node is dom.Element ? node.localName : null) {
      'b' => style.copyWith(fontWeight: FontWeight.bold),
      'i' => style.copyWith(fontStyle: FontStyle.italic),
      'u' => style.copyWith(decoration: TextDecoration.underline),
      'big' => style.copyWith(fontSize: size * 1.15),
      'small' => style.copyWith(fontSize: size * 0.85),
      _ => style,
    };
    for (final child in node.nodes) {
      walk(child, inner);
    }
  }

  walk(html_parser.parseFragment(html), base);
  final spans = <InlineSpan>[];
  var left = maxChars;
  for (final piece in pieces) {
    if (left == null) {
      spans.add(TextSpan(text: piece.text, style: piece.style));
      continue;
    }
    final chars = piece.text.characters;
    if (chars.length <= left) {
      spans.add(TextSpan(text: piece.text, style: piece.style));
      left -= chars.length;
      continue;
    }
    spans.add(TextSpan(text: '${chars.take(left)}…', style: piece.style));
    break;
  }
  return spans;
}
