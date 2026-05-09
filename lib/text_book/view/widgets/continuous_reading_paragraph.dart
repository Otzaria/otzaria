import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class ContinuousReadingParagraphLine {
  final int lineIndex;
  final String text;
  final List<InlineSpan>? inlineSpans;
  final TextStyle style;

  const ContinuousReadingParagraphLine({
    required this.lineIndex,
    required this.text,
    required this.style,
    this.inlineSpans,
  });
}

List<InlineSpan> buildInlineHtmlSpans(
  String htmlText,
  TextStyle baseStyle,
) {
  final fragment = html_parser.parseFragment(htmlText);
  return _nodesToSpans(fragment.nodes, baseStyle);
}

class ContinuousReadingParagraph extends StatefulWidget {
  final List<ContinuousReadingParagraphLine> lines;
  final TextStyle baseStyle;
  final ValueChanged<int> onLineTap;
  final TextDirection textDirection;
  final TextAlign textAlign;

  const ContinuousReadingParagraph({
    super.key,
    required this.lines,
    required this.baseStyle,
    required this.onLineTap,
    this.textDirection = TextDirection.rtl,
    this.textAlign = TextAlign.justify,
  });

  @override
  State<ContinuousReadingParagraph> createState() =>
      _ContinuousReadingParagraphState();
}

class _ContinuousReadingParagraphState
    extends State<ContinuousReadingParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildRecognizers();
  }

  @override
  void didUpdateWidget(covariant ContinuousReadingParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameLineOrder(oldWidget.lines, widget.lines)) {
      _rebuildRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final hasNext = i < widget.lines.length - 1;
      final lineSpans = line.inlineSpans ?? [TextSpan(text: line.text)];
      for (final span in lineSpans) {
        spans.add(_withRecognizer(span, _recognizers[i], line.style));
      }
      if (hasNext) {
        spans.add(TextSpan(text: ' ', style: line.style));
      }
    }

    return Text.rich(
      TextSpan(style: widget.baseStyle, children: spans),
      textDirection: widget.textDirection,
      textAlign: widget.textAlign,
    );
  }

  void _rebuildRecognizers() {
    _disposeRecognizers();
    for (var i = 0; i < widget.lines.length; i++) {
      _recognizers.add(
        TapGestureRecognizer()
          ..onTap = () => widget.onLineTap(widget.lines[i].lineIndex),
      );
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  bool _sameLineOrder(
    List<ContinuousReadingParagraphLine> oldLines,
    List<ContinuousReadingParagraphLine> newLines,
  ) {
    if (oldLines.length != newLines.length) {
      return false;
    }
    for (var i = 0; i < oldLines.length; i++) {
      if (oldLines[i].lineIndex != newLines[i].lineIndex) {
        return false;
      }
    }
    return true;
  }
}

List<InlineSpan> _nodesToSpans(
  List<dom.Node> nodes,
  TextStyle style,
) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(_nodeToSpans(node, style));
  }
  return spans;
}

List<InlineSpan> _nodeToSpans(
  dom.Node node,
  TextStyle style,
) {
  if (node is dom.Text) {
    if (node.text.isEmpty) return const [];
    return [TextSpan(text: node.text, style: style)];
  }

  if (node is! dom.Element) {
    return const [];
  }

  if (node.localName == 'br') {
    return [TextSpan(text: '\n', style: style)];
  }

  final childStyle = _styleForElement(node, style);
  return _nodesToSpans(node.nodes, childStyle);
}

TextStyle _styleForElement(dom.Element element, TextStyle parentStyle) {
  var style = parentStyle;
  final localName = element.localName;

  if (localName == 'small') {
    style = style.copyWith(fontSize: (style.fontSize ?? 18) * 0.8);
  }
  if (localName == 'big') {
    style = style.copyWith(fontSize: (style.fontSize ?? 18) * 1.2);
  }
  final inlineFontSize = _inlineFontSize(element, style.fontSize ?? 18);
  if (inlineFontSize != null) {
    style = style.copyWith(fontSize: inlineFontSize);
  }
  if (localName == 'sup' ||
      element.classes.contains('footnote-marker-number')) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * 0.75,
      fontStyle: FontStyle.italic,
    );
  }
  if (localName == 'i' ||
      localName == 'em' ||
      element.classes.contains('footnote') ||
      _hasFontStyle(element, 'italic')) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (localName == 'b' || localName == 'strong') {
    style = style.copyWith(fontWeight: FontWeight.bold);
  }

  return style;
}

double? _inlineFontSize(dom.Element element, double parentFontSize) {
  final inlineStyle = element.attributes['style'] ?? '';
  final match = RegExp(
    r'font-size\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*(em|rem|px|%)?',
    caseSensitive: false,
  ).firstMatch(inlineStyle);
  if (match == null) return null;

  final value = double.tryParse(match.group(1) ?? '');
  if (value == null) return null;

  final unit = (match.group(2) ?? 'px').toLowerCase();
  return switch (unit) {
    'em' => parentFontSize * value,
    'rem' => parentFontSize * value,
    '%' => parentFontSize * value / 100,
    _ => value,
  };
}

bool _hasFontStyle(dom.Element element, String value) {
  final inlineStyle = element.attributes['style'] ?? '';
  return RegExp('font-style\\s*:\\s*$value', caseSensitive: false)
      .hasMatch(inlineStyle);
}

InlineSpan _withRecognizer(
  InlineSpan span,
  TapGestureRecognizer recognizer,
  TextStyle fallbackStyle,
) {
  if (span is! TextSpan) {
    return span;
  }

  return TextSpan(
    text: span.text,
    children: span.children
        ?.map((child) => _withRecognizer(child, recognizer, fallbackStyle))
        .toList(),
    style: span.style ?? fallbackStyle,
    recognizer: recognizer,
  );
}
