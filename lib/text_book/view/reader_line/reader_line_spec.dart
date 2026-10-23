/// הגדרת שורת מקור אחת לתצוגה, משותפת למסך העיון ולצורת הדף: אותם כללי
/// בחירה, הדגשה וחיפוש לשורה בודדת ולשורה שבתוך פסקה ממוזגת.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/plugins/services/plugin_highlight_reveal_service.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/theme/app_colors.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/file/markdown_to_otzaria.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

enum ReaderLineBackground { none, permanent, highlighted, related }

/// בחירה ורקע של שורה — תלויים במצב הספר בלבד.
@immutable
class ReaderLineMarks {
  const ReaderLineMarks({
    this.isSelected = false,
    this.background = ReaderLineBackground.none,
  });

  final bool isSelected;
  final ReaderLineBackground background;
}

/// [isRelated] — שורת מפרש שמודגשת כקשורה לשורה הנבחרת בטקסט הראשי.
ReaderLineMarks readerLineMarks(
  TextBookLoaded state,
  int lineIndex, {
  bool isMainText = true,
  bool isRelated = false,
}) {
  if (!isMainText) {
    return ReaderLineMarks(
      background: isRelated
          ? ReaderLineBackground.related
          : ReaderLineBackground.none,
    );
  }
  return ReaderLineMarks(
    isSelected: state.selectedIndices.contains(lineIndex),
    background: state.isPermanentHighlight(lineIndex)
        ? ReaderLineBackground.permanent
        : state.highlightedLine == lineIndex
        ? ReaderLineBackground.highlighted
        : ReaderLineBackground.none,
  );
}

Color? readerLineBackgroundColor(
  ReaderLineBackground background,
  ColorScheme colorScheme,
) => switch (background) {
  ReaderLineBackground.none => null,
  ReaderLineBackground.permanent => AppColors.permanentHighlight,
  ReaderLineBackground.highlighted => AppSurfaces.highlightedLineBackground(
    colorScheme,
  ),
  ReaderLineBackground.related => AppSurfaces.paragraphSelectionBackground(
    colorScheme,
  ),
};

final RegExp _blockMarkup = RegExp(
  r'<(?:details|table|img|ul|ol|pre|blockquote|hr|h[1-6])\b',
  caseSensitive: false,
);

/// מספר ניסיונות ההתאמה של [_blockMarkup]; נספר רק במצב debug.
int debugReaderBlockMarkupChecks = 0;

/// [_blockMarkup] אינו רגיש לרישיות, ולכן סריקתו על שורה שלמה איטית; מנסים
/// אותו רק במיקומי `<` שאחריהם אות פתיחה של אחד התגים.
bool _hasBlockMarkup(String line) {
  for (var i = line.indexOf('<'); i >= 0; i = line.indexOf('<', i + 1)) {
    if (i + 1 >= line.length) break;
    final initial = line.codeUnitAt(i + 1) | 0x20;
    if (!'bdhiotpu'.codeUnits.contains(initial)) continue;
    assert(() {
      debugReaderBlockMarkupChecks++;
      return true;
    }());
    if (_blockMarkup.matchAsPrefix(line, i) != null) return true;
  }
  return false;
}

final RegExp _leadingBlockElement = RegExp(
  r'^\s*<(?:div|p|center|li)\b',
  caseSensitive: false,
);

/// שורה שאינה ניתנת לייצוג כספאנים בתוך פסקה, ולכן מוצגת כבלוק משלה.
/// גם שורה ארוכה מאוד: כבלוק היא מוצגת במקטעים ([LongLineChunks]).
bool isReaderBlockLine(String rawLine) =>
    rawLine.length > kLongLineMinChars ||
    isAlignedBlockLine(rawLine) ||
    rawLine.contains(kMarkdownBlockClass) ||
    (rawLine.contains('<') &&
        (_hasBlockMarkup(rawLine) || _leadingBlockElement.hasMatch(rawLine)));

/// טקסט כותרות הנושא שמוצג בתוך פסקה ממוזגת לפני השורה שהן פותחות.
String? readerInlineHeading(List<String>? headings) =>
    headings == null || headings.isEmpty ? null : headings.join(' · ');

/// האם [line] מוצגת בתוך פסקה ממוזגת ולא כפריט או כבלוק משלה.
bool readerLineInParagraph(
  ReadingLayout layout,
  List<String> lines,
  int line,
) =>
    layout.continuous &&
    line >= 0 &&
    line < lines.length &&
    layout.lineCountOf(layout.itemForLine(line)) > 1 &&
    !isReaderBlockLine(lines[line]);

/// מבנה הפסקאות של חלון בחירה שמתחיל בשורה [baseIndex]; null במצב רגיל.
/// [splitsAfter] — שורה שאחריה הפסקה נחתכת (כרטיס מפרשים מתחתיה).
SelectionParagraphs? readerSelectionParagraphs({
  required ReadingLayout layout,
  required List<String> lines,
  required int baseIndex,
  Map<int, List<String>> sectionHeadings = const {},
  bool Function(int line)? splitsAfter,
}) {
  if (!layout.continuous) return null;
  return (
    joinsNext: (windowLine) {
      final line = baseIndex + windowLine;
      return readerLineInParagraph(layout, lines, line) &&
          readerLineInParagraph(layout, lines, line + 1) &&
          layout.itemForLine(line) == layout.itemForLine(line + 1) &&
          !(splitsAfter?.call(line) ?? false);
    },
    headingAt: (windowLine) {
      final line = baseIndex + windowLine;
      return readerLineInParagraph(layout, lines, line)
          ? readerInlineHeading(sectionHeadings[line])
          : null;
    },
  );
}

/// מה שמשתנה בין המסכים: מקור השורות, הזרקות ה-HTML שלהם וגופן הטור.
@immutable
class ReaderLineContext {
  const ReaderLineContext({
    required this.state,
    required this.lines,
    required this.profile,
    required this.lineHtml,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily,
    this.fontWeight,
    this.isMainText = true,
    this.sectionHeadings = const {},
    this.isRelated,
  });

  final TextBookLoaded state;
  final List<String> lines;
  final TextDisplayProfile profile;

  /// השורה עם כל ההזרקות של המסך (קישורים, סמנים, הערות), לפני `processText`.
  final String Function(int lineIndex) lineHtml;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final FontWeight? fontWeight;
  final bool isMainText;
  final Map<int, List<String>> sectionHeadings;
  final bool Function(int lineIndex)? isRelated;
}

@immutable
class ReaderLineSpec {
  const ReaderLineSpec({
    required this.lineIndex,
    required this.html,
    required this.sourceText,
    required this.settings,
    required this.marks,
    this.sectionHeadings,
  });

  final int lineIndex;

  /// הקלט של [SmartTextWidget] / `processText`.
  final String html;

  /// שורת המקור הגולמית — בסיס העיגון של הדגשות התוספים.
  final String sourceText;
  final RenderSettings settings;
  final ReaderLineMarks marks;

  /// נבדק רק בפריט של כמה שורות; בשורה בודדת אין לו משמעות.
  bool get isBlock => isReaderBlockLine(sourceText);
  final List<String>? sectionHeadings;
}

ReaderLineSpec buildReaderLineSpec(int lineIndex, ReaderLineContext ctx) {
  final state = ctx.state;
  final main = ctx.isMainText;
  final raw = ctx.lines[lineIndex];
  final yellow = main && state.isHighlightYellowBackground(lineIndex);
  final settings = RenderSettings.fromProfile(
    ctx.profile,
    searchText: !main
        ? ''
        : yellow
        ? state.highlightText
        : state.searchText,
    highlightYellowBackground: yellow,
    searchOptions: main ? state.searchOptions : const {},
    alternativeWords: main ? state.alternativeWords : const {},
    spacingValues: main ? state.spacingValues : const {},
    isFuzzySearch: main && state.searchMode == SearchMode.fuzzy,
    searchMode: main ? state.searchMode : SearchMode.exact,
    searchDistance: main ? state.searchDistance : 0,
    matchPolicy: main ? state.matchPolicy : SearchMatchPolicy.standard,
    partialWordHighlight:
        main &&
        literalPartialWordMatch(
          state.searchText,
          wholeWord: state.searchWholeWord,
        ),
    isSearchResultLine:
        main && state.lineParticipatesInSearchHighlight(lineIndex),
    previousLineText: main
        ? state.searchResultNeighbour(lineIndex, next: false)
        : null,
    nextLineText: main
        ? state.searchResultNeighbour(lineIndex, next: true)
        : null,
    fontSize: ctx.fontSize,
    fontFamily: ctx.fontFamily,
    fontWeight: ctx.fontWeight,
    lineHeight: ctx.lineHeight,
  );
  return ReaderLineSpec(
    lineIndex: lineIndex,
    html: ctx.lineHtml(lineIndex),
    sourceText: raw,
    settings: settings,
    marks: readerLineMarks(
      state,
      lineIndex,
      isMainText: main,
      isRelated: ctx.isRelated?.call(lineIndex) ?? false,
    ),
    sectionHeadings: ctx.sectionHeadings[lineIndex],
  );
}

/// הסגנון הבסיסי של פסקה ממוזגת — כמו של [SmartTextWidget] לשורה בודדת.
TextStyle readerParagraphBaseStyle(
  ReaderLineContext ctx,
  ColorScheme colorScheme,
) => TextStyle(
  fontSize: ctx.fontSize,
  fontFamily: AppFonts.renderFontFamily(ctx.fontFamily),
  fontWeight: ctx.fontWeight,
  fontVariations: AppFonts.boldFontVariations(
    ctx.fontFamily,
    ctx.fontWeight ?? FontWeight.normal,
  ),
  height: ctx.lineHeight,
  color: colorScheme.onSurface,
);

/// שורה בתוך פסקה ממוזגת: עיבוד, הדגשות תוספים וסנכרון התוכן לתוספים —
/// אותו מסלול ש-[SmartTextWidget] מריץ לשורה בודדת.
ContinuousReadingParagraphLine readerParagraphLine(
  ReaderLineSpec spec,
  ReaderLineContext ctx, {
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
}) {
  // אותו קלט כמו של SmartTextWidget, כדי שתיעוד התוכן לא ישתנה בהחלפת מצב.
  final processed = TextRendererService.processText(spec.html, spec.settings);
  var html = processed;
  var ranges = const <PluginHighlightRenderedRange>[];
  if (ctx.isMainText) {
    final book = ctx.state.book;
    final uid = PluginBookIdentity.uidOf(book);
    syncReaderSectionForPlugins(
      bookId: book.title,
      bookUid: uid,
      bookDbId: book.id,
      bookType: PluginBookIdentity.typeOf(book),
      bookSource: PluginBookIdentity.sourceOf(book),
      sectionIndex: spec.lineIndex,
      rawSourceHtml: spec.sourceText,
      processedHtml: processed,
      renderingSignature: spec.settings.sectionContentRenderingSignature,
    );
    final highlights = PluginHighlightRegistry.instance.getAllHighlights(
      bookId: book.title,
      sectionIndex: spec.lineIndex,
      bookUid: uid,
    );
    if (highlights.isNotEmpty) {
      final rendering = const PluginHighlightRenderer().renderWithRanges(
        bookId: book.title,
        sectionIndex: spec.lineIndex,
        rawText: spec.sourceText,
        processedHtml: processed,
        highlights: highlights,
        revealedHighlightId: PluginHighlightRevealService.instance.highlightId,
      );
      html = rendering.html;
      ranges = rendering.ranges;
    }
  }
  // רווח בקצוות השורה היה מכפיל את הרווח המחבר בפסקה.
  final leading = html.length - html.trimLeft().length;
  if (leading > 0 && ranges.isNotEmpty) {
    final shift = html.substring(0, leading).characters.length;
    ranges = [
      for (final range in ranges)
        PluginHighlightRenderedRange(
          start: (range.start - shift).clamp(0, range.start).toInt(),
          end: (range.end - shift).clamp(0, range.end).toInt(),
          highlight: range.highlight,
        ),
    ];
  }
  html = html.trim();
  return ContinuousReadingParagraphLine(
    lineIndex: spec.lineIndex,
    htmlText: html,
    style: AppFonts.taamimSafeStyle(baseStyle, html),
    frameRanges: ranges,
    background: readerLineBackgroundColor(spec.marks.background, colorScheme),
    selected: spec.marks.isSelected,
    heading: readerInlineHeading(spec.sectionHeadings),
  );
}

/// רצף שורות שמוצג כפסקה אחת. מאזין להדגשות התוספים ולתבנית החיפוש כמו
/// [SmartTextWidget].
class ReaderParagraphRun extends StatelessWidget {
  const ReaderParagraphRun({
    super.key,
    required this.specs,
    required this.lineContext,
    required this.onTapUrl,
    this.onMiddleClickUrl,
    this.onAnchorHover,
    this.onAnchorExit,
  });

  final List<ReaderLineSpec> specs;
  final ReaderLineContext lineContext;
  final ContinuousReadingUrlTap onTapUrl;
  final void Function(String url)? onMiddleClickUrl;
  final ContinuousReadingAnchorHover? onAnchorHover;
  final ContinuousReadingAnchorExit? onAnchorExit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = readerParagraphBaseStyle(lineContext, colorScheme);
    final hasSearch = specs.any((spec) => spec.settings.searchText.isNotEmpty);
    return ListenableBuilder(
      listenable: Listenable.merge([
        PluginHighlightRegistry.instance,
        PluginHighlightRevealService.instance,
        if (hasSearch) utils.highlightPatternRevision,
      ]),
      builder: (context, _) => ContinuousReadingParagraph(
        lines: [
          for (final spec in specs)
            readerParagraphLine(
              spec,
              lineContext,
              baseStyle: baseStyle,
              colorScheme: colorScheme,
            ),
        ],
        baseStyle: baseStyle,
        // אותו עיצוב קישורים כמו במצב הרגיל (HtmlWidget).
        linkStyle: TextStyle(
          color: AppSurfaces.readerLink(colorScheme),
          decoration: TextDecoration.underline,
        ),
        anchorActiveBackground: colorScheme.primaryContainer,
        headingColor: colorScheme.onSurfaceVariant,
        textAlign: specs.isEmpty || specs.first.settings.justifyText
            ? TextAlign.justify
            : TextAlign.right,
        onTapUrl: onTapUrl,
        onMiddleClickUrl: onMiddleClickUrl,
        onAnchorHover: onAnchorHover,
        onAnchorExit: onAnchorExit,
      ),
    );
  }
}

/// חלקי פריט של כמה שורות: רצפי שורות שמוזגו לפסקה, ושורות שמוצגות כבלוק.
/// [splitAfter] — שורה שאחריה הפסקה נחתכת (כרטיס המפרשים, issue #875).
List<({List<int> lines, bool isBlock})> readerItemParts(
  List<int> lineIndices,
  bool Function(int lineIndex) isBlock, {
  int? splitAfter,
}) {
  final parts = <({List<int> lines, bool isBlock})>[];
  var run = <int>[];
  void flush() {
    if (run.isEmpty) return;
    parts.add((lines: run, isBlock: false));
    run = <int>[];
  }

  for (final line in lineIndices) {
    if (isBlock(line)) {
      flush();
      parts.add((lines: [line], isBlock: true));
    } else {
      run.add(line);
    }
    if (line == splitAfter) flush();
  }
  flush();
  return parts;
}
