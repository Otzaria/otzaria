import 'package:flutter/material.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_content_view.dart';

/// ההערה של [mark] כהערה אישית, לתצוגה ולעורך של ההערות האישיות. null כשאין
/// לסימון הערה.
PersonalNote? markerNoteAsPersonalNote(MarkerHighlight mark) {
  final note = mark.note;
  if (note == null) return null;
  return PersonalNote(
    id: 'marker:${mark.id}',
    bookId: mark.bookTitle,
    lineNumber: mark.sectionStart + 1,
    lastKnownLineNumber: null,
    status: PersonalNoteStatus.located,
    content: note.content,
    contentPlain: note.plain,
    contentFormat: note.format,
    createdAt: mark.createdAt,
    updatedAt: mark.updatedAt,
  );
}

/// ההערה של סימון בעיצוב שבו נכתבה, בתצוגה של ההערות האישיות.
class MarkerNoteView extends StatelessWidget {
  final MarkerHighlight mark;

  /// קיצור לתצוגה מקדימה; null — ההערה כולה.
  final int? maxChars;
  final TextStyle? textStyle;

  const MarkerNoteView({
    super.key,
    required this.mark,
    this.maxChars,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) => PersonalNoteContentView(
    // המפתח מרענן את התצוגה כשההערה נערכת.
    key: ValueKey((mark.id, mark.version)),
    note: markerNoteAsPersonalNote(mark)!,
    maxPreviewChars: maxChars,
    interactive: false,
    textAlign: TextAlign.start,
    textStyle: textStyle,
  );
}
