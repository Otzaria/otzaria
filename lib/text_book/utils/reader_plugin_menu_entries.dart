import 'package:flutter/widgets.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/utils/highlight_click_resolver.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// Where the reader's current selection sits in the book's lines.
typedef ReaderSelectionAnchor = ({
  int? lineStart,
  int? lineEnd,
  int? startColumn,
  int? pointerColumn,
});

/// The selection payload that plugins receive for a selection in the main
/// text of a reader view, whose lines are [lines].
///
/// A selection over several paragraphs gets one anchor per paragraph. A
/// selection within one paragraph is anchored in the paragraph where it
/// starts, not in [paragraphIndex] where the user clicked; otherwise a phrase
/// that also appears in the clicked paragraph would take the anchor.
Map<String, dynamic> buildReaderSelectionPayload({
  required TextBookLoaded state,
  required List<String> lines,
  required int paragraphIndex,
  required String selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings settings,
}) {
  const selectionService = ReaderSelectionService();
  final book = state.book;
  final lineStart = anchor.lineStart;
  var lineEnd = anchor.lineEnd;
  // תוסף מקבל מבחירה בספר מוגן רק את מה שמותר להעתיק.
  selectedText = limitTextToCopySegments(state.protection, selectedText);
  final maxSegments = state.protection.maxCopySegments;
  if (maxSegments != null &&
      lineStart != null &&
      lineEnd != null &&
      lineEnd - lineStart >= maxSegments) {
    lineEnd = lineStart + maxSegments - 1;
  }
  if (lineStart != null &&
      lineEnd != null &&
      lineEnd > lineStart &&
      lineStart >= 0 &&
      lineEnd < lines.length) {
    final rawTexts = [for (var i = lineStart; i <= lineEnd; i++) lines[i]];
    final renderedLines = [
      for (final raw in rawTexts)
        renderSelectionLine(rawText: raw, settings: settings),
    ];
    return selectionService.buildMultiSectionPayload(
      bookId: book.title,
      bookTitle: book.title,
      firstSectionIndex: lineStart,
      rawTexts: rawTexts,
      lineRanges:
          locateSelectionRangesPerLine(
            selectedText: selectedText,
            visibleLines: renderedLines,
            startColumnHint: anchor.startColumn,
          ) ??
          const [],
      settings: settings,
      selectedText: selectedText,
      currentRef: state.currentTitle,
      bookDbId: book.id,
      bookType: PluginBookIdentity.typeOf(book),
      bookSource: PluginBookIdentity.sourceOf(book),
    );
  }

  final sectionIndex =
      (lineStart != null && lineStart >= 0 && lineStart < lines.length)
      ? lineStart
      : paragraphIndex;
  final renderedLine = renderSelectionLine(
    rawText: lines[sectionIndex],
    settings: settings,
  );
  final localRange = selectionService.locateRenderedRange(
    renderedText: renderedLine,
    selectedText: selectedText,
    startHint:
        anchor.startColumn ??
        (sectionIndex == paragraphIndex ? anchor.pointerColumn : null),
  );
  return selectionService.buildPayload(
    bookId: book.title,
    bookTitle: book.title,
    sectionIndex: sectionIndex,
    rawText: lines[sectionIndex],
    settings: settings,
    selectedText: selectedText,
    renderedStartUtf16: localRange?.start,
    renderedEndUtf16: localRange?.end,
    currentRef: state.currentTitle,
    bookDbId: book.id,
    bookType: PluginBookIdentity.typeOf(book),
    bookSource: PluginBookIdentity.sourceOf(book),
    bookUid: PluginBookIdentity.uidOf(book),
  );
}

Map<String, dynamic> buildReaderBookPayload({
  required TextBookLoaded state,
  required int paragraphIndex,
}) => {
  ...PluginBookIdentity.toJsonWithUid(state.book),
  'bookTitle': state.book.title,
  'currentBook': state.book.title,
  'currentBookId': state.book.title,
  'sectionIndex': paragraphIndex,
  'currentIndex': paragraphIndex,
  'currentRef': state.currentTitle,
  'text': '',
  'start': null,
  'end': null,
};

/// Plugin entries for the `reader-highlight` context: a right click on
/// highlighted text with no active selection. Empty unless the click at
/// [tapPosition] falls on a highlight in paragraph [paragraphIndex].
List<AppContextMenuEntry> buildClickedHighlightPluginEntries({
  required RenderObject? root,
  required TextBookLoaded state,
  required String rawText,
  required int paragraphIndex,
  required Offset tapPosition,
  required RenderSettings settings,
  required List<(String, PluginContextMenuItem)> pluginItems,
  required BuildContext menuContext,
}) {
  if (root == null) return const [];
  final book = state.book;
  final clicked = resolveClickedHighlights(
    root: root,
    globalPosition: tapPosition,
    bookId: book.title,
    bookUid: PluginBookIdentity.uidOf(book),
    sectionIndex: paragraphIndex,
    rawText: rawText,
    settings: settings,
  );
  if (clicked.isEmpty) return const [];
  final entries = buildPluginContextMenuEntries(
    records: pluginItems,
    selection: buildClickedHighlightsPayload(
      highlights: clicked,
      bookId: book.title,
      bookTitle: book.title,
      sectionIndex: paragraphIndex,
      currentRef: state.currentTitle,
      bookDbId: book.id,
      bookType: PluginBookIdentity.typeOf(book),
      bookSource: PluginBookIdentity.sourceOf(book),
      bookUid: PluginBookIdentity.uidOf(book),
    ),
    context: 'reader-highlight',
    selectionActionDispatcher: pluginSelectionActionDispatcherOf(menuContext),
  );
  if (entries.isEmpty) return const [];
  return [const AppContextMenuEntry.divider(), ...entries];
}

List<AppContextMenuEntry> buildReaderPluginMenuEntries({
  required RenderObject? root,
  required TextBookLoaded state,
  required List<String> lines,
  required int paragraphIndex,
  required bool hasSelection,
  required String? selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings Function() settings,
  required Offset tapPosition,
  required BuildContext menuContext,
  String selectionContext = 'reader-selection',
  List<(String, PluginContextMenuItem)>? pluginItems,
}) {
  final items = pluginItems ?? ContextMenuRegistry.instance.getAll();
  if (items.isEmpty || paragraphIndex < 0 || paragraphIndex >= lines.length) {
    return const [];
  }
  final renderSettings = settings();
  if (!hasSelection) {
    final bookEntries = buildPluginContextMenuEntries(
      records: items,
      selection: buildReaderBookPayload(
        state: state,
        paragraphIndex: paragraphIndex,
      ),
      context: 'reader-book',
      selectionActionDispatcher: pluginSelectionActionDispatcherOf(menuContext),
    );
    final highlightEntries = buildClickedHighlightPluginEntries(
      root: root,
      state: state,
      rawText: lines[paragraphIndex],
      paragraphIndex: paragraphIndex,
      tapPosition: tapPosition,
      settings: renderSettings,
      pluginItems: items,
      menuContext: menuContext,
    );
    return [
      if (bookEntries.isNotEmpty) const AppContextMenuEntry.divider(),
      ...bookEntries,
      ...highlightEntries,
    ];
  }
  final selection = buildReaderSelectionPayload(
    state: state,
    lines: lines,
    paragraphIndex: paragraphIndex,
    selectedText: selectedText ?? '',
    anchor: anchor,
    settings: renderSettings,
  );
  return [
    const AppContextMenuEntry.divider(),
    ...buildPluginContextMenuEntries(
      records: items,
      selection: selection,
      context: selectionContext,
      selectionActionDispatcher: pluginSelectionActionDispatcherOf(menuContext),
    ),
  ];
}
