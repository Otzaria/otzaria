import 'package:html/parser.dart' as html_parser;
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/utils/text/text_manipulation.dart' show removeVolwels;

typedef BookNoteReportTarget = ({
  int lineIndex,
  String contextText,
  String? singleNoteHtml,
});

/// מזהה הערה רק בין ההערות המוצגות; בחירה עמומה שומרת את כולן עם מיקומן.
BookNoteReportTarget? bookNoteReportTarget({
  required List<String> content,
  required BookNotes bookNotes,
  required Iterable<int> lineIndexes,
  required String selectedText,
  String? noteHtml,
}) {
  final candidates = <({int line, int note, String html, String text})>[];
  for (final line in lineIndexes.toSet()) {
    final lineNotes = notes.notesForLines(content, [line], dbNotes: bookNotes);
    for (final (index, html) in lineNotes.indexed) {
      candidates.add((
        line: line,
        note: index,
        html: html,
        text: bookNoteReportText(html),
      ));
    }
  }
  if (candidates.isEmpty) return null;

  final selection = _matchText(selectedText);
  final matching = candidates.where(
    (note) => noteHtml != null
        ? note.html == noteHtml
        : selection.isNotEmpty && _matchText(note.text).contains(selection),
  );
  final exact = matching.toList();
  final targets = exact.length == 1 ? exact : candidates;
  return (
    lineIndex: targets.first.line,
    singleNoteHtml: exact.length == 1 ? exact.single.html : null,
    contextText: targets
        .map(
          (note) =>
              'הערת שוליים ${note.note + 1} (שורה ${note.line + 1}):\n${note.text}',
        )
        .join('\n\n'),
  );
}

/// Decode a raw note for the display-only fallback when no text was selected.
/// Text supplied by the selection renderer must not be decoded a second time.
String bookNoteReportText(String html) =>
    html_parser
        .parseFragment(
          html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
        )
        .text
        ?.trim() ??
    '';

String _matchText(String text) =>
    removeVolwels(text).replaceAll(RegExp(r'\s+'), ' ').trim();
