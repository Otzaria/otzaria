import 'package:flutter/foundation.dart';

/// הערת שוליים אחת של שורה (`line_note`). [marker] null — הערה שאין לה
/// אות-הפניה בגוף השורה.
typedef BookNote = ({int noteIndex, String? marker, String body});

/// הערות השוליים של ספר שלם מטבלת `line_note`, לפי `lineIndex`. עובר ל-isolate
/// וחזרה כמו שהוא.
@immutable
class BookNotes {
  const BookNotes._(this._byLine);

  /// ספר בלי הערות — גם מסד בלי הטבלה, ספר אישי או מהדורה חלופית.
  static const BookNotes empty = BookNotes._({});

  final Map<int, List<BookNote>> _byLine;

  bool get isEmpty => _byLine.isEmpty;

  /// מספר השורות שיש בהן הערות.
  int get lineCount => _byLine.length;

  /// ההערות של שורה [lineIndex] (0-based), לפי סדר הקריאה.
  List<BookNote> notesAt(int lineIndex) => _byLine[lineIndex] ?? const [];

  /// ההערה בצורת `notesForLines` של הערת inline, כדי שהצרכנים לא יבחינו במקור.
  static String toInlineHtml(BookNote note) {
    final marker = note.marker;
    if (marker == null) return note.body;
    return '<sup class="footnote-marker">$marker</sup> ${note.body}';
  }
}

/// בונה [BookNotes] משורות שמגיעות ממוינות לפי (lineIndex, noteIndex).
class BookNotesBuilder {
  final _byLine = <int, List<BookNote>>{};

  void add(int lineIndex, int noteIndex, String? marker, String body) {
    (_byLine[lineIndex] ??= []).add((
      noteIndex: noteIndex,
      marker: marker,
      body: body,
    ));
  }

  BookNotes build() {
    if (_byLine.isEmpty) return BookNotes.empty;
    return BookNotes._({
      for (final entry in _byLine.entries)
        entry.key: List.unmodifiable(entry.value),
    });
  }
}
