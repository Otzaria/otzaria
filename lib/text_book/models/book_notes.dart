import 'package:flutter/foundation.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';

/// הערת שוליים אחת של שורה (`line_note`). [marker] null — אין לה אות-הפניה;
/// [charPos] — האופסט הגלוי בשורה השמורה שבו עמד הגוף, או -1 לסוף השורה.
typedef BookNote = ({int noteIndex, int charPos, String? marker, String body});

/// הערות השוליים של ספר שלם מטבלת `line_note`, לפי `lineIndex`, ומופעי שמות
/// הקודש שבגופן (`line_note_divine_name`). עובר ל-isolate וחזרה כמו שהוא.
@immutable
class BookNotes {
  const BookNotes._(this._byLine, this._namesByLine);

  /// ספר בלי הערות — גם מסד בלי הטבלה, ספר אישי או מהדורה חלופית.
  static const BookNotes empty = BookNotes._({}, {});

  final Map<int, List<BookNote>> _byLine;
  final Map<int, Map<int, List<DivineNameSpan>>> _namesByLine;

  bool get isEmpty => _byLine.isEmpty;

  /// מספר השורות שיש בהן הערות.
  int get lineCount => _byLine.length;

  /// ההערות של שורה [lineIndex] (0-based), לפי סדר הקריאה.
  List<BookNote> notesAt(int lineIndex) => _byLine[lineIndex] ?? const [];

  /// מופעי השמות בגוף ההערה [noteIndex] של שורה [lineIndex], באופסטים בתוך הגוף.
  List<DivineNameSpan> bodyDivineNames(int lineIndex, int noteIndex) =>
      _namesByLine[lineIndex]?[noteIndex] ?? const [];

  /// ההערה בצורת `notesForLines` של הערת inline, כדי שהצרכנים לא יבחינו במקור.
  static String toInlineHtml(BookNote note, {String? body}) {
    final marker = note.marker;
    final text = body ?? note.body;
    if (marker == null) return text;
    return '<sup class="footnote-marker">$marker</sup> $text';
  }
}

/// בונה [BookNotes] משורות שמגיעות ממוינות לפי (lineIndex, noteIndex).
class BookNotesBuilder {
  final _byLine = <int, List<BookNote>>{};
  final _namesByLine = <int, Map<int, List<DivineNameSpan>>>{};

  void add(
    int lineIndex,
    int noteIndex,
    String? marker,
    String body, {
    int charPos = -1,
  }) {
    (_byLine[lineIndex] ??= []).add((
      noteIndex: noteIndex,
      charPos: charPos,
      marker: marker,
      body: body,
    ));
  }

  /// מופע שם בגוף ההערה; [start, end) באופסט גלוי בתוך הגוף.
  void addDivineName(
    int lineIndex,
    int noteIndex,
    int start,
    int end,
    int kind,
  ) {
    if (start < 0 || end <= start) return;
    ((_namesByLine[lineIndex] ??= {})[noteIndex] ??= []).add((
      start: start,
      end: end,
      kind: kind,
    ));
  }

  BookNotes build() {
    if (_byLine.isEmpty) return BookNotes.empty;
    return BookNotes._(
      {
        for (final entry in _byLine.entries)
          entry.key: List.unmodifiable(entry.value),
      },
      {
        for (final line in _namesByLine.entries)
          line.key: {
            for (final note in line.value.entries)
              note.key: List.unmodifiable(note.value),
          },
      },
    );
  }
}
