import 'dart:collection';

import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/utils/copy_guard.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reader_plugin_menu_entries.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// טיוטה מהבחירה בטקסט הראשי, או null כשאי אפשר לעגן בוודאות. כל פסקה
/// מאותרת בטקסט המוצג בלי תלות ברווחים, וממופה לטקסט המקור.
MarkerDraft? markerDraftFromSelection({
  required TextBookLoaded state,
  required List<String> lines,
  required int paragraphIndex,
  required String selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings settings,
}) => markerDraftFor(
  book: state.book,
  bookUid: markerBookUidOf(state.book),
  protection: state.protection,
  ref: state.currentTitle,
  lines: lines,
  paragraphIndex: paragraphIndex,
  selectedText: selectedText,
  anchor: anchor,
  settings: settings,
);

/// שורות ספר שבהן ידועה רק שורה [index], כמו בקטע מפרש בודד ברשימה.
List<String> markerSingleLine(int index, String line) =>
    markerKnownLines({index: line});

/// שורות ספר שבהן ידועות רק השורות של [known] (אינדקס ← תוכן), כמו בקטע
/// מפרש של כמה שורות ברשימה. שאר השורות ריקות.
List<String> markerKnownLines(Map<int, String> known) => _KnownLines(known);

class _KnownLines extends ListBase<String> {
  _KnownLines(this.known)
    : length = known.isEmpty
          ? 0
          : known.keys.reduce((a, b) => a > b ? a : b) + 1;

  final Map<int, String> known;

  @override
  final int length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  String operator [](int i) => known[i] ?? '';

  @override
  void operator []=(int i, String value) => throw UnsupportedError('read-only');
}

/// כמו [markerDraftFromSelection], לכל ספר — גם למפרש שמוצג לצד הספר.
/// [lines] הן שורות הספר הזה, ו-[ref] מראה המקום שיוצג ברשימה.
MarkerDraft? markerDraftFor({
  required TextBook book,
  required String? bookUid,
  required BookProtection protection,
  required String? ref,
  required List<String> lines,
  required int paragraphIndex,
  required String selectedText,
  required ReaderSelectionAnchor anchor,
  required RenderSettings settings,
}) {
  const service = ReaderSelectionService();
  // הסימון שומר את הטקסט ומציג אותו ברשימה, ולכן כפוף למגבלת ההעתקה.
  final text = limitTextToCopySegments(protection, selectedText).trim();
  if (text.isEmpty || lines.isEmpty) return null;
  final lineStart = anchor.lineStart;
  var lineEnd = anchor.lineEnd;
  final maxSegments = protection.maxCopySegments;
  if (maxSegments != null &&
      lineStart != null &&
      lineEnd != null &&
      lineEnd - lineStart >= maxSegments) {
    lineEnd = lineStart + maxSegments - 1;
  }

  MarkerSegment? segmentFor(int sectionIndex, String piece, int? startHint) {
    final selection = service.buildFromRenderedSelection(
      bookId: book.title,
      bookTitle: book.title,
      sectionIndex: sectionIndex,
      rawText: lines[sectionIndex],
      settings: settings,
      selectedText: piece,
      startHint: startHint,
    );
    final range = selection?.sourceRange;
    if (range == null || range.exactText.trim().isEmpty) return null;
    return MarkerSegment(sectionIndex: sectionIndex, range: range);
  }

  final segments = <MarkerSegment>[];
  if (lineStart != null &&
      lineEnd != null &&
      lineEnd > lineStart &&
      lineStart >= 0 &&
      lineEnd < lines.length) {
    final rendered = [
      for (var i = lineStart; i <= lineEnd; i++)
        renderSelectionLine(rawText: lines[i], settings: settings),
    ];
    final ranges = locateSelectionRangesPerLine(
      selectedText: text,
      visibleLines: rendered,
      startColumnHint: anchor.startColumn,
    );
    if (ranges == null) return null;
    for (final range in ranges) {
      final piece = rendered[range.line].substring(range.start, range.end);
      if (piece.trim().isEmpty) continue;
      final segment = segmentFor(lineStart + range.line, piece, range.start);
      // פסקה שאי אפשר לעגן מפילה את כל הסימון: חלק חסר היה מטעה.
      if (segment == null) return null;
      segments.add(segment);
    }
  } else {
    final sectionIndex =
        lineStart != null && lineStart >= 0 && lineStart < lines.length
        ? lineStart
        : paragraphIndex;
    if (sectionIndex < 0 || sectionIndex >= lines.length) return null;
    final segment = segmentFor(
      sectionIndex,
      text,
      anchor.startColumn ??
          (sectionIndex == paragraphIndex ? anchor.pointerColumn : null),
    );
    if (segment != null) segments.add(segment);
  }
  if (segments.isEmpty) return null;
  return MarkerDraft(
    bookTitle: book.title,
    bookUid: bookUid,
    segments: segments,
    text: text.replaceAll(RegExp(r'\s+'), ' '),
    ref: ref,
  );
}
