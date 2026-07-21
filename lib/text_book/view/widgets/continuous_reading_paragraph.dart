import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/theme/app_fonts.dart';

/// תגובה ללחיצה על קישור inline בתוך פסקה של מצב טקסט רציף.
/// יוחזר `true` אם הטיפול בקישור הסתיים והעיבוד הרגיל (לחיצה על שורה) לא נדרש.
typedef ContinuousReadingUrlTap = Future<bool> Function(String url);

/// ריחוף מעל עוגן-מילה (`otzaria://anchor`) — מקבל את מיקום הסמן הגלובלי.
typedef ContinuousReadingAnchorHover =
    void Function(String url, Offset globalPosition);

/// יציאת הסמן מעוגן-מילה.
typedef ContinuousReadingAnchorExit = void Function(String url);

class ContinuousReadingParagraphLine {
  final int lineIndex;
  final String text;
  final String? htmlText;
  final TextStyle style;

  const ContinuousReadingParagraphLine({
    required this.lineIndex,
    required this.text,
    required this.style,
    this.htmlText,
  });
}

List<InlineSpan> buildInlineHtmlSpans(
  String htmlText,
  TextStyle baseStyle, {
  ContinuousReadingUrlTap? onTapUrl,
  ContinuousReadingAnchorHover? onAnchorHover,
  ContinuousReadingAnchorExit? onAnchorExit,
  TextStyle? linkStyle,
  List<TapGestureRecognizer>? recognizerSink,
}) {
  final fragment = html_parser.parseFragment(htmlText);
  return _nodesToSpans(
    fragment.nodes,
    baseStyle,
    onTapUrl: onTapUrl,
    onAnchorHover: onAnchorHover,
    onAnchorExit: onAnchorExit,
    linkStyle: linkStyle,
    recognizerSink: recognizerSink,
  );
}

class ContinuousReadingParagraph extends StatefulWidget {
  final List<ContinuousReadingParagraphLine> lines;
  final TextStyle baseStyle;
  final ValueChanged<int> onLineTap;
  final ValueChanged<int>? onLineSecondaryTap;
  final ContinuousReadingUrlTap? onTapUrl;
  final ContinuousReadingAnchorHover? onAnchorHover;
  final ContinuousReadingAnchorExit? onAnchorExit;
  final TextStyle? linkStyle;
  final TextAlign textAlign;

  const ContinuousReadingParagraph({
    super.key,
    required this.lines,
    required this.baseStyle,
    required this.onLineTap,
    this.onLineSecondaryTap,
    this.onTapUrl,
    this.onAnchorHover,
    this.onAnchorExit,
    this.linkStyle,
    this.textAlign = TextAlign.justify,
  });

  @override
  State<ContinuousReadingParagraph> createState() =>
      _ContinuousReadingParagraphState();
}

class _ContinuousReadingParagraphState
    extends State<ContinuousReadingParagraph> {
  // recognizer-ים של לחיצה על שורה כולה (כדי לבחור/לבטל בחירה של סעיף)
  final List<TapGestureRecognizer> _lineRecognizers = [];
  // recognizer-ים של קישורי <a> inline שמתוך הספאנים המפורסרים
  final List<TapGestureRecognizer> _linkRecognizers = [];

  @override
  void initState() {
    super.initState();
    _rebuildLineRecognizers();
  }

  @override
  void didUpdateWidget(covariant ContinuousReadingParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameLineOrder(oldWidget.lines, widget.lines)) {
      _rebuildLineRecognizers();
    }
  }

  @override
  void dispose() {
    _disposeLineRecognizers();
    _disposeLinkRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // הספאנים נבנים מחדש בכל build כי הסגנון/הבחירה עשויים להשתנות.
    // כדי למנוע דליפת recognizer-ים של קישורים, אנו מנקים את הרשימה כאן.
    _disposeLinkRecognizers();

    final spans = <InlineSpan>[];
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final hasNext = i < widget.lines.length - 1;
      final lineSpans = _buildLineSpans(line);
      for (final span in lineSpans) {
        spans.add(_withRecognizer(span, _lineRecognizers[i], line.style));
      }
      if (hasNext) {
        spans.add(TextSpan(text: ' ', style: line.style));
      }
    }

    final textSpan = TextSpan(style: widget.baseStyle, children: spans);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Text.rich(
          textSpan,
          textAlign: _effectiveTextAlign(
            textSpan: textSpan,
            constraints: constraints,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        );
      },
    );
  }

  List<InlineSpan> _buildLineSpans(ContinuousReadingParagraphLine line) {
    final htmlText = line.htmlText;
    if (htmlText == null) {
      return [TextSpan(text: line.text, style: line.style)];
    }

    return buildInlineHtmlSpans(
      htmlText,
      line.style,
      onTapUrl: widget.onTapUrl,
      onAnchorHover: widget.onAnchorHover,
      onAnchorExit: widget.onAnchorExit,
      linkStyle: widget.linkStyle,
      recognizerSink: _linkRecognizers,
    );
  }

  TextAlign _effectiveTextAlign({
    required InlineSpan textSpan,
    required BoxConstraints constraints,
    required TextScaler textScaler,
  }) {
    if (widget.textAlign != TextAlign.justify || !constraints.hasBoundedWidth) {
      return widget.textAlign;
    }

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.start,
      textDirection: TextDirection.rtl,
      textScaler: textScaler,
    )..layout(maxWidth: constraints.maxWidth);

    final visualLineCount = textPainter.computeLineMetrics().length;
    textPainter.dispose();

    return visualLineCount <= 1 ? TextAlign.start : widget.textAlign;
  }

  void _rebuildLineRecognizers() {
    _disposeLineRecognizers();
    for (var i = 0; i < widget.lines.length; i++) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onLineTap(widget.lines[i].lineIndex);
      if (widget.onLineSecondaryTap != null) {
        recognizer.onSecondaryTap = () =>
            widget.onLineSecondaryTap!(widget.lines[i].lineIndex);
      }
      _lineRecognizers.add(recognizer);
    }
  }

  void _disposeLineRecognizers() {
    for (final recognizer in _lineRecognizers) {
      recognizer.dispose();
    }
    _lineRecognizers.clear();
  }

  void _disposeLinkRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
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
  TextStyle style, {
  ContinuousReadingUrlTap? onTapUrl,
  ContinuousReadingAnchorHover? onAnchorHover,
  ContinuousReadingAnchorExit? onAnchorExit,
  TextStyle? linkStyle,
  List<TapGestureRecognizer>? recognizerSink,
}) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    spans.addAll(
      _nodeToSpans(
        node,
        style,
        onTapUrl: onTapUrl,
        onAnchorHover: onAnchorHover,
        onAnchorExit: onAnchorExit,
        linkStyle: linkStyle,
        recognizerSink: recognizerSink,
      ),
    );
  }
  return spans;
}

List<InlineSpan> _nodeToSpans(
  dom.Node node,
  TextStyle style, {
  ContinuousReadingUrlTap? onTapUrl,
  ContinuousReadingAnchorHover? onAnchorHover,
  ContinuousReadingAnchorExit? onAnchorExit,
  TextStyle? linkStyle,
  List<TapGestureRecognizer>? recognizerSink,
}) {
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

  // טיפול בקישורים inline: <a href="...">…</a>
  if (node.localName == 'a' && onTapUrl != null) {
    final href = node.attributes['href'];
    if (href != null && href.isNotEmpty) {
      final childStyle = _styleForElement(node, style);
      // עוגן-מילה לחיץ שומר על מראה הסמן (צבע טקסט יורש, בלי קו תחתון), ובמצב
      // active מודגש בצבע primary; טווח-ציטוט — קו תחתון בצבע הטקסט (לא
      // primary); שאר הקישורים — קו תחתון + צבע theme.
      final effectiveLinkStyle = node.classes.contains('link-anchor')
          ? (node.classes.contains('link-anchor-active')
                ? childStyle
                      .merge(linkStyle)
                      .copyWith(
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.bold,
                        fontVariations: AppFonts.boldFontVariations(
                          childStyle.fontFamily,
                        ),
                      )
                : childStyle)
          : node.classes.contains('link-anchor-range')
          ? childStyle.copyWith(decoration: TextDecoration.underline)
          : linkStyle == null
          ? childStyle.copyWith(decoration: TextDecoration.underline)
          : childStyle.merge(linkStyle);
      final children = _nodesToSpans(
        node.nodes,
        effectiveLinkStyle,
        onTapUrl: onTapUrl,
        onAnchorHover: onAnchorHover,
        onAnchorExit: onAnchorExit,
        linkStyle: linkStyle,
        recognizerSink: recognizerSink,
      );
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          onTapUrl(href);
        };
      recognizerSink?.add(recognizer);
      // קישורי עוגן והערה מקבלים תצוגה מקדימה בריחוף.
      final isHoverableAnchor =
          _isPreviewUrl(href) &&
          (onAnchorHover != null || onAnchorExit != null);
      return [
        TextSpan(
          style: effectiveLinkStyle,
          recognizer: recognizer,
          mouseCursor: isHoverableAnchor ? SystemMouseCursors.click : null,
          onEnter: isHoverableAnchor && onAnchorHover != null
              ? (event) => onAnchorHover(href, event.position)
              : null,
          onExit: isHoverableAnchor && onAnchorExit != null
              ? (_) => onAnchorExit(href)
              : null,
          children: children,
        ),
      ];
    }
  }

  final childStyle = _styleForElement(node, style);
  return _nodesToSpans(
    node.nodes,
    childStyle,
    onTapUrl: onTapUrl,
    onAnchorHover: onAnchorHover,
    onAnchorExit: onAnchorExit,
    linkStyle: linkStyle,
    recognizerSink: recognizerSink,
  );
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
      element.classes.contains('footnote-marker-number') ||
      element.classes.contains('book-note-marker') ||
      element.classes.contains('link-anchor')) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * 0.75,
      fontStyle: FontStyle.italic,
    );
  }
  if (localName == 'i' ||
      localName == 'em' ||
      _hasFontStyle(element, 'italic')) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (localName == 'b' || localName == 'strong') {
    style = style.copyWith(
      fontWeight: FontWeight.bold,
      fontVariations: AppFonts.boldFontVariations(style.fontFamily),
    );
  }

  // הדגשת תוצאות חיפוש מגיעות כ-`<span style="color: red">` או
  // `<span style="color: blue; background-color: yellow">` (התוצאה הנוכחית).
  // המפרסר חייב לכבד את ה-styles האלה אחרת תוצאות חיפוש לא יסומנו במצב רציף.
  final inlineColor = _inlineColor(element);
  if (inlineColor != null) {
    style = style.copyWith(color: inlineColor);
  }
  final inlineBackground = _inlineBackgroundColor(element);
  if (inlineBackground != null) {
    style = style.copyWith(backgroundColor: inlineBackground);
  }

  return style;
}

bool _isPreviewUrl(String url) =>
    url.startsWith('otzaria://anchor') ||
    url.startsWith('otzaria://book-note') ||
    url.startsWith('otzaria://note');

Color? _inlineColor(dom.Element element) {
  final inlineStyle = element.attributes['style'] ?? '';
  // לוכד `color: <value>` אך לא `background-color:` (שלפניו `-`).
  final match = RegExp(
    r'(?:^|[\s;])color\s*:\s*([^;]+)',
    caseSensitive: false,
  ).firstMatch(inlineStyle);
  if (match == null) return null;
  return _parseCssColor(match.group(1)!.trim());
}

Color? _inlineBackgroundColor(dom.Element element) {
  final inlineStyle = element.attributes['style'] ?? '';
  final match = RegExp(
    r'background-color\s*:\s*([^;]+)',
    caseSensitive: false,
  ).firstMatch(inlineStyle);
  if (match == null) return null;
  return _parseCssColor(match.group(1)!.trim());
}

Color? _parseCssColor(String value) {
  final v = value.toLowerCase().trim();
  // צבעים פשוטים שהחיפוש משתמש בהם.
  switch (v) {
    case 'red':
      return const Color(0xFFFF0000);
    case 'blue':
      return const Color(0xFF0000FF);
    case 'yellow':
      return const Color(0xFFFFFF00);
    case 'green':
      return const Color(0xFF008000);
    case 'black':
      return const Color(0xFF000000);
    case 'white':
      return const Color(0xFFFFFFFF);
  }
  // #rgb / #rrggbb
  if (v.startsWith('#')) {
    var hex = v.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(0xFF000000 | n);
    }
    if (hex.length == 8) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(n);
    }
  }
  return null;
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
  return RegExp(
    'font-style\\s*:\\s*$value',
    caseSensitive: false,
  ).hasMatch(inlineStyle);
}

InlineSpan _withRecognizer(
  InlineSpan span,
  TapGestureRecognizer recognizer,
  TextStyle fallbackStyle,
) {
  if (span is! TextSpan) {
    return span;
  }

  // אם הספאן עצמו כבר נושא recognizer (למשל קישור inline), משאירים את
  // כל תת-העץ כמו שהוא: ה-recognizer של ההורה יורש ממילא לכל הצאצאים.
  // ירידה רקורסיבית כאן הייתה דורסת את הקישור בלחיצת שורה.
  if (span.recognizer != null) {
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
