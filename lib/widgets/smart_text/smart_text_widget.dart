import 'dart:async';
import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/core/diagnostics/smart_text_render_stats.dart';
import 'package:html/dom.dart' as dom;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/exact_line_height.dart';
import 'package:otzaria/widgets/smart_text/inline_html_document.dart';
import 'package:otzaria/widgets/smart_text/inline_html_text.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';
import 'package:otzaria/widgets/smart_text/otzaria_widget_factory.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/smart_text_css.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/services/reader_section_content_tracker.dart';
import 'package:otzaria/plugins/services/reader_section_sync_gate.dart';
import 'package:otzaria/plugins/view/plugin_highlight_frame_overlay.dart';

/// ווידג'ט חכם להצגת טקסט עברי
///
/// מרכז את כל הלוגיקה של עיבוד והצגת טקסט במקום אחד:
/// - הסרת ניקוד וטעמים
/// - החלפת שמות קדושים
/// - הדגשת תוצאות חיפוש
/// - עיצוב סוגריים
/// - טיפול בקישורים פנימיים
class SmartTextWidget extends StatelessWidget {
  /// הטקסט הגולמי להצגה (יכול להכיל HTML)
  final String text;

  /// הגדרות הרינדור
  final RenderSettings settings;

  /// callback לפתיחת ספר/טאב
  final Function(OpenedTab)? onOpenBook;

  /// callback ללחיצה על סימון הערה אישית inline.
  /// מקבל את אינדקס השורה (0-based) שעליה ההערה.
  final void Function(int lineIndex)? onNoteTap;

  /// callback ללחיצה על עוגן-מילה (`otzaria://anchor`). מקבל את ה-URL המלא;
  /// מזהה את הקישור ומקפיץ תצוגה מקדימה של המפרש.
  final void Function(String url)? onAnchorTap;

  /// callback לריחוף מעל עוגן-מילה — מקבל את ה-URL ואת מיקום הסמן הגלובלי.
  /// כשמסופק, onEnter/onExit מוזרקים ל-TextSpan של הסמן (ל-fwfh אין hover על
  /// `<a>`), והסמן נשאר ספאן טקסט.
  final void Function(String url, Offset globalPosition)? onAnchorHover;

  /// callback ליציאת הסמן מעוגן-מילה.
  final void Function(String url)? onAnchorHoverExit;

  /// הקשת מגע על קישור שהתצוגה המקדימה שלו נפתחת במחשב בריחוף
  /// ([isTouchPreviewUrl]) — מקבל את ה-URL ואת מיקום ההקשה.
  final void Function(String url, Offset globalPosition)? onTouchPreview;

  /// מפתח ייחודי לווידג'ט (לאופטימיזציה)
  final Key? widgetKey;

  /// מצב רינדור של HtmlWidget
  final RenderMode renderMode;

  /// כאשר שניהם מסופקים, הווידג'ט מצייר Highlights זמניים של תוספים.
  final String? highlightBookId;

  /// מזהה הספר היציב (`PluginBookIdentity.uidOf`). מבדיל בין שני ספרים בעלי
  /// אותה כותרת; הדגשה ישנה ללא uid מצוירת כמקודם.
  final String? highlightBookUid;
  final int? highlightSectionIndex;
  final String? highlightSourceText;
  final int? highlightBookDbId;
  final String? highlightBookType;
  final String? highlightBookSource;

  /// בדיקות: מציג כל שורה ב-HtmlWidget, כייחוס למסלול הספאנים.
  @visibleForTesting
  static bool debugForceHtmlWidget = false;

  const SmartTextWidget({
    super.key,
    required this.text,
    required this.settings,
    this.onOpenBook,
    this.onNoteTap,
    this.onAnchorTap,
    this.onAnchorHover,
    this.onAnchorHoverExit,
    this.onTouchPreview,
    this.widgetKey,
    this.renderMode = RenderMode.column,
    this.highlightBookId,
    this.highlightBookUid,
    this.highlightSectionIndex,
    this.highlightSourceText,
    this.highlightBookDbId,
    this.highlightBookType,
    this.highlightBookSource,
  });

  @override
  Widget build(BuildContext context) {
    final bookId = highlightBookId;
    final sectionIndex = highlightSectionIndex;
    final listenables = <Listenable>[];
    // כשיש חיפוש, מאזינים לגרסת תבנית ההדגשה: תבנית מבוססת-אינדקס שמגיעה
    // אחרי הרינדור הראשוני (fallback) גורמת להתרנדר מחדש עם ההדגשה המדויקת.
    if (settings.searchText.isNotEmpty) {
      listenables.add(utils.highlightPatternRevision);
    }
    if (bookId != null && sectionIndex != null) {
      listenables.add(
        PluginHighlightRegistry.instance.sectionListenable(
          bookId: bookId,
          sectionIndex: sectionIndex,
          bookUid: highlightBookUid,
        ),
      );
    }
    Widget buildResolved() => _buildResolved(
      context,
      bookId != null && sectionIndex != null
          ? PluginHighlightRegistry.instance.getAllHighlights(
              bookId: bookId,
              sectionIndex: sectionIndex,
              bookUid: highlightBookUid,
            )
          : const [],
    );
    if (listenables.isEmpty) return buildResolved();
    return ListenableBuilder(
      listenable: listenables.length == 1
          ? listenables.single
          : Listenable.merge(listenables),
      builder: (context, _) => buildResolved(),
    );
  }

  Widget _buildResolved(
    BuildContext context,
    List<PluginHighlight> highlights,
  ) {
    // עיבוד הטקסט דרך השירות המרכזי
    var processedHtml = TextRendererService.processText(text, settings);
    final bookId = highlightBookId;
    final sectionIndex = highlightSectionIndex;
    if (bookId != null && sectionIndex != null) {
      syncReaderSectionForPlugins(
        bookId: bookId,
        bookUid: highlightBookUid,
        bookDbId: highlightBookDbId,
        bookType: highlightBookType,
        bookSource: highlightBookSource,
        sectionIndex: sectionIndex,
        rawSourceHtml: highlightSourceText ?? text,
        processedHtml: processedHtml,
        renderingSignature: settings.sectionContentRenderingSignature,
      );
    }
    var frameRanges = const <PluginHighlightRenderedRange>[];
    if (highlights.isNotEmpty) {
      const highlightRenderer = PluginHighlightRenderer();
      final rendering = highlightRenderer.renderWithRanges(
        bookId: highlightBookId!,
        sectionIndex: highlightSectionIndex!,
        rawText: highlightSourceText ?? text,
        processedHtml: processedHtml,
        highlights: highlights,
        revealedHighlightId: PluginHighlightRevealService.instance.highlightId,
      );
      processedHtml = rendering.html;
      frameRanges = rendering.ranges;
    }
    // סימונים מורמים (sup פשוט ולא-מספרי שהומר ל-span ב-processText): מחולצים
    // מה-HTML הסופי. ה-HTML לא משתנה — הגליפים נשארים בשורה (שקופים, בסדר
    // הנכון), ושכבת הציור מציירת אותם מורמים מעל מקומם האמיתי.
    final raisedMarkers = RaisedMarkers.extract(processedHtml);
    final fontFamily = AppFonts.taamimSafeFontFamily(
      settings.fontFamily,
      processedHtml,
    );
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      fontFamily: AppFonts.renderFontFamily(fontFamily),
      fontWeight: settings.fontWeight,
      fontVariations: AppFonts.boldFontVariations(
        fontFamily,
        settings.fontWeight ?? FontWeight.normal,
      ),
      height: settings.lineHeight,
    );
    // נחוצים רק לשורה עם קישורים או ל-HtmlWidget, לא לשורה סטטית.
    late final colorScheme = Theme.of(context).colorScheme;
    late final linkColor = AppSurfaces.readerLink(colorScheme);
    late final onTapUrl = _tapHandler(context);
    late final onMiddleClickUrl = onOpenBook == null
        ? null
        : (String url) => HtmlLinkHandler.openLinkInBackground(context, url);

    // מסלול מהיר: שורה שכל ה-markup בה inline מוצגת ב-Text.rich, בספאנים זהים
    // לאלה ש-HtmlWidget היה בונה — בלי עלות עץ הווידג'טים של fwfh.
    if (renderMode == RenderMode.column && !debugForceHtmlWidget) {
      final line = InlineHtmlDocument.parseLine(processedHtml, textStyle);
      if (line != null) {
        SmartTextRenderStats.fastLine(heading: line.isHeading);
        final document = line.document;
        if (document.plainText.isEmpty) {
          return const SizedBox.shrink();
        }
        final lineStyle = line.style;
        final staticSpan = document.staticSpan;
        final textAlign = settings.justifyText
            ? TextAlign.justify
            : TextAlign.right;
        // רוחב מלא כמו <div> בלוק ב-HtmlWidget - אחרת מסכים שעוטפים שורה
        // ב-Center (הגבלת רוחב קריאה) ימרכזו שורות קצרות בטעות.
        return _withPluginFrames(
          frameRanges,
          _withRaisedMarkers(
            context,
            raisedMarkers,
            lineStyle,
            SizedBox(
              key: widgetKey,
              width: double.infinity,
              child: staticSpan != null
                  ? inlineSpanText(
                      staticSpan,
                      plainTextLength: document.plainText.length,
                      style: lineStyle,
                      strutStyle: line.strutStyle,
                      textAlign: textAlign,
                      splitLongLines: !line.isHeading,
                    )
                  : InlineHtmlText(
                      document: document,
                      style: lineStyle,
                      strutStyle: line.strutStyle,
                      textAlign: textAlign,
                      linkColor: InlineHtmlText.readerLinkColor(colorScheme),
                      primaryColor: colorScheme.primary,
                      splitLongLines: !line.isHeading,
                      onTapUrl: onTapUrl,
                      onAnchorHover: onAnchorHover,
                      onAnchorHoverExit: onAnchorHoverExit,
                      onMiddleClickUrl: onMiddleClickUrl,
                    ),
            ),
          ),
        );
      }
    }

    SmartTextRenderStats.fullLine(columnMode: renderMode == RenderMode.column);
    // הציור המורם נמדד בסגנון השורה — בכותרת זה סגנון הכותרת, כמו הגליף שבה.
    final lineStyle =
        SimpleInlineHtml.headingStyle(processedHtml, textStyle) ?? textStyle;

    // סמן-מספר וטווח-ציטוט נשארים בשורה בצבע הקישור; fwfh לא מכיר
    // inherit ולכן הערך מפורש. צבעי אותיות המפרשים המורמות נפתרים ב-wrap.
    String toCssHex(Color color) =>
        '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
    final anchorLinkColorCss = toCssHex(linkColor);
    final headingColorCss = toCssHex(colorScheme.onSurfaceVariant);
    final markdownSurfaceCss = toCssHex(colorScheme.surfaceContainerHighest);
    final markdownBorderCss = toCssHex(colorScheme.outlineVariant);
    final hasMarkdownBlock = processedHtml.contains(kMarkdownBlockClass);

    return _withPluginFrames(
      frameRanges,
      _withRaisedMarkers(
        context,
        raisedMarkers,
        lineStyle,
        _SmartTextCallbacks(
          onAnchorHover: onAnchorHover,
          onAnchorHoverExit: onAnchorHoverExit,
          onMiddleClickUrl: onMiddleClickUrl,
          child: HtmlWidget(
            _wrapWithRtlDivCached(processedHtml, settings.justifyText),
            key: widgetKey,
            // מעל 10K תווים fwfh בונה ב-isolate ומציג קודם גובה 0 — שורת רשימה
            // קופצת אחרי פריים ו-jumpTo מחטיא.
            buildAsync: false,
            renderMode: renderMode,
            textStyle: textStyle,
            // העץ נשמר כל עוד ה-html וה-textStyle זהים; הצבעים אפויים ב-CSS,
            // והימצאות ה-callbacks קובעת את מבנה הספאנים.
            rebuildTriggers: [
              linkColor,
              colorScheme.surfaceContainerHighest,
              colorScheme.outlineVariant,
              colorScheme.onSurfaceVariant,
              onAnchorHover != null,
              onOpenBook != null,
            ],
            factoryBuilder: _SmartTextWidgetFactory.new,
            customStylesBuilder: (dom.Element element) {
              final elementCss = smartTextElementCss(
                element.localName,
                element.classes,
                hasHref: element.attributes.containsKey('href'),
                fontFamily: fontFamily,
                linkColorCss: anchorLinkColorCss,
                headingColorCss: headingColorCss,
              );
              if (elementCss != null) return elementCss;
              final headingCss = smartTextHeadingCss(
                element.localName,
                fontFamily,
              );
              if (!hasMarkdownBlock) {
                return headingCss.isEmpty ? null : headingCss;
              }
              final markdownCss = _markdownElementCss(
                element,
                linkColorCss: anchorLinkColorCss,
                surfaceCss: markdownSurfaceCss,
                borderCss: markdownBorderCss,
              );
              if (headingCss.isNotEmpty) {
                return {...headingCss, ...?markdownCss};
              }
              return markdownCss;
            },
            onTapUrl: onTapUrl,
          ),
        ),
      ),
    );
  }

  /// הטיפול בלחיצה על קישור, משותף ל-HtmlWidget ולמסלול הספאנים. null — אין
  /// callback, והקישור נפתח בדפדפן.
  Future<bool> Function(String url)? _tapHandler(BuildContext context) {
    if (onOpenBook == null && onNoteTap == null && onAnchorTap == null) {
      return null;
    }
    return (url) async {
      final touchPosition = touchLinkTapPosition();
      if (touchPosition != null &&
          onTouchPreview != null &&
          isTouchPreviewUrl(url)) {
        onTouchPreview!(url, touchPosition);
        return true;
      }
      // עוגן-מילה — תצוגה מקדימה של המפרש, לפני שאר הקישורים.
      if (url.startsWith('otzaria://anchor') && onAnchorTap != null) {
        onAnchorTap!(url);
        return true;
      }
      // סמן-מספר של הערה — הפעולה שלו היא ריחוף בלבד.
      if (url.startsWith('otzaria://note-marker')) return true;
      // סימון הערה אישית inline — נטפל לפני שאר הקישורים.
      if (url.startsWith('otzaria://note')) {
        final lineIndex = int.tryParse(
          Uri.parse(url).queryParameters['line'] ?? '',
        );
        if (lineIndex != null) {
          onNoteTap?.call(lineIndex);
        }
        return true;
      }
      if (url.startsWith('otzaria://book-note')) return true;
      if (onOpenBook == null) return false;
      return await HtmlLinkHandler.handleLink(
        context,
        url,
        (tab) => onOpenBook!(tab),
      );
    };
  }

  /// עוטף את ווידג'ט הטקסט בשכבת הציור של הסימונים המורמים, אם יש כאלה.
  Widget _withRaisedMarkers(
    BuildContext context,
    List<RaisedMarker> markers,
    TextStyle textStyle,
    Widget child,
  ) {
    return RaisedMarkerOverlay.wrap(
      context: context,
      markers: markers,
      baseStyle: textStyle,
      child: child,
    );
  }

  Widget _withPluginFrames(
    List<PluginHighlightRenderedRange> ranges,
    Widget child,
  ) {
    if (!ranges.any(
      (range) => const {
        'text-background',
        'box',
      }.contains(range.highlight.style.markerMode),
    )) {
      return child;
    }
    return PluginHighlightFrameOverlay(ranges: ranges, child: child);
  }
}

/// ה-HTML העטוף נשמר לפי ה-HTML המעובד (שמוחזר ממטמון processText), כדי
/// ש-HtmlWidget יקבל בכל build את אותו מופע ולא ישווה מחרוזת חדשה תו אחר תו.
final LinkedHashMap<(String, bool), String> _rtlDivCache = LinkedHashMap();
int _rtlDivCacheChars = 0;
const int _rtlDivCacheMaxChars = 2 * 1024 * 1024;

String _wrapWithRtlDivCached(String html, bool justifyText) {
  final key = (html, justifyText);
  final cached = _rtlDivCache.remove(key);
  if (cached != null) {
    _rtlDivCache[key] = cached;
    return cached;
  }
  final wrapped = TextRendererService.wrapWithRtlDiv(
    html,
    justifyText: justifyText,
  );
  if (html.length > _rtlDivCacheMaxChars ~/ 4) return wrapped;
  _rtlDivCache[key] = wrapped;
  _rtlDivCacheChars += wrapped.length;
  while (_rtlDivCacheChars > _rtlDivCacheMaxChars) {
    final oldest = _rtlDivCache.keys.first;
    _rtlDivCacheChars -= _rtlDivCache.remove(oldest)!.length;
  }
  return wrapped;
}

Map<String, String>? _markdownElementCss(
  dom.Element element, {
  required String linkColorCss,
  required String surfaceCss,
  required String borderCss,
}) {
  if (!_isInsideMarkdownBlock(element)) return null;

  return switch (element.localName) {
    'h1' => _markdownHeadingCss('1.7em', top: 22, bottom: 10),
    'h2' => _markdownHeadingCss('1.45em', top: 20, bottom: 9),
    'h3' => _markdownHeadingCss('1.25em', top: 18, bottom: 8),
    'h4' => _markdownHeadingCss('1.1em', top: 16, bottom: 7),
    'h5' || 'h6' => _markdownHeadingCss('1em', top: 14, bottom: 6),
    'p' => {'margin': '0 0 10px 0', 'line-height': '1.7'},
    'a' => {'color': linkColorCss, 'text-decoration': 'underline'},
    'blockquote' => {
      'border-right': '4px solid $borderCss',
      'padding': '4px 12px',
      'margin': '10px 4px',
      'background-color': surfaceCss,
      'font-style': 'italic',
    },
    'code' => {
      'direction': 'ltr',
      'text-align': 'left',
      'font-family': 'monospace',
      'font-size': '0.92em',
    },
    'pre' => {
      'direction': 'ltr',
      'text-align': 'left',
      'font-family': 'monospace',
      'background-color': surfaceCss,
      'padding': '12px',
      'margin': '10px 0',
      'border-radius': '6px',
      'line-height': '1.5',
    },
    'table' => {
      'border-collapse': 'collapse',
      'width': '100%',
      'margin': '10px 0',
    },
    'tr' => _markdownZebraRowCss(element, surfaceCss),
    'td' => {'border': '1px solid $borderCss', 'padding': '6px 8px'},
    'th' => {
      'border': '1px solid $borderCss',
      'padding': '6px 8px',
      'background-color': surfaceCss,
      'font-weight': 'bold',
    },
    'ul' || 'ol' => {'padding-right': '24px', 'margin': '6px 0 10px 0'},
    'li' => {'margin-bottom': '4px', 'line-height': '1.7'},
    'hr' => {'margin': '18px 0'},
    _ => null,
  };
}

Map<String, String> _markdownHeadingCss(
  String fontSize, {
  required int top,
  required int bottom,
}) => {
  'font-size': fontSize,
  'margin': '${top}px 0 ${bottom}px 0',
  'line-height': '1.4',
};

Map<String, String>? _markdownZebraRowCss(dom.Element row, String surfaceCss) {
  final siblings = row.parent?.nodes;
  if (siblings == null) return null;
  var index = 0;
  for (final node in siblings) {
    if (identical(node, row)) {
      return index.isEven ? null : {'background-color': surfaceCss};
    }
    if (node is dom.Element) index++;
  }
  return null;
}

bool _isInsideMarkdownBlock(dom.Element element) {
  dom.Element? current = element;
  while (current != null) {
    if (current.className.isNotEmpty &&
        current.classes.contains(kMarkdownBlockClass)) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

/// WidgetFactory ל-fwfh עם שלוש אחריות:
/// 1. בולד אמיתי לגופן משתנה — מזריק FontVariation('wght') לספאנים מודגשים.
/// 2. ריחוף על עוגני-מילה — fwfh בונה recognizer לכל `<a>`; זוכרים אילו
///    recognizers שייכים ל-href של עוגן, וכשה-TextSpan נבנה מזריקים
///    onEnter/onExit לצד ה-recognizer הקיים.
/// 3. קיבוע גובה השורה — ראו [buildText].
class _SmartTextWidgetFactory extends OtzariaWidgetFactory {
  final _previewHrefByRecognizer = <GestureRecognizer, String>{};
  State? _state;

  /// ה-factory והעץ השמור שורדים בנייה חוזרת, לכן callbacks נקראים מהבנייה
  /// הנוכחית ולא מזו שבנתה את העץ.
  _SmartTextCallbacks? get _live {
    final state = _state;
    if (state == null || !state.mounted) return null;
    return state.context.getInheritedWidgetOfExactType<_SmartTextCallbacks>();
  }

  @override
  Future<bool> onTapCallback(String url) async {
    final state = _state;
    final widget = state != null && state.mounted ? state.widget : null;
    final callback = widget is HtmlWidget ? widget.onTapUrl : null;
    return callback != null && await callback(url);
  }

  @override
  GestureRecognizer? buildGestureRecognizer(
    BuildTree tree, {
    GestureTapCallback? onTap,
  }) {
    final recognizer = super.buildGestureRecognizer(tree, onTap: onTap);
    final href = tree.element.attributes['href'];
    if (recognizer != null && href != null && isPreviewHoverableUrl(href)) {
      _previewHrefByRecognizer[recognizer] = href;
      if (recognizer is TapGestureRecognizer) trackLinkTapDown(recognizer);
    }
    if (recognizer is TapGestureRecognizer &&
        href != null &&
        HtmlLinkHandler.opensAnotherBook(href)) {
      registerInlineLinkRecognizer(
        recognizer,
        href,
        onMiddleClick: _live?.onMiddleClickUrl == null
            ? null
            : (url) => _live?.onMiddleClickUrl?.call(url),
      );
    }
    return recognizer;
  }

  /// ה-RichText של fwfh נבנה בלי strut ואין פרמטר להעביר אחד מבחוץ, לכן
  /// בונים מחדש את מה ש-fwfh בנה עם [exactLineHeightStrut] ועם מילוי הבחירה.
  /// מבנה אחר מהצפוי (גרסת fwfh חדשה) פשוט נשאר כפי שהוא.
  @override
  Widget? buildText(
    BuildTree tree,
    InheritedProperties resolved,
    InlineSpan text,
  ) {
    final built = super.buildText(tree, resolved, text);
    if (built is! Builder) {
      return built;
    }
    final strutStyle = exactLineHeightStrut(resolved.prepareTextStyle(), text);

    return Builder(
      builder: (context) => withSelectionFillRichText(
        built.builder(context),
        strutStyle: strutStyle,
      ),
    );
  }

  @override
  InlineSpan? buildTextSpan({
    List<InlineSpan>? children,
    GestureRecognizer? recognizer,
    TextStyle? style,
    String? text,
  }) {
    style = _withBoldVariations(style);

    final href = recognizer == null
        ? null
        : _previewHrefByRecognizer[recognizer];
    if (_live?.onAnchorHover == null || href == null) {
      return super.buildTextSpan(
        children: children,
        recognizer: recognizer,
        style: style,
        text: text,
      );
    }
    return TextSpan(
      children: children,
      text: text,
      style: style,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.click,
      onEnter: (event) => _live?.onAnchorHover?.call(href, event.position),
      onExit: (_) => _live?.onAnchorHoverExit?.call(href),
    );
  }

  /// מוסיף FontVariation לספאן מודגש בגופן משתנה (אם עוד לא הוגדר), כדי לקבל
  /// בולד אמיתי במקום מלאכותי לפי הגופן שנפתר בפועל בספאן.
  TextStyle? _withBoldVariations(TextStyle? style) {
    if (style == null || style.fontVariations != null) return style;
    final variations = AppFonts.boldFontVariations(
      style.fontFamily,
      style.fontWeight ?? FontWeight.normal,
    );
    if (variations == null) return style;
    return style.copyWith(fontVariations: variations);
  }

  @override
  void reset(State state) {
    _state = state;
    _previewHrefByRecognizer.clear();
    super.reset(state);
  }
}

/// ה-callbacks הנוכחיים של [_SmartTextWidgetFactory]; נקראים בלי תלות, כך
/// שהחלפתם לא בונה מחדש את העץ.
class _SmartTextCallbacks extends InheritedWidget {
  final void Function(String url, Offset globalPosition)? onAnchorHover;
  final void Function(String url)? onAnchorHoverExit;
  final void Function(String url)? onMiddleClickUrl;

  const _SmartTextCallbacks({
    required this.onAnchorHover,
    required this.onAnchorHoverExit,
    required this.onMiddleClickUrl,
    required super.child,
  });

  @override
  bool updateShouldNotify(_SmartTextCallbacks oldWidget) => false;

  @override
  InheritedElement createElement() => _TimedCallbacksElement(this);
}

/// מודד את בניית תת-העץ של HtmlWidget: פרסור, עץ fwfh וספאנים, בלי פריסה.
class _TimedCallbacksElement extends InheritedElement {
  _TimedCallbacksElement(super.widget);

  @override
  void performRebuild() {
    final start = SmartTextRenderStats.startMicros();
    super.performRebuild();
    SmartTextRenderStats.fwfhBuild(start);
  }
}

/// עיגון מחדש של הדגשות התוספים ותיעוד תוכן הקטע (#828) לשורה מוצגת.
/// [processedHtml] הוא התוצר של `processText`, לפני ציור ההדגשות.
void syncReaderSectionForPlugins({
  required String bookId,
  String? bookUid,
  int? bookDbId,
  String? bookType,
  String? bookSource,
  required int sectionIndex,
  required String rawSourceHtml,
  required String processedHtml,
  required Object renderingSignature,
}) {
  // ניקוי-HTML וגיבוב הם העלות הכבדה בפריים; מדלגים עליהם כשהקלט זהה
  // לפריים הקודם, וזה המצב בכמעט כל פריים גלילה.
  if (!ReaderSectionSyncGate.instance.claimSync(
    bookId: bookId,
    bookDbId: bookDbId,
    bookType: bookType,
    bookSource: bookSource,
    sectionIndex: sectionIndex,
    rawSourceHtml: rawSourceHtml,
    processedHtml: processedHtml,
    renderingSignature: renderingSignature,
    highlightsRevision: PluginHighlightRegistry.instance.revision,
  )) {
    return;
  }
  final sourceText = TextRendererService.stripHtml(rawSourceHtml);
  final renderedText = TextRendererService.stripHtml(processedHtml);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    PluginHighlightRegistry.instance.reanchorSection(
      bookId: bookId,
      sectionIndex: sectionIndex,
      sourceText: sourceText,
      bookUid: bookUid,
    );
    unawaited(
      _recordSectionContentSnapshot(
        bookId: bookId,
        bookDbId: bookDbId,
        bookType: bookType,
        bookSource: bookSource,
        sectionIndex: sectionIndex,
        sourceText: sourceText,
        renderedText: renderedText,
        renderingSignature: renderingSignature,
      ),
    );
  });
}

Future<void> _recordSectionContentSnapshot({
  required String bookId,
  int? bookDbId,
  String? bookType,
  String? bookSource,
  required int sectionIndex,
  required String sourceText,
  required String renderedText,
  required Object renderingSignature,
}) async {
  try {
    await ReaderSectionContentTracker.instance.recordSnapshot(
      bookId: bookId,
      bookDbId: bookDbId,
      bookType: bookType,
      bookSource: bookSource,
      sectionIndex: sectionIndex,
      sourceText: sourceText,
      renderedText: renderedText,
      renderingSignature: renderingSignature,
    );
  } catch (error, stackTrace) {
    // בלי ביטול הסימון הקטע היה נשאר "מסונכרן" לנצח ולא מנסה שוב.
    ReaderSectionSyncGate.instance.forget(
      bookId: bookId,
      sectionIndex: sectionIndex,
    );
    debugPrint('Failed to track reader section content: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
