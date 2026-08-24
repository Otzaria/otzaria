import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/utils/link_anchor_variants.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/exact_line_height.dart';
import 'package:otzaria/widgets/smart_text/raised_markers.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
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

  const SmartTextWidget({
    super.key,
    required this.text,
    required this.settings,
    this.onOpenBook,
    this.onNoteTap,
    this.onAnchorTap,
    this.onAnchorHover,
    this.onAnchorHoverExit,
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
      listenables.addAll([
        PluginHighlightRegistry.instance,
        PluginHighlightRevealService.instance,
      ]);
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
      listenable: Listenable.merge(listenables),
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
      final rawSourceHtml = highlightSourceText ?? text;
      final renderingSignature = settings.sectionContentRenderingSignature;
      // ניקוי-HTML וגיבוב הם העלות הכבדה בפריים; מדלגים עליהם כשהקלט זהה
      // לפריים הקודם, וזה המצב בכמעט כל פריים גלילה.
      if (ReaderSectionSyncGate.instance.claimSync(
        bookId: bookId,
        bookDbId: highlightBookDbId,
        bookType: highlightBookType,
        bookSource: highlightBookSource,
        sectionIndex: sectionIndex,
        rawSourceHtml: rawSourceHtml,
        processedHtml: processedHtml,
        renderingSignature: renderingSignature,
        highlightsRevision: PluginHighlightRegistry.instance.revision,
      )) {
        final sourceText = TextRendererService.stripHtml(rawSourceHtml);
        final renderedText = TextRendererService.stripHtml(processedHtml);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PluginHighlightRegistry.instance.reanchorSection(
            bookId: bookId,
            sectionIndex: sectionIndex,
            sourceText: sourceText,
            bookUid: highlightBookUid,
          );
          unawaited(
            _recordSectionContentSnapshot(
              bookId: bookId,
              bookDbId: highlightBookDbId,
              bookType: highlightBookType,
              bookSource: highlightBookSource,
              sectionIndex: sectionIndex,
              sourceText: sourceText,
              renderedText: renderedText,
              renderingSignature: renderingSignature,
            ),
          );
        });
      }
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
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontWeight: settings.fontWeight,
      fontVariations: AppFonts.boldFontVariations(
        settings.fontFamily,
        settings.fontWeight ?? FontWeight.normal,
      ),
      height: settings.lineHeight,
    );

    // מסלול מהיר: רוב השורות הן טקסט פשוט (או עם תגי עיצוב בסיסיים) —
    // רינדור ישיר ב-Text.rich חוסך את מלוא עלות הפרסור של HtmlWidget.
    // גם סימונים מורמים נתמכים כאן באופן בסיסי: SimpleInlineHtml מזהה את
    // שני תגי הסימון, והשכבה נעטפת בדיוק כמו במסלול ה-HtmlWidget.
    if (renderMode == RenderMode.column) {
      final simpleSpan = SimpleInlineHtml.tryParse(processedHtml, textStyle);
      if (simpleSpan != null) {
        if (simpleSpan.toPlainText().isEmpty) {
          return const SizedBox.shrink();
        }
        // רוחב מלא כמו <div> בלוק ב-HtmlWidget - אחרת מסכים שעוטפים שורה
        // ב-Center (הגבלת רוחב קריאה) ימרכזו שורות קצרות בטעות.
        return _withPluginFrames(
          frameRanges,
          _withRaisedMarkers(
            context,
            raisedMarkers,
            textStyle,
            SizedBox(
              key: widgetKey,
              width: double.infinity,
              child: Text.rich(
                simpleSpan,
                style: textStyle,
                strutStyle: exactLineHeightStrut(textStyle, simpleSpan),
                textAlign: settings.justifyText
                    ? TextAlign.justify
                    : TextAlign.right,
              ),
            ),
          ),
        );
      }
    }

    // סמן-מספר וטווח-ציטוט נשארים בשורה בצבע ה-primary; fwfh לא מכיר
    // inherit ולכן הערך מפורש. צבעי אותיות המפרשים המורמות נפתרים ב-wrap.
    final colorScheme = Theme.of(context).colorScheme;
    String toCssHex(Color color) =>
        '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
    final anchorLinkColorCss = toCssHex(colorScheme.primary);
    // מרקר-עילי נצבע בצבע הטקסט הסביבתי — fwfh צובע <a> ב-primary כברירת מחדל.
    final anchorColorCss = toCssHex(
      DefaultTextStyle.of(context).style.color ?? colorScheme.onSurface,
    );
    final markdownSurfaceCss = toCssHex(colorScheme.surfaceContainerHighest);
    final markdownBorderCss = toCssHex(colorScheme.outlineVariant);
    final hasMarkdownBlock = processedHtml.contains(kMarkdownBlockClass);

    return _withPluginFrames(
      frameRanges,
      _withRaisedMarkers(
        context,
        raisedMarkers,
        textStyle,
        HtmlWidget(
          TextRendererService.wrapWithRtlDiv(
            processedHtml,
            justifyText: settings.justifyText,
          ),
          key: widgetKey,
          renderMode: renderMode,
          textStyle: textStyle,
          // WidgetFactory מותאם לשתי מטרות: (1) בולד אמיתי לגופן משתנה — fwfh בונה
          // font-weight:bold בלי FontVariation, לכן מזריקים אותו לפי הגופן שנפתר.
          // (2) ריחוף על עוגני-מילה — fwfh לא חושף hover על <a>, לכן מזריקים
          // onEnter/onExit ל-TextSpan של כל עוגן, בלי לגעת בזרימת הטקסט.
          factoryBuilder: () => _SmartTextWidgetFactory(
            onAnchorHover: onAnchorHover,
            onAnchorHoverExit: onAnchorHoverExit,
          ),
          customStylesBuilder: (dom.Element element) {
            final headingWeight = AppFonts.headingFontWeightOverride(
              element.localName,
              settings.fontFamily,
            );
            if (element.localName == 'span' &&
                element.classes.contains('subscript-text')) {
              return {'font-size': 'smaller'};
            }
            // סימונים מורמים: הגליפים נשארים בשורה — תופסים את המקום ואת הסדר
            // הנכון, וזמינים לבחירה ולהעתקה — אבל שקופים, ו-RaisedMarkerOverlay
            // מצייר אותם מורמים מעל מקומם. `position`/`top` אינם נתמכים ב-fwfh
            // כלל (היו no-op גם קודם), ולכן הרמה בפריסה אינה אפשרית כאן.
            if (element.localName == 'span' &&
                element.classes.contains(kFootnoteMarkerClass)) {
              return {
                'font-size': '${kFootnoteMarkerScale}em',
                'font-style': 'italic',
                'color': 'transparent',
              };
            }
            if (element.localName == 'span' &&
                element.classes.contains(kRaisedSupClass)) {
              return {
                'font-size': '${kHtmlSmallerFontScale}em',
                'color': 'transparent',
              };
            }
            // מרקר מספרי שהומר לספרות-עיליות — הגליפים כבר מוגבהים ומוקטנים.
            if (element.localName == 'a' &&
                element.classes.contains('book-note-marker-sup')) {
              return {'color': anchorColorCss, 'text-decoration': 'none'};
            }
            // סימון הערה מוטמעת לחיץ: כמו מרקר הערה — הגליף שקוף ומורם בשכבה;
            // ה-recognizer והריחוף נשארים על הספאן, והשכבה מפנה אליו לחיצות.
            if (element.localName == 'a' &&
                element.classes.contains('book-note-marker')) {
              return {
                'font-size': '${kFootnoteMarkerScale}em',
                'font-style': 'italic',
                'color': 'transparent',
                'text-decoration': 'none',
              };
            }
            // סמן-מספר מודפס בגוף הספר, למשל (9): נשאר בגודלו ובמקומו — רק
            // נצבע בגוון הנושא כדי לרמז שאפשר לרחף עליו.
            if (element.localName == 'a' &&
                element.classes.contains('numbered-note-marker')) {
              return {'color': anchorLinkColorCss, 'text-decoration': 'none'};
            }
            // סמן-אות של מפרש (עוגן-נקודה): הגליף שקוף — הווריאנט הטיפוגרפי
            // נשאר עליו כדי שרוחב המקום בשורה יתאים לציור המורם, שנושא את
            // הצבע, הרקע הפעיל וההדגשה (ראו RaisedMarkerOverlay).
            if ((element.localName == 'span' || element.localName == 'a') &&
                element.classes.contains('link-anchor')) {
              final style = <String, String>{
                'font-size': '${kLinkAnchorMarkerScale}em',
                'white-space': 'nowrap',
                'color': 'transparent',
                'text-decoration': 'none',
                ...linkAnchorVariantCss(
                  linkAnchorVariantFromClasses(element.classes),
                ),
              };
              // אות פעילה מצוירת מודגשת — ההדגשה נשארת גם על הגליף השקוף כדי
              // שרוחבו יתאים; הרקע עבר לציור המורם.
              if (element.classes.contains('link-anchor-active')) {
                style['font-weight'] = 'bold';
              }
              return style;
            }
            // טווח-ציטוט (לינקר): צבע ה-primary בגופן הטקסט הסובב, בלי קו תחתון.
            // בלי וריאנט טיפוגרפי — הוא שייך לסמני-האות של המפרשים בלבד.
            if ((element.localName == 'span' || element.localName == 'a') &&
                element.classes.contains('link-anchor-range')) {
              return <String, String>{
                'text-decoration': 'none',
                'color': anchorLinkColorCss,
              };
            }
            if (!hasMarkdownBlock) {
              return headingWeight == null
                  ? null
                  : {'font-weight': headingWeight};
            }
            final markdownCss = _markdownElementCss(
              element,
              linkColorCss: anchorLinkColorCss,
              surfaceCss: markdownSurfaceCss,
              borderCss: markdownBorderCss,
            );
            if (headingWeight != null) {
              return {'font-weight': headingWeight, ...?markdownCss};
            }
            return markdownCss;
          },
          onTapUrl:
              (onOpenBook != null || onNoteTap != null || onAnchorTap != null)
              ? (url) async {
                  // עוגן-מילה — תצוגה מקדימה של המפרש, לפני שאר הקישורים.
                  if (url.startsWith('otzaria://anchor') &&
                      onAnchorTap != null) {
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
                }
              : null,
        ),
      ),
    );
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
class _SmartTextWidgetFactory extends WidgetFactory {
  final void Function(String url, Offset globalPosition)? onAnchorHover;
  final void Function(String url)? onAnchorHoverExit;
  final _previewHrefByRecognizer = <GestureRecognizer, String>{};

  _SmartTextWidgetFactory({this.onAnchorHover, this.onAnchorHoverExit});

  @override
  GestureRecognizer? buildGestureRecognizer(
    BuildTree tree, {
    GestureTapCallback? onTap,
  }) {
    final recognizer = super.buildGestureRecognizer(tree, onTap: onTap);
    final href = tree.element.attributes['href'];
    if (recognizer != null && href != null && isPreviewHoverableUrl(href)) {
      _previewHrefByRecognizer[recognizer] = href;
    }
    return recognizer;
  }

  /// ה-RichText של fwfh נבנה בלי strut ואין פרמטר להעביר אחד מבחוץ, לכן
  /// בונים מחדש את מה ש-fwfh בנה עם [exactLineHeightStrut]. מבנה אחר מהצפוי
  /// (גרסת fwfh חדשה) פשוט נשאר כפי שהוא — בלי קיבוע.
  @override
  Widget? buildText(
    BuildTree tree,
    InheritedProperties resolved,
    InlineSpan text,
  ) {
    final built = super.buildText(tree, resolved, text);
    final strutStyle = exactLineHeightStrut(resolved.prepareTextStyle(), text);
    if (strutStyle == null || built is! Builder) {
      return built;
    }

    return Builder(
      builder: (context) {
        final child = built.builder(context);
        if (child is RichText) {
          return _withStrutStyle(child, strutStyle);
        }
        if (child is MouseRegion && child.child is RichText) {
          return MouseRegion(
            onEnter: child.onEnter,
            onExit: child.onExit,
            onHover: child.onHover,
            cursor: child.cursor,
            opaque: child.opaque,
            hitTestBehavior: child.hitTestBehavior,
            child: _withStrutStyle(child.child! as RichText, strutStyle),
          );
        }
        return child;
      },
    );
  }

  static RichText _withStrutStyle(RichText source, StrutStyle strutStyle) {
    return RichText(
      key: source.key,
      text: source.text,
      textAlign: source.textAlign,
      textDirection: source.textDirection,
      softWrap: source.softWrap,
      overflow: source.overflow,
      textScaler: source.textScaler,
      maxLines: source.maxLines,
      locale: source.locale,
      strutStyle: strutStyle,
      textWidthBasis: source.textWidthBasis,
      textHeightBehavior: source.textHeightBehavior,
      selectionRegistrar: source.selectionRegistrar,
      selectionColor: source.selectionColor,
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
    if (onAnchorHover == null || href == null) {
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
      onEnter: (event) => onAnchorHover!(href, event.position),
      onExit: (_) => onAnchorHoverExit?.call(href),
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
    _previewHrefByRecognizer.clear();
    super.reset(state);
  }
}

/// גרסה פשוטה יותר של SmartTextWidget שמקבלת פרמטרים בודדים
/// במקום RenderSettings - נוחה למקרים פשוטים
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

class SimpleSmartText extends StatelessWidget {
  final String text;
  final double fontSize;
  final String? fontFamily;
  final bool removeNikud;
  final bool removeTeamim;
  final bool replaceHolyNames;
  final String searchText;
  final Function(OpenedTab)? onOpenBook;
  final Key? widgetKey;

  const SimpleSmartText({
    super.key,
    required this.text,
    required this.fontSize,
    this.fontFamily,
    this.removeNikud = false,
    this.removeTeamim = true,
    this.replaceHolyNames = false,
    this.searchText = '',
    this.onOpenBook,
    this.widgetKey,
  });

  @override
  Widget build(BuildContext context) {
    return SmartTextWidget(
      text: text,
      settings: RenderSettings(
        fontSize: fontSize,
        fontFamily: fontFamily,
        removeNikud: removeNikud,
        removeTeamim: removeTeamim,
        replaceHolyNames: replaceHolyNames,
        searchText: searchText,
      ),
      onOpenBook: onOpenBook,
      widgetKey: widgetKey,
    );
  }
}
