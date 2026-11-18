import 'dart:collection';

import 'package:otzaria/personal_notes/models/personal_note.dart';

/// הערות ממוקמות וחסרות-מיקום, כל קבוצה כבר ממוינת.
typedef PersonalNotesPartition = ({
  List<PersonalNote> located,
  List<PersonalNote> missing,
});

/// מפריד הערות לממוקמות (עם [PersonalNote.hasLocation]) וחסרות-מיקום,
/// וממיין כל קבוצה: ממוקמות לפי מספר שורה (ואז מועד יצירה, ואז מזהה),
/// חסרות-מיקום לפי מועד עדכון יורד.
PersonalNotesPartition partitionAndSortPersonalNotes(List<PersonalNote> notes) {
  final located = notes.where((n) => n.hasLocation).toList()
    ..sort((a, b) {
      final lineOrder = a.lineNumber!.compareTo(b.lineNumber!);
      if (lineOrder != 0) return lineOrder;
      final creationOrder = a.createdAt.compareTo(b.createdAt);
      return creationOrder != 0 ? creationOrder : a.id.compareTo(b.id);
    });
  final missing = notes.where((n) => !n.hasLocation).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return (located: located, missing: missing);
}

/// מטמון לפי זהות הרשימה האחרונה, עבור קורא אחד.
class PersonalNotesLineIndex {
  List<PersonalNote>? _notes;
  Map<int, List<PersonalNote>> _byLine = const {};

  /// הרשימה היא תמונת־מצב לקריאה בלבד, שמתעדכנת בהחלפת המופע.
  Map<int, List<PersonalNote>> forSnapshot(List<PersonalNote> notes) {
    if (identical(notes, _notes)) return _byLine;
    _byLine = notes.isEmpty ? const {} : indexPersonalNotesByLine(notes);
    _notes = notes;
    return _byLine;
  }
}

/// ההערות לפי שורה (1-based), בלי להקצות רשומה לכל שורה בטווח.
Map<int, List<PersonalNote>> indexPersonalNotesByLine(
  Iterable<PersonalNote> notes,
) {
  final byLine = <int, List<PersonalNote>>{};
  final ranges = <({int order, PersonalNote note})>[];
  final order = HashMap<PersonalNote, int>.identity();
  var position = 0;
  for (final note in notes) {
    if (!note.hasLocation || note.lastLineNumber! < note.lineNumber!) continue;
    final current = position++;
    if (note.lastLineNumber! > note.lineNumber!) {
      ranges.add((order: current, note: note));
    } else {
      byLine.putIfAbsent(note.lineNumber!, () => <PersonalNote>[]).add(note);
      // שורות שלפני הטווח הראשון קודמות לכל הטווחים בלי מפתח סדר.
      if (ranges.isNotEmpty) order[note] = current;
    }
  }
  return ranges.isEmpty ? byLine : _RangedNotesByLine(byLine, ranges, order);
}

class _RangedNotesByLine extends UnmodifiableMapBase<int, List<PersonalNote>> {
  _RangedNotesByLine(this._singleLines, this._ranges, this._order);

  final Map<int, List<PersonalNote>> _singleLines;
  final List<({int order, PersonalNote note})> _ranges;
  final Map<PersonalNote, int> _order;

  // איחוד מרווחים מאפשר גם keys ו-length בלי פריסה של טווח מיובא גדול.
  late final _spans = () {
    final spans = <({int start, int end})>[
      for (final line in _singleLines.keys) (start: line, end: line),
      for (final range in _ranges)
        (start: range.note.lineNumber!, end: range.note.lastLineNumber!),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end})>[];
    for (final span in spans) {
      if (merged.isEmpty ||
          (span.start > merged.last.end && span.start - merged.last.end > 1)) {
        merged.add(span);
      } else if (span.end > merged.last.end) {
        merged[merged.length - 1] = (start: merged.last.start, end: span.end);
      }
    }
    return merged;
  }();

  @override
  List<PersonalNote>? operator [](Object? key) {
    if (key is! int) return null;
    final single = _singleLines[key] ?? const <PersonalNote>[];
    final result = <PersonalNote>[];
    var next = 0;
    for (final range in _ranges) {
      if (!range.note.coversLine(key)) continue;
      while (next < single.length &&
          (_order[single[next]] ?? -1) < range.order) {
        result.add(single[next++]);
      }
      result.add(range.note);
    }
    if (result.isEmpty) return single.isEmpty ? null : single;
    result.addAll(single.skip(next));
    return result;
  }

  @override
  Iterable<int> get keys sync* {
    for (final span in _spans) {
      for (var line = span.start; line < span.end; line++) {
        yield line;
      }
      yield span.end;
    }
  }

  @override
  int get length =>
      _spans.fold(0, (sum, span) => sum + span.end - span.start + 1);

  @override
  bool containsKey(Object? key) =>
      key is int &&
      (_singleLines.containsKey(key) ||
          _ranges.any((r) => r.note.coversLine(key)));
}

List<PersonalNote> sortPersonalNotes(List<PersonalNote> notes) {
  final partition = partitionAndSortPersonalNotes(notes);
  return [...partition.located, ...partition.missing];
}
