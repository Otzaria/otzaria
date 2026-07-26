import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/plugins/services/reader_section_content_tracker.dart';
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
  /// כשמסופק, סמני העוגן מרונדרים כווידג'ט inline (ל-fwfh אין hover על <a>).
  final void Function(String url, Offset globalPosition)? onAnchorHover;

  /// callback ליציאת הסמן מעוגן-מילה.
  final void Function(String url)? onAnchorHoverExit;

  /// מפתח ייחודי לווידג'ט (לאופטימיזציה)
  final Key? widgetKey;

  /// מצב רינדור של HtmlWidget
  final RenderMode renderMode;

  /// כאשר שניהם מסופקים, הווידג'ט מצייר Highlights זמניים של תוספים.
  final String? highlightBookId;
  final int? highlightSectionIndex;
  final String? highlightSourceText;

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
    this.highlightSectionIndex,
    this.highlightSourceText,
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
      final sourceText = TextRendererService.stripHtml(
        highlightSourceText ?? text,
      );
      final renderedText = TextRendererService.stripHtml(processedHtml);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PluginHighlightRegistry.instance.reanchorSection(
          bookId: bookId,
          sectionIndex: sectionIndex,
          sourceText: sourceText,
        );
        unawaited(
          _recordSectionContentSnapshot(
            bookId: bookId,
            sectionIndex: sectionIndex,
            sourceText: sourceText,
            renderedText: renderedText,
            renderingSignature: settings.sectionContentRenderingSignature,
          ),
        );
      });
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
          SizedBox(
            key: widgetKey,
            width: double.infinity,
            child: Text.rich(
              simpleSpan,
              style: textStyle,
              textAlign: settings.justifyText
                  ? TextAlign.justify
                  : TextAlign.right,
            ),
          ),
        );
      }
    }

    // עוגן-מילה נפלט כ-<a> לחיץ; fwfh צובע <a> בצבע primary. מחזירים לצבע
    // הטקסט הסביבתי בערך מפורש (inherit לא נתמך בפרסר הצבעים של fwfh).
    final colorScheme = Theme.of(context).colorScheme;
    String toCssHex(Color color) =>
        '#${(color.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
    final anchorColorCss = toCssHex(
      DefaultTextStyle.of(context).style.color ?? colorScheme.onSurface,
    );
    final anchorLinkColorCss = toCssHex(colorScheme.primary);
    final anchorActiveBgCss = toCssHex(colorScheme.primaryContainer);

    return _withPluginFrames(
      frameRanges,
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
          if (element.localName == 'span' &&
              element.classes.contains('footnote-marker-number')) {
            return {
              'font-size': '0.75em',
              'font-style': 'italic',
              'position': 'relative',
              'top': '-0.55em',
            };
          }
          if (element.localName == 'a' &&
              element.classes.contains('book-note-marker')) {
            return {
              'font-size': '0.75em',
              'font-style': 'italic',
              'position': 'relative',
              'top': '-0.55em',
              'color': anchorColorCss,
              'text-decoration': 'none',
            };
          }
          // סמן-מספר מודפס בגוף הספר, למשל (9): נשאר בגודלו ובמקומו — רק
          // נצבע בגוון הנושא כדי לרמז שאפשר לרחף עליו.
          if (element.localName == 'a' &&
              element.classes.contains('numbered-note-marker')) {
            return {
              'color': anchorLinkColorCss,
              'text-decoration': 'none',
            };
          }
          // סמן-אות של מפרש (עוגן-נקודה): אות קטנה מורמת בצבע ה-primary, עם
          // וריאנט טיפוגרפי קבוע לכל מפרש (ראו anchorStyleIndexByCommentator).
          if ((element.localName == 'span' || element.localName == 'a') &&
              element.classes.contains('link-anchor')) {
            final style = <String, String>{
              'font-size': '0.7em',
              'position': 'relative',
              'top': '-0.55em',
              'white-space': 'nowrap',
              'color': anchorLinkColorCss,
              'text-decoration': 'none',
              ..._linkAnchorVariantStyle(element),
            };
            // האות שחלונית התצוגה שלה פתוחה — מודגשת (רקע + מודגש).
            if (element.classes.contains('link-anchor-active')) {
              style['background-color'] = anchorActiveBgCss;
              style['font-weight'] = 'bold';
            }
            return style;
          }
          // טווח-ציטוט (לינקר): קו תחתון בצבע ה-primary, בגופן הטקסט הסובב.
          // בלי וריאנט טיפוגרפי — הוא שייך לסמני-האות של המפרשים בלבד.
          if ((element.localName == 'span' || element.localName == 'a') &&
              element.classes.contains('link-anchor-range')) {
            return <String, String>{
              'text-decoration': 'underline',
              'color': anchorLinkColorCss,
            };
          }
          return null;
        },
        onTapUrl:
            (onOpenBook != null || onNoteTap != null || onAnchorTap != null)
            ? (url) async {
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
              }
            : null,
      ),
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

/// WidgetFactory ל-fwfh עם שתי אחריות:
/// 1. בולד אמיתי לגופן משתנה — מזריק FontVariation('wght') לספאנים מודגשים.
/// 2. ריחוף על עוגני-מילה — fwfh בונה recognizer לכל `<a>`; זוכרים אילו
///    recognizers שייכים ל-href של עוגן, וכשה-TextSpan נבנה מזריקים
///    onEnter/onExit לצד ה-recognizer הקיים.
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

/// הווריאנט הטיפוגרפי של סמן-אות (עוגן-נקודה) לפי המחלקה שהוקצתה למפרש.
Map<String, String> _linkAnchorVariantStyle(dom.Element element) {
  if (element.classes.contains('link-anchor-0')) {
    return const {'font-weight': 'bold'};
  }
  if (element.classes.contains('link-anchor-1')) {
    return const {'font-style': 'italic'};
  }
  if (element.classes.contains('link-anchor-2')) {
    return const {'font-weight': 'bold', 'font-style': 'italic'};
  }
  if (element.classes.contains('link-anchor-3')) {
    return const {'font-family': 'NotoRashiHebrew'};
  }
  if (element.classes.contains('link-anchor-4')) {
    return const {'font-family': 'NotoRashiHebrew', 'font-weight': 'bold'};
  }
  if (element.classes.contains('link-anchor-5')) {
    return const {'text-decoration': 'underline'};
  }
  return const {};
}

/// גרסה פשוטה יותר של SmartTextWidget שמקבלת פרמטרים בודדים
/// במקום RenderSettings - נוחה למקרים פשוטים
Future<void> _recordSectionContentSnapshot({
  required String bookId,
  required int sectionIndex,
  required String sourceText,
  required String renderedText,
  required Object renderingSignature,
}) async {
  try {
    await ReaderSectionContentTracker.instance.recordSnapshot(
      bookId: bookId,
      sectionIndex: sectionIndex,
      sourceText: sourceText,
      renderedText: renderedText,
      renderingSignature: renderingSignature,
    );
  } catch (error, stackTrace) {
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
