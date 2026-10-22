import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/text_book/utils/mikra_structure.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/widgets/smart_text/exact_line_height.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

/// תגובה ללחיצה על קישור inline בתוך פסקה של מצב טקסט רציף.
typedef ContinuousReadingUrlTap = Future<bool> Function(String url);

/// ריחוף מעל עוגן-מילה (`otzaria://anchor`) — מקבל את מיקום הסמן הגלובלי.
typedef ContinuousReadingAnchorHover =
    void Function(String url, Offset globalPosition);

/// יציאת הסמן מעוגן-מילה.
typedef ContinuousReadingAnchorExit = void Function(String url);

class ContinuousReadingParagraphLine {
  final int lineIndex;

  /// הטקסט כשאין [htmlText].
  final String text;
  final String? htmlText;
  final TextStyle style;
  final List<PluginHighlightRenderedRange> frameRanges;

  /// רקע לטקסט השורה בלבד (הדגשה קבועה/זמנית), בגובה שורת התצוגה.
  final Color? background;
  final bool selected;

  /// כותרת נושא שנפתחת בשורה — מוצגת לפניה בתוך הזרימה.
  final String? heading;

  /// ציון פרק/פסוק לגליון הצדדי (ספרי מקרא).
  final MikraGutterLabel? gutter;

  /// פרשה ועלייה לגליון הצדדי (חומשי התורה).
  final MikraDivisionLabel? division;

  const ContinuousReadingParagraphLine({
    required this.lineIndex,
    this.text = '',
    required this.style,
    this.htmlText,
    this.frameRanges = const [],
    this.background,
    this.selected = false,
    this.heading,
    this.gutter,
    this.division,
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

/// [hideRaisedMarkers] — כברירת מחדל גליפי הסימונים המורמים נפלטים שקופים,
/// מתוך הנחה שהקורא עוטף את התוצאה ב-[RaisedMarkerOverlay.wrap] שמצייר אותם
/// מורמים. קורא שמציג את הספאנים בלי השכבה חייב להעביר false — אחרת
/// הסימונים ייעלמו מהמסך.
List<InlineSpan> buildInlineHtmlSpans(
  String htmlText,
  TextStyle baseStyle, {
  ContinuousReadingUrlTap? onTapUrl,
  ContinuousReadingAnchorHover? onAnchorHover,
  ContinuousReadingAnchorExit? onAnchorExit,
  TextStyle? linkStyle,
  Color? anchorActiveBackground,
  List<TapGestureRecognizer>? recognizerSink,
  void Function(String url)? onMiddleClickUrl,
  bool hideRaisedMarkers = true,
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
    onMiddleClickUrl: onMiddleClickUrl,
    hideRaisedMarkers: hideRaisedMarkers,
  );
}

class ContinuousReadingParagraph extends StatefulWidget {
  final List<ContinuousReadingParagraphLine> lines;
  final TextStyle baseStyle;
  final ContinuousReadingUrlTap? onTapUrl;

  /// לחיצת גלגל על קישור לספר אחר — פתיחה בכרטיסייה חדשה ברקע.
  final void Function(String url)? onMiddleClickUrl;
  final ContinuousReadingAnchorHover? onAnchorHover;
  final ContinuousReadingAnchorExit? onAnchorExit;
  final TextStyle? linkStyle;

  /// רקע סמן-האות שחלונית התצוגה שלו פתוחה (בד"כ primaryContainer).
  final Color? anchorActiveBackground;
  final TextAlign textAlign;

  /// צבע כותרות הנושא שמוצגות בתוך הזרימה לפני השורה שהן פותחות.
  final Color? headingColor;

  /// סגנון ציוני הגליון; null — אין גליון.
  final TextStyle? gutterStyle;
  final TextStyle? divisionStyle;

  const ContinuousReadingParagraph({
    super.key,
    required this.lines,
    required this.baseStyle,
    this.onTapUrl,
    this.onMiddleClickUrl,
    this.onAnchorHover,
    this.onAnchorExit,
    this.linkStyle,
    this.anchorActiveBackground,
    this.textAlign = TextAlign.justify,
    this.headingColor,
    this.gutterStyle,
    this.divisionStyle,
  });

  @override
  State<ContinuousReadingParagraph> createState() =>
      _ContinuousReadingParagraphState();
}

typedef _BuiltLine = ({List<InlineSpan> spans, int length});

class _ContinuousReadingParagraphState
    extends State<ContinuousReadingParagraph> {
  // recognizer-ים של קישורי <a> inline; נבנים מחדש בכל build.
  final List<TapGestureRecognizer> _linkRecognizers = [];

  // שורות בלי קישורים אינן תלויות ב-callbacks, ולכן נשמרות בין builds.
  Map<(String, TextStyle), _BuiltLine> _staticLines = {};

  @override
  void dispose() {
    _disposeLinkRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeLinkRecognizers();
    final staticLines = <(String, TextStyle), _BuiltLine>{};

    final spans = <InlineSpan>[];
    final lineData = <ReaderParagraphLineData>[];
    final frames = <PluginHighlightRenderedRange>[];
    final markerSources = <String>[];
    var offset = 0;
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      final heading = line.heading;
      if (heading != null && heading.isNotEmpty) {
        final text = '$heading ';
        spans.add(TextSpan(text: text, style: _headingStyle(line.style)));
        offset += text.length;
        markerSources.add(_htmlEscape.convert(text));
      }
      final built = _buildLine(line, staticLines);
      spans.addAll(built.spans);
      lineData.add(
        ReaderParagraphLineData(
          lineIndex: line.lineIndex,
          range: TextRange(start: offset, end: offset + built.length),
          background: line.background,
          selected: line.selected,
          gutter: line.gutter,
          division: line.division,
        ),
      );
      for (final range in line.frameRanges) {
        final mode = range.highlight.style.markerMode;
        if (mode != 'text-background' && mode != 'box') continue;
        frames.add(
          PluginHighlightRenderedRange(
            start: offset + _lineUtf16Offset(line, range.start, isStart: true),
            end: offset + _lineUtf16Offset(line, range.end, isStart: false),
            highlight: range.highlight,
          ),
        );
      }
      offset += built.length;
      markerSources.add(line.htmlText ?? line.text);
      if (i < widget.lines.length - 1) {
        spans.add(TextSpan(text: ' ', style: line.style));
        offset++;
        markerSources.add(' ');
      }
    }
    _staticLines = staticLines;

    final textSpan = TextSpan(style: widget.baseStyle, children: spans);
    // justify אינו מותח שורה אחרונה, ולכן גם לא פסקה בת שורה חזותית אחת.
    // מדידה מוקדמת של מספר השורות = layout שני על כל הפסקה, ומייקרת גלילה.
    Widget result = SelectionFillText.rich(
      textSpan,
      textAlign: widget.textAlign,
      strutStyle: exactLineHeightStrut(widget.baseStyle, textSpan),
    );
    if (frames.isNotEmpty) {
      result = PluginHighlightFrameOverlay(
        ranges: _toGraphemeRanges(textSpan, frames),
        child: result,
      );
    }
    result = ReaderParagraphLines(
      lines: lineData,
      gutterStyle: widget.gutterStyle,
      divisionStyle: widget.divisionStyle,
      child: result,
    );
    // סימונים מורמים: ספירת המופעים רצה על הפסקה כולה, באותו סדר שהשכבה
    // קוראת את הטקסט מעץ הרינדור.
    return RaisedMarkerOverlay.wrap(
      context: context,
      markers: RaisedMarkers.extract(markerSources.join()),
      baseStyle: widget.baseStyle,
      linkColor: widget.linkStyle?.color,
      activeBackground: widget.anchorActiveBackground,
      child: result,
    );
  }

  TextStyle _headingStyle(TextStyle lineStyle) => lineStyle.copyWith(
    fontSize: (lineStyle.fontSize ?? 18) * kHtmlSmallerFontScale,
    fontWeight: FontWeight.bold,
    fontVariations: AppFonts.boldFontVariations(lineStyle.fontFamily),
    color: widget.headingColor,
  );

  _BuiltLine _buildLine(
    ContinuousReadingParagraphLine line,
    Map<(String, TextStyle), _BuiltLine> staticLines,
  ) {
    final htmlText = line.htmlText;
    if (htmlText == null) {
      return (
        spans: [TextSpan(text: line.text, style: line.style)],
        length: line.text.length,
      );
    }
    final cacheable = !htmlText.contains('<a');
    final key = (htmlText, line.style);
    if (cacheable) {
      final cached = staticLines[key] ?? _staticLines[key];
      if (cached != null) {
        staticLines[key] = cached;
        return cached;
      }
    }
    final spans = buildInlineHtmlSpans(
      htmlText,
      line.style,
      onTapUrl: widget.onTapUrl,
      onAnchorHover: widget.onAnchorHover,
      onAnchorExit: widget.onAnchorExit,
      linkStyle: widget.linkStyle,
      anchorActiveBackground: widget.anchorActiveBackground,
      recognizerSink: _linkRecognizers,
      onMiddleClickUrl: widget.onMiddleClickUrl,
    );
    var length = 0;
    for (final span in spans) {
      length += span.toPlainText(includeSemanticsLabels: false).length;
    }
    final built = (spans: spans, length: length);
    if (cacheable) staticLines[key] = built;
    return built;
  }

  void _disposeLinkRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
  }
}

const HtmlEscape _htmlEscape = HtmlEscape(HtmlEscapeMode.element);

/// טווחי ההדגשה של התוספים נמדדים ב-graphemes על צמתי הטקסט של ה-HTML,
/// ו-`<br>` אינו נספר בהם — בספאנים הוא `\n`. מחזיר אופסט UTF-16 בשורה.
int _lineUtf16Offset(
  ContinuousReadingParagraphLine line,
  int grapheme, {
  required bool isStart,
}) {
  final htmlText = line.htmlText;
  if (htmlText == null) {
    return line.text.characters.take(grapheme).join().length;
  }
  var remaining = grapheme;
  var utf16 = 0;
  bool walk(dom.Node node) {
    if (node is dom.Text) {
      final chars = node.data.characters;
      final length = chars.length;
      // תחילת טווח בגבול צומת שייכת לצומת הבא (אחרי <br>), סופו — לקודם.
      if (isStart ? remaining < length : remaining <= length) {
        utf16 += chars.take(remaining).join().length;
        return true;
      }
      remaining -= length;
      utf16 += node.data.length;
      return false;
    }
    if (node is dom.Element && node.localName == 'br') {
      utf16++;
      return false;
    }
    for (final child in node.nodes) {
      if (walk(child)) return true;
    }
    return false;
  }

  for (final node in _parseFragmentCached(htmlText).nodes) {
    if (walk(node)) break;
  }
  return utf16;
}

/// [PluginHighlightFrameOverlay] סופר graphemes על טקסט הפסקה כולו.
List<PluginHighlightRenderedRange> _toGraphemeRanges(
  TextSpan text,
  List<PluginHighlightRenderedRange> utf16Ranges,
) {
  final boundaries = <int>[0];
  var cursor = 0;
  for (final grapheme
      in text.toPlainText(includeSemanticsLabels: false).characters) {
    cursor += grapheme.length;
    boundaries.add(cursor);
  }
  int toGrapheme(int utf16) {
    var lo = 0;
    var hi = boundaries.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (boundaries[mid] <= utf16) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  return [
    for (final range in utf16Ranges)
      PluginHighlightRenderedRange(
        start: toGrapheme(range.start),
        end: toGrapheme(range.end),
        highlight: range.highlight,
      ),
  ];
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
  void Function(String url)? onMiddleClickUrl,
  bool hideRaisedMarkers = true,
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
        onMiddleClickUrl: onMiddleClickUrl,
        hideRaisedMarkers: hideRaisedMarkers,
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
  void Function(String url)? onMiddleClickUrl,
  bool hideRaisedMarkers = true,
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
      final childStyle = _styleForElement(
        node,
        style,
        hideRaisedMarkers: hideRaisedMarkers,
      );
      // עוגן-מילה וטווח-ציטוט — צבע ה-primary של הנושא בלי קו תחתון; active
      // מקבל רקע בלבד (הדגשה מרחיבה את האות ופורסת מחדש את השורה).
      // שאר הקישורים — קו תחתון + צבע theme.
      //
      // כשהגליפים מוסתרים (hideRaisedMarkers) עוגן-מילה וסימון הערה נשארים
      // שקופים: הצבע והרקע עוברים לציור המורם של RaisedMarkerOverlay.
      final effectiveLinkStyle = node.classes.contains('link-anchor')
          // הווריאנט שב-childStyle נשמר גם ב-active (מיזוג linkStyle היה גורר
          // קו תחתון של קישור ומוחק את קו-התחתון שהוא סימנו של וריאנט 5).
          ? (hideRaisedMarkers
                ? childStyle
                : childStyle.copyWith(
                    color: linkStyle?.color,
                    backgroundColor: node.classes.contains('link-anchor-active')
                        ? anchorActiveBackground
                        : null,
                  ))
          : node.classes.contains('book-note-marker') && hideRaisedMarkers
          ? childStyle
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
        onMiddleClickUrl: onMiddleClickUrl,
        hideRaisedMarkers: hideRaisedMarkers,
      );
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          onTapUrl(href);
        };
      trackLinkTapDown(recognizer);
      recognizerSink?.add(recognizer);
      if (HtmlLinkHandler.opensAnotherBook(href)) {
        registerInlineLinkRecognizer(
          recognizer,
          href,
          onMiddleClick: onMiddleClickUrl,
        );
      }
      // קישורי עוגן והערה מקבלים תצוגה מקדימה בריחוף.
      final isHoverableAnchor =
          isPreviewHoverableUrl(href) &&
          (onAnchorHover != null || onAnchorExit != null);
      final mouseCursor = isHoverableAnchor ? SystemMouseCursors.click : null;
      final onEnter = isHoverableAnchor && onAnchorHover != null
          ? (PointerEnterEvent event) => onAnchorHover(href, event.position)
          : null;
      final onExit = isHoverableAnchor && onAnchorExit != null
          ? (PointerExitEvent _) => onAnchorExit(href)
          : null;

      // ה-hit-test של RenderParagraph מחזיר את ספאן-העלה שמכיל את הטקסט —
      // recognizer שיושב רק על ספאן-האב לעולם אינו נפגע בלחיצה במיקום.
      // לכן ההתנהגות מועתקת לכל עלה בתת-העץ (אותו recognizer משותף, כך
      // שה-dispose דרך recognizerSink נשאר יחיד).
      InlineSpan withLinkBehavior(InlineSpan span) {
        if (span is! TextSpan) return span;
        return TextSpan(
          text: span.text,
          style: span.style,
          recognizer: recognizer,
          mouseCursor: mouseCursor,
          onEnter: onEnter,
          onExit: onExit,
          children: span.children?.map(withLinkBehavior).toList(),
        );
      }

      return [
        TextSpan(
          style: effectiveLinkStyle,
          recognizer: recognizer,
          mouseCursor: mouseCursor,
          onEnter: onEnter,
          onExit: onExit,
          children: children.map(withLinkBehavior).toList(),
        ),
      ];
    }
  }

  final childStyle = _styleForElement(
    node,
    style,
    hideRaisedMarkers: hideRaisedMarkers,
  );
  return _nodesToSpans(
    node.nodes,
    childStyle,
    onTapUrl: onTapUrl,
    onAnchorHover: onAnchorHover,
    onAnchorExit: onAnchorExit,
    linkStyle: linkStyle,
    anchorActiveBackground: anchorActiveBackground,
    recognizerSink: recognizerSink,
    onMiddleClickUrl: onMiddleClickUrl,
    hideRaisedMarkers: hideRaisedMarkers,
  );
}

TextStyle _styleForElement(
  dom.Element element,
  TextStyle parentStyle, {
  bool hideRaisedMarkers = true,
}) {
  var style = parentStyle;
  final localName = element.localName;
  // נקראים פעם אחת: `classes` מפרק את המחרוזת מחדש בכל גישה.
  final classes = element.classes.toSet();
  final inlineStyle = element.attributes['style'] ?? '';

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
  final inlineFontSize = _inlineFontSize(inlineStyle, style.fontSize ?? 18);
  if (inlineFontSize != null) {
    style = style.copyWith(fontSize: inlineFontSize);
  }
  // sup חשוף (למשל מייבוא Word) מוקטן כמו ב-fwfh, בלי נטייה; סמני ההערות
  // מוקטנים ונוטים לפי ה-CSS שהוגדר להם ב-SmartTextWidget.
  // `processText` ממיר כל sup לא-מספרי ל-span (ראו raised_markers.dart), ולכן
  // בפועל מגיע לכאן `raised-sup`; תג sup חשוף נשאר נתמך לקלט שלא עבר עיבוד.
  if (localName == 'sup' || classes.contains(kRaisedSupClass)) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * kHtmlSmallerFontScale,
    );
    // הגליף עצמו שקוף — RaisedMarkerOverlay מצייר אותו מורם. תג sup חשוף
    // (קלט שלא עבר processText) נשאר גלוי, שם אין סימון לשכבה לצייר.
    if (hideRaisedMarkers && classes.contains(kRaisedSupClass)) {
      style = style.copyWith(color: const Color(0x00000000));
    }
  }
  // טקסט תחתי שהומר ל-span (ראו TextRendererService._fixSubscripts) — מוקטן.
  if (classes.contains('subscript-text')) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * kHtmlSmallerFontScale,
    );
  }
  if (classes.contains(kFootnoteMarkerClass) ||
      classes.contains('book-note-marker')) {
    style = style.copyWith(
      fontSize: (style.fontSize ?? 18) * kFootnoteMarkerScale,
      fontStyle: FontStyle.italic,
    );
    // גם סימון ההערה הלחיץ שקוף — RaisedMarkerOverlay מצייר אותו מורם
    // ומפנה אליו לחיצות; ה-recognizer נשאר על הספאן שבשורה.
    if (hideRaisedMarkers) {
      style = style.copyWith(color: const Color(0x00000000));
    }
  }
  // סמן-אות של מפרש: מוקטן, והטיפוגרפיה נקבעת אך ורק בווריאנט שהוקצה למפרש.
  // נטייה כפויה כאן הייתה מוחקת את ההבחנה בין המפרשים.
  if (classes.contains('link-anchor')) {
    style = applyLinkAnchorVariant(
      linkAnchorVariantFromClasses(classes),
      style.copyWith(
        fontSize: (style.fontSize ?? 18) * kLinkAnchorMarkerScale,
      ),
    );
    // הגליף שקוף; הווריאנט נשאר עליו כדי שרוחב המקום יתאים לציור המורם.
    // גם הקו התחתון שלו — אחרת נצבע בצבע ה-decoration שבירושה (#2758).
    if (hideRaisedMarkers) {
      style = style.copyWith(
        color: const Color(0x00000000),
        decorationColor: const Color(0x00000000),
      );
    }
  }
  if (localName == 'i' ||
      localName == 'em' ||
      _italicRe.hasMatch(inlineStyle)) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }
  if (localName == 'b' || localName == 'strong') {
    style = style.copyWith(
      fontWeight: FontWeight.bold,
      fontVariations: AppFonts.boldFontVariations(style.fontFamily),
    );
  }

  // הדגשות החיפוש מגיעות כ-color/background-color ב-style; בלי פרסורן הן לא
  // יסומנו במצב רציף.
  final inlineColor = _inlineCssColor(_colorRe, inlineStyle);
  if (inlineColor != null) {
    style = style.copyWith(color: inlineColor);
  }
  final inlineBackground = _inlineCssColor(_backgroundColorRe, inlineStyle);
  if (inlineBackground != null) {
    style = style.copyWith(backgroundColor: inlineBackground);
  }
  if (_underlineRe.hasMatch(inlineStyle)) {
    style = style.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: _inlineCssColor(_decorationColorRe, inlineStyle),
      decorationThickness: _inlineDecorationThickness(inlineStyle),
    );
  }

  return style;
}

// הביטויים נבנים פעם אחת ולא בכל אלמנט בכל build.
// לוכד `color: <value>` אך לא `background-color:` (שלפניו `-`).
final _colorRe = RegExp(
  r'(?:^|[\s;])color\s*:\s*([^;]+)',
  caseSensitive: false,
);
final _backgroundColorRe = RegExp(
  r'background-color\s*:\s*([^;]+)',
  caseSensitive: false,
);
final _decorationColorRe = RegExp(
  r'text-decoration-color\s*:\s*([^;]+)',
  caseSensitive: false,
);
final _decorationThicknessRe = RegExp(
  r'text-decoration-thickness\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*(px|%)',
  caseSensitive: false,
);
final _fontSizeRe = RegExp(
  r'font-size\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*(em|rem|px|%)?',
  caseSensitive: false,
);
final _italicRe = RegExp(r'font-style\s*:\s*italic', caseSensitive: false);
final _underlineRe = RegExp(
  r'text-decoration\s*:\s*[^;]*\bunderline\b',
  caseSensitive: false,
);
final _rgbaRe = RegExp(
  r'^rgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(0(?:\.\d+)?|\.\d+|1(?:\.0+)?)\s*\)$',
);

Color? _inlineCssColor(RegExp property, String inlineStyle) {
  final match = property.firstMatch(inlineStyle);
  if (match == null) return null;
  return _parseCssColor(match.group(1)!.trim());
}

double? _inlineDecorationThickness(String inlineStyle) {
  final match = _decorationThicknessRe.firstMatch(inlineStyle);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  return match.group(2) == '%' ? value / 100 : value;
}

Color? _parseCssColor(String value) {
  final v = value.toLowerCase().trim();
  final rgba = _rgbaRe.firstMatch(v);
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

double? _inlineFontSize(String inlineStyle, double parentFontSize) {
  final match = _fontSizeRe.firstMatch(inlineStyle);
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
