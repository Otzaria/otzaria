import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/text_book/utils/link_anchor_variants.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

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
  final List<PluginHighlightRenderedRange> frameRanges;

  const ContinuousReadingParagraphLine({
    required this.lineIndex,
    required this.text,
    required this.style,
    this.htmlText,
    this.frameRanges = const [],
  });
}

/// תקרת המטמון — גדולה מפסקה ממוזגת טיפוסית, וחסומה כדי שספר שלם לא ייצבר.
const int _maxCachedFragments = 1024;

/// מטמון DOM מפורק לפי מחרוזת ה-HTML. הפירוק תלוי אך ורק במחרוזת, והמעבר
/// ב-[_nodesToSpans] הוא קריאה בלבד — ולכן בטוח לחלוק את אותו DOM בין builds.
final Map<String, dom.DocumentFragment> _fragmentCache =
    <String, dom.DocumentFragment>{};

int _fragmentParseCount = 0;

/// מספר הפירוקים שבוצעו בפועל — לאימות שהמטמון פוגע.
@visibleForTesting
int get inlineHtmlParseCount => _fragmentParseCount;

@visibleForTesting
void resetInlineHtmlCacheForTesting() {
  _fragmentCache.clear();
  _fragmentParseCount = 0;
}

/// פירוק HTML עם מטמון LRU. `Map` ב-Dart שומר סדר הכנסה, ולכן הסרה+הכנסה
/// מחדש מקדמת ערך לסוף, ו-`keys.first` הוא הישן ביותר.
dom.DocumentFragment _parseFragmentCached(String htmlText) {
  final cached = _fragmentCache.remove(htmlText);
  if (cached != null) {
    _fragmentCache[htmlText] = cached;
    return cached;
  }

  final fragment = html_parser.parseFragment(htmlText);
  _fragmentParseCount++;
  if (_fragmentCache.length >= _maxCachedFragments) {
    _fragmentCache.remove(_fragmentCache.keys.first);
  }
  _fragmentCache[htmlText] = fragment;
  return fragment;
}

List<InlineSpan> buildInlineHtmlSpans(
  String htmlText,
  TextStyle baseStyle, {
  ContinuousReadingUrlTap? onTapUrl,
  ContinuousReadingAnchorHover? onAnchorHover,
  ContinuousReadingAnchorExit? onAnchorExit,
  TextStyle? linkStyle,
  Color? anchorActiveBackground,
  List<TapGestureRecognizer>? recognizerSink,
}) {
  final fragment = _parseFragmentCached(htmlText);
  return _nodesToSpans(
    fragment.nodes,
    baseStyle,
    onTapUrl: onTapUrl,
    onAnchorHover: onAnchorHover,
    onAnchorExit: onAnchorExit,
    linkStyle: linkStyle,
    anchorActiveBackground: anchorActiveBackground,
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

  /// רקע סמן-האות שחלונית התצוגה שלו פתוחה (בד"כ primaryContainer).
  final Color? anchorActiveBackground;
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
    this.anchorActiveBackground,
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
    final frameRanges = <PluginHighlightRenderedRange>[];
    var graphemeOffset = 0;
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final hasNext = i < widget.lines.length - 1;
      final lineSpans = _buildLineSpans(line);
      for (final span in lineSpans) {
        spans.add(_withRecognizer(span, _lineRecognizers[i], line.style));
      }
      for (final range in line.frameRanges) {
        final mode = range.highlight.style.markerMode;
        if (mode == 'text-background' || mode == 'box') {
          frameRanges.add(
            PluginHighlightRenderedRange(
              start: range.start + graphemeOffset,
              end: range.end + graphemeOffset,
              highlight: range.highlight,
            ),
          );
        }
      }
      graphemeOffset += line.text.characters.length;
      if (hasNext) {
        spans.add(TextSpan(text: ' ', style: line.style));
        graphemeOffset++;
      }
    }

    final textSpan = TextSpan(style: widget.baseStyle, children: spans);
    // justify אינו מותח שורה אחרונה, ולכן גם לא פסקה בת שורה חזותית אחת.
    // מדידה מוקדמת של מספר השורות = layout שני על כל הפסקה, ומייקרת גלילה.
    final text = Text.rich(textSpan, textAlign: widget.textAlign);
    if (frameRanges.isEmpty) return text;
    return PluginHighlightFrameOverlay(ranges: frameRanges, child: text);
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
      anchorActiveBackground: widget.anchorActiveBackground,
      recognizerSink: _linkRecognizers,
    );
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
  Color? anchorActiveBackground,
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
        anchorActiveBackground: anchorActiveBackground,
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
  Color? anchorActiveBackground,
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
      // עוגן-מילה וטווח-ציטוט — צבע ה-primary של הנושא בלי קו תחתון; במצב
      // active מודגש עם רקע; שאר הקישורים — קו תחתון + צבע theme.
      final effectiveLinkStyle = node.classes.contains('link-anchor')
          // הווריאנט שב-childStyle נשמר גם ב-active (מיזוג linkStyle היה גורר
          // קו תחתון של קישור ומוחק את קו-התחתון שהוא סימנו של וריאנט 5).
          ? (node.classes.contains('link-anchor-active')
                ? childStyle.copyWith(
                    color: linkStyle?.color,
                    fontWeight: FontWeight.bold,
                    fontVariations: AppFonts.boldFontVariations(
                      childStyle.fontFamily,
                    ),
                    backgroundColor: anchorActiveBackground,
                  )
                : childStyle.copyWith(color: linkStyle?.color))
          : node.classes.contains('numbered-note-marker')
          ? childStyle.copyWith(color: linkStyle?.color)
          : node.classes.contains('link-anchor-range')
          ? childStyle.copyWith(
              decoration: TextDecoration.none,
              color: linkStyle?.color,
            )
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
        anchorActiveBackground: anchorActiveBackground,
        recognizerSink: recognizerSink,
      );
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          onTapUrl(href);
        };
      recognizerSink?.add(recognizer);
      // קישורי עוגן והערה מקבלים תצוגה מקדימה בריחוף.
      final isHoverableAnchor =
          isPreviewHoverableUrl(href) &&
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
    anchorActiveBackground: anchorActiveBackground,
    recognizerSink: recognizerSink,
  );
}

TextStyle _styleForElement(dom.Element element, TextStyle parentStyle) {
  var style = parentStyle;
  final localName = element.localName;

  if (localName == 'small') {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * kHtmlSmallerFontScale,
    );
  }
  if (localName == 'big') {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * kHtmlLargerFontScale,
    );
  }
  final inlineFontSize = _inlineFontSize(element, style.fontSize ?? 18);
  if (inlineFontSize != null) {
    style = style.copyWith(fontSize: inlineFontSize);
  }
  // sup חשוף (למשל מייבוא Word) מוקטן כמו ב-fwfh, בלי נטייה; סמני ההערות
  // מוקטנים ונוטים לפי ה-CSS שהוגדר להם ב-SmartTextWidget.
  if (localName == 'sup') {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * kHtmlSmallerFontScale,
    );
  }
  if (element.classes.contains('footnote-marker-number') ||
      element.classes.contains('book-note-marker')) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * 0.75,
      fontStyle: FontStyle.italic,
    );
  }
  // סמן-אות של מפרש: מוקטן, והטיפוגרפיה נקבעת אך ורק בווריאנט שהוקצה למפרש.
  // נטייה כפויה כאן הייתה מוחקת את ההבחנה בין המפרשים.
  if (element.classes.contains('link-anchor')) {
    style = applyLinkAnchorVariant(
      linkAnchorVariantFromClasses(element.classes),
      style.copyWith(
        fontSize: (style.fontSize ?? 18) * kLinkAnchorMarkerScale,
      ),
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
  if (_hasTextDecoration(element, 'underline')) {
    style = style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: _inlineDecorationColor(element),
      decorationThickness: _inlineDecorationThickness(element),
    );
  }

  return style;
}

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

Color? _inlineDecorationColor(dom.Element element) {
  final inlineStyle = element.attributes['style'] ?? '';
  final match = RegExp(
    r'text-decoration-color\s*:\s*([^;]+)',
    caseSensitive: false,
  ).firstMatch(inlineStyle);
  if (match == null) return null;
  return _parseCssColor(match.group(1)!.trim());
}

double? _inlineDecorationThickness(dom.Element element) {
  final inlineStyle = element.attributes['style'] ?? '';
  final match = RegExp(
    r'text-decoration-thickness\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*px',
    caseSensitive: false,
  ).firstMatch(inlineStyle);
  return match == null ? null : double.tryParse(match.group(1)!);
}

Color? _parseCssColor(String value) {
  final v = value.toLowerCase().trim();
  final rgba = RegExp(
    r'^rgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(0(?:\.\d+)?|\.\d+|1(?:\.0+)?)\s*\)$',
  ).firstMatch(v);
  if (rgba != null) {
    final red = int.parse(rgba.group(1)!).clamp(0, 255).toInt();
    final green = int.parse(rgba.group(2)!).clamp(0, 255).toInt();
    final blue = int.parse(rgba.group(3)!).clamp(0, 255).toInt();
    final alpha = (double.parse(rgba.group(4)!) * 255)
        .round()
        .clamp(0, 255)
        .toInt();
    return Color.fromARGB(alpha, red, green, blue);
  }
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
      final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
      final alpha = int.tryParse(hex.substring(6, 8), radix: 16);
      if (rgb != null && alpha != null) return Color((alpha << 24) | rgb);
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

bool _hasTextDecoration(dom.Element element, String value) {
  final inlineStyle = element.attributes['style'] ?? '';
  return RegExp(
    'text-decoration\\s*:\\s*[^;]*\\b$value\\b',
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
