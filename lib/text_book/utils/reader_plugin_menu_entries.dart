import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/plugins/models/plugin_context_menu_item.dart';
import 'package:otzaria/plugins/utils/highlight_click_resolver.dart';
import 'package:otzaria/plugins/utils/plugin_context_menu_entries.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_divine_names_filter.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/selection/plugin_selection_payload.dart';
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
  final (payload, markedLineOf) = _anchorReaderSelection(
    state: state,
    lines: lines,
    paragraphIndex: paragraphIndex,
    selectedText: selectedText,
    anchor: anchor,
    settings: settings,
  );
  return withReaderSelectionDivineNames(
    payload,
    state: state,
    settings: settings,
    markedLineOf: markedLineOf,
  );
}

/// הבחירה מעוגנת מול [settings], בלי הנספח, ושורות הפסקאות עם סמני השמות.
(Map<String, dynamic>, String Function(int sectionIndex))
_anchorReaderSelection({
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
    final rawTexts = [
      for (var i = lineStart; i <= lineEnd; i++)
        readerLineWithDivineNames(state, lines[i], i),
    ];
    final renderedLines = [
      for (final raw in rawTexts)
        renderSelectionLine(rawText: raw, settings: settings),
    ];
    final payload = selectionService.buildMultiSectionPayload(
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
    return (payload, (sectionIndex) => rawTexts[sectionIndex - lineStart]);
  }

  final sectionIndex =
      (lineStart != null && lineStart >= 0 && lineStart < lines.length)
      ? lineStart
      : paragraphIndex;
  final markedLine = readerLineWithDivineNames(
    state,
    lines[sectionIndex],
    sectionIndex,
  );
  final renderedLine = renderSelectionLine(
    rawText: markedLine,
    settings: settings,
  );
  final localRange = selectionService.locateRenderedRange(
    renderedText: renderedLine,
    selectedText: selectedText,
    startHint:
        anchor.startColumn ??
        (sectionIndex == paragraphIndex ? anchor.pointerColumn : null),
  );
  final payload = selectionService.buildPayload(
    bookId: book.title,
    bookTitle: book.title,
    sectionIndex: sectionIndex,
    rawText: markedLine,
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
  return (payload, (_) => markedLine);
}

/// [payload] של `reader.selection_changed` עם נספח שמוסר את הטקסט לפי הגדרת
/// השמות העדכנית או כפי שנשמר; מחושב רק במסירה.
Map<String, dynamic> withSelectionEventDivineNames(
  Map<String, dynamic> payload, {
  required TextBookLoaded state,
  required List<String> lines,
  required int paragraphIndex,
  required ReaderSelectionAnchor anchor,
  required RenderSettings settings,
}) => PluginDivineNamesPayload(
  () =>
      PluginDivineNamesDisplay.of(PluginDivineNamesFilter.readerProfile(state)),
  (payload, names) {
    if (names == PluginDivineNamesDisplay.ofSettings(settings)) {
      final text = withoutDivineNameJoiners(payload['text'] as String);
      return {
        ...payload,
        'text': text,
        if (payload.containsKey('renderedSelectedText'))
          'renderedSelectedText': text,
      };
    }
    // האירוע מוסר רק את הטקסט — בלי normalizedSelectedText ובלי נספח שני.
    final (anchored, markedLineOf) = _anchorReaderSelection(
      state: state,
      lines: lines,
      paragraphIndex: paragraphIndex,
      selectedText: payload['text'] as String,
      anchor: anchor,
      settings: settings,
    );
    final selection = const ReaderSelectionService().withDivineNames(
      anchored,
      names: names,
      settings: settings,
      rawTextOf: markedLineOf,
      includeNormalized: false,
    );
    final text = selection['text'] as String;
    return {
      ...payload,
      'text': text,
      if (payload.containsKey('renderedSelectedText'))
        'renderedSelectedText': selection['renderedSelectedText'] ?? text,
    };
  },
).attachTo(payload);

String? readerBookTabId(OpenedTab? tab, TextBookLoaded state) {
  if (tab == null) return null;
  if (tab is TextBookTab) {
    return PluginCorrectionSessionService.tabIdFor(tab);
  }
  for (final pane in leafPanes(tab).whereType<TextBookTab>()) {
    if (identical(pane.bloc.state, state)) {
      return PluginCorrectionSessionService.tabIdFor(pane);
    }
  }
  return null;
}

Map<String, dynamic> buildReaderBookPayload({
  required TextBookLoaded state,
  required int paragraphIndex,
  String? tabId,
}) => pluginMenuPayload(
  identity: {
    ...PluginBookIdentity.toJsonWithUid(state.book),
    'tabId': ?tabId,
  },
  bookTitle: state.book.title,
  sectionIndex: paragraphIndex,
  currentRef: state.currentTitle,
);

/// Payload for the `reader-highlight` context: a right click on highlighted
/// text with no active selection. Null unless the click at
/// [tapPosition] falls on a highlight in paragraph [paragraphIndex].
Map<String, dynamic>? _clickedHighlightPluginPayload({
  required RenderObject? root,
  required TextBookLoaded state,
  required String rawText,
  required int paragraphIndex,
  required Offset tapPosition,
  required RenderSettings settings,
  TextRange? lineRange,
}) {
  if (root == null) return null;
  final book = state.book;
  final clicked = resolveClickedHighlights(
    root: root,
    globalPosition: tapPosition,
    bookId: book.title,
    bookUid: PluginBookIdentity.uidOf(book),
    sectionIndex: paragraphIndex,
    rawText: rawText,
    settings: settings,
    lineRange: lineRange,
  );
  if (clicked.isEmpty) return null;
  return buildClickedHighlightsPayload(
    highlights: clicked,
    bookId: book.title,
    bookTitle: book.title,
    sectionIndex: paragraphIndex,
    currentRef: state.currentTitle,
    bookDbId: book.id,
    bookType: PluginBookIdentity.typeOf(book),
    bookSource: PluginBookIdentity.sourceOf(book),
    bookUid: PluginBookIdentity.uidOf(book),
  );
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
  TextRange? lineRange,
  String? tabId,
}) {
  final items = pluginItems ?? ContextMenuRegistry.instance.getAll();
  if (items.isEmpty || paragraphIndex < 0 || paragraphIndex >= lines.length) {
    return const [];
  }
  final renderSettings = settings();
  if (!hasSelection) {
    final highlight = _clickedHighlightPluginPayload(
      root: root,
      state: state,
      rawText: lines[paragraphIndex],
      paragraphIndex: paragraphIndex,
      tapPosition: tapPosition,
      settings: renderSettings,
      lineRange: lineRange,
    );
    final entries = buildPluginContextMenuEntries(
      viewId: View.of(menuContext).viewId,
      windowKeys: AppWindowKeys.of(menuContext),
      records: items,
      selection: buildReaderBookPayload(
        state: state,
        paragraphIndex: paragraphIndex,
        tabId: tabId,
      ),
      context: 'reader-book',
      additionalSection: highlight == null
          ? null
          : (context: 'reader-highlight', selection: highlight),
      selectionActionDispatcher: pluginSelectionActionDispatcherOf(
        menuContext,
      ),
    );
    return entries.isEmpty
        ? const []
        : [const AppContextMenuEntry.divider(), ...entries];
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
      viewId: View.of(menuContext).viewId,
      windowKeys: AppWindowKeys.of(menuContext),
      records: items,
      selection: selection,
      context: selectionContext,
      selectionActionDispatcher: pluginSelectionActionDispatcherOf(menuContext),
    ),
  ];
}
