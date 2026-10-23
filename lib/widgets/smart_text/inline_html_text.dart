import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';
import 'package:url_launcher/url_launcher.dart';

/// מציג [InlineHtmlDocument] ב-Text.rich, עם הקישורים וההתנהגות של `<a>` ב-HtmlWidget
/// של SmartTextWidget: לחיצה, ריחוף, לחיצת גלגל ותצוגה מקדימה במגע.
///
/// ה-recognizers שייכים ל-State ומשוחררים כשהמסמך מתחלף. ה-callbacks נקראים
/// מה-widget הנוכחי, כך שספאן שנשמר אינו קורא ל-closure ישן.
class InlineHtmlText extends StatefulWidget {
  const InlineHtmlText({
    super.key,
    required this.document,
    required this.style,
    this.strutStyle,
    required this.textAlign,
    required this.linkColor,
    required this.primaryColor,
    this.onTapUrl,
    this.onAnchorHover,
    this.onAnchorHoverExit,
    this.onMiddleClickUrl,
    this.splitLongLines = true,
  });

  /// צבע הקישור של הקורא; ב-HtmlWidget הוא עובר ב-CSS כ-hex בלי שקיפות.
  static Color readerLinkColor(ColorScheme colorScheme) =>
      Color(0xFF000000 | AppSurfaces.readerLink(colorScheme).toARGB32());

  /// שורה ארוכה מאוד מוצגת במקטעים ([LongLineChunks]).
  final bool splitLongLines;

  final InlineHtmlDocument document;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;
  final Color linkColor;
  final Color primaryColor;

  /// true — הלחיצה טופלה; אחרת הקישור נפתח בדפדפן, כמו ב-fwfh.
  final Future<bool> Function(String url)? onTapUrl;
  final void Function(String url, Offset globalPosition)? onAnchorHover;
  final void Function(String url)? onAnchorHoverExit;
  final void Function(String url)? onMiddleClickUrl;

  @override
  State<InlineHtmlText> createState() => _InlineHtmlTextState();
}

class _InlineHtmlTextState extends State<InlineHtmlText> {
  List<TapGestureRecognizer> _recognizers = const [];
  InlineHtmlDocument? _recognizersFor;
  bool _recognizersHaveMiddleClick = false;

  TextSpan? _span;
  Object? _spanKey;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers = const [];
    _recognizersFor = null;
  }

  /// כמו ה-WidgetFactory: ריחוף ומיקום מגע לקישורי תצוגה מקדימה בלבד, ולחיצת
  /// גלגל לקישור לספר אחר כשיש מי שפותח ספרים.
  void _ensureRecognizers() {
    final document = widget.document;
    final hasMiddleClick = widget.onMiddleClickUrl != null;
    if (identical(_recognizersFor, document) &&
        _recognizersHaveMiddleClick == hasMiddleClick) {
      return;
    }
    _disposeRecognizers();
    _recognizers = [
      for (final link in document.links)
        _recognizerFor(link, middleClick: hasMiddleClick),
    ];
    _recognizersFor = document;
    _recognizersHaveMiddleClick = hasMiddleClick;
  }

  TapGestureRecognizer _recognizerFor(
    InlineLink link, {
    required bool middleClick,
  }) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => _handleTap(link.url);
    if (isPreviewHoverableUrl(link.href)) trackLinkTapDown(recognizer);
    if (HtmlLinkHandler.opensAnotherBook(link.href)) {
      registerInlineLinkRecognizer(
        recognizer,
        link.href,
        onMiddleClick: middleClick
            ? (url) => widget.onMiddleClickUrl?.call(url)
            : null,
      );
    }
    return recognizer;
  }

  Future<void> _handleTap(String url) async {
    if (!mounted) return;
    final onTapUrl = widget.onTapUrl;
    if (onTapUrl != null && await onTapUrl(url)) return;
    try {
      final uri = Uri.parse(url);
      if (!await canLaunchUrl(uri)) return;
      await launchUrl(uri);
    } catch (error) {
      debugPrint('Could not launch "$url": $error');
    }
  }

  TextSpan _buildSpan() {
    final document = widget.document;
    final staticSpan = document.staticSpan;
    if (staticSpan != null) return staticSpan;
    _ensureRecognizers();
    final hover = widget.onAnchorHover != null;
    final key = (
      document,
      widget.linkColor,
      widget.primaryColor,
      hover,
      _recognizers,
    );
    final cached = _span;
    if (cached != null && _spanKey == key) return cached;

    final children = <InlineSpan>[];
    for (final run in document.runs) {
      final style = run.resolvedStyle(
        linkColor: widget.linkColor,
        primaryColor: widget.primaryColor,
      );
      if (run.link < 0) {
        children.add(TextSpan(text: run.text, style: style));
        continue;
      }
      final href = document.links[run.link].href;
      final recognizer = _recognizers[run.link];
      if (!hover || !isPreviewHoverableUrl(href)) {
        children.add(
          TextSpan(text: run.text, style: style, recognizer: recognizer),
        );
        continue;
      }
      children.add(
        TextSpan(
          text: run.text,
          style: style,
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          onEnter: (event) => widget.onAnchorHover?.call(href, event.position),
          onExit: (_) => widget.onAnchorHoverExit?.call(href),
        ),
      );
    }
    final span = TextSpan(children: children);
    _span = span;
    _spanKey = key;
    return span;
  }

  @override
  Widget build(BuildContext context) => inlineSpanText(
    _buildSpan(),
    plainTextLength: widget.document.plainText.length,
    style: widget.style,
    strutStyle: widget.strutStyle,
    textAlign: widget.textAlign,
    splitLongLines: widget.splitLongLines,
  );
}

/// מציג ספאן שורה ב-[SelectionFillText], ושורה ארוכה מאוד ב-[LongLineChunks].
/// שורה בלי קישורים מוצגת כך ישירות, בלי ה-State של [InlineHtmlText].
Widget inlineSpanText(
  TextSpan span, {
  required int plainTextLength,
  required TextStyle style,
  StrutStyle? strutStyle,
  required TextAlign textAlign,
  bool splitLongLines = true,
}) {
  final longLine = splitLongLines && plainTextLength > kLongLineMinChars
      ? splitLongLine(span)
      : null;
  if (longLine != null) {
    return LongLineChunks(
      split: longLine,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
    );
  }
  return SelectionFillText.rich(
    span,
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
  );
}
