import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// בונה payload של בחירה בפסקה יחידה לתוסף, בדיוק כמו תפריט הלחיצה הימנית.
Map<String, dynamic> buildPluginSelectionPayload({
  required TextBookLoaded state,
  required String rawText,
  required String selectedText,
  required int sectionIndex,
  required int? startHint,
  required RenderSettings settings,
}) {
  const selectionService = ReaderSelectionService();
  final renderedLine = renderSelectionLine(
    rawText: rawText,
    settings: settings,
  );
  final localRange = selectionService.locateRenderedRange(
    renderedText: renderedLine,
    selectedText: selectedText,
    startHint: startHint,
  );
  return selectionService.buildPayload(
    bookId: state.book.title,
    bookTitle: state.book.title,
    sectionIndex: sectionIndex,
    rawText: rawText,
    settings: settings,
    selectedText: selectedText,
    renderedStartUtf16: localRange?.start,
    renderedEndUtf16: localRange?.end,
    currentRef: state.currentTitle,
    bookDbId: state.book.id,
    bookType: PluginBookIdentity.typeOf(state.book),
    bookSource: PluginBookIdentity.sourceOf(state.book),
  );
}

/// בונה payload לבחירה חוצת-פסקאות, עם עוגן וטווח עבור כל פסקה.
Map<String, dynamic> buildPluginMultiSectionSelectionPayload({
  required TextBookLoaded state,
  required List<String> rawTexts,
  required String selectedText,
  required int firstSectionIndex,
  required int? startHint,
  required RenderSettings settings,
}) {
  const selectionService = ReaderSelectionService();
  final renderedLines = [
    for (final rawText in rawTexts)
      renderSelectionLine(rawText: rawText, settings: settings),
  ];
  return selectionService.buildMultiSectionPayload(
    bookId: state.book.title,
    bookTitle: state.book.title,
    firstSectionIndex: firstSectionIndex,
    rawTexts: rawTexts,
    lineRanges:
        locateSelectionRangesPerLine(
          selectedText: selectedText,
          visibleLines: renderedLines,
          startColumnHint: startHint,
        ) ??
        const [],
    settings: settings,
    selectedText: selectedText,
    currentRef: state.currentTitle,
    bookDbId: state.book.id,
    bookType: PluginBookIdentity.typeOf(state.book),
    bookSource: PluginBookIdentity.sourceOf(state.book),
  );
}
