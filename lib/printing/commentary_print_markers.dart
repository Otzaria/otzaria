import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';

/// משחזר הערות ושמות לפני הוספת ציוני המפרשים שנכללים בפלט.
String withPrintCommentaryMarkers({
  required String rawLine,
  required int lineIndex,
  required List<Link> printedLinks,
  required BookNotes notes,
  required DivineNameSpans names,
}) {
  final lineNotes = notes.notesAt(lineIndex);
  final anchors = <Link>[];
  for (final link in printedLinks) {
    if (link.index1 != lineIndex + 1) continue;
    if (lineNotes.any((note) => note.charPos < 0)) continue;
    final points = [
      for (final span in linkAnchorSpans(link))
        if (span.start >= 0 && span.end == null)
          LinkAnchorSpan(
            start: link.anchorOffsetsAreRaw
                ? _fullLineOffset(rawLine, span.start, lineNotes)
                : span.start,
            label: span.label,
          ),
    ];
    if (points.isEmpty) continue;
    anchors.add(
      Link(
        heRef: link.heRef,
        index1: link.index1,
        path2: link.path2,
        index2: link.index2,
        connectionType: link.connectionType,
        anchorStart: points.first.start,
        anchorSpans: points,
      ),
    );
  }
  // העוגנים במסד נמדדו על השורה המלאה, כולל גופי ההערות המשוחזרים.
  return injectLinkAnchorMarkers(
    rawLine: markStoredLineData(rawLine, lineIndex, names: names, notes: notes),
    anchorLinks: anchors,
    styleIndexByCommentator: anchorStyleIndexByCommentator(anchors),
  );
}

int _fullLineOffset(String rawLine, int rawOffset, List<BookNote> notes) {
  final visible = visibleCharCount(
    rawLine.substring(0, rawOffset.clamp(0, rawLine.length)),
  );
  return visible +
      notes
          .where((note) => note.charPos <= visible)
          .fold(0, (sum, note) => sum + visibleCharCount(note.body));
}
