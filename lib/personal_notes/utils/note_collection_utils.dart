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

/// ההערות לפי שורה (1-based). הערה על כמה שורות מופיעה בכל אחת מהן.
Map<int, List<PersonalNote>> indexPersonalNotesByLine(
  Iterable<PersonalNote> notes,
) {
  final byLine = <int, List<PersonalNote>>{};
  for (final note in notes) {
    if (!note.hasLocation) continue;
    for (var line = note.lineNumber!; line <= note.lastLineNumber!; line++) {
      byLine.putIfAbsent(line, () => <PersonalNote>[]).add(note);
    }
  }
  return byLine;
}

List<PersonalNote> sortPersonalNotes(List<PersonalNote> notes) {
  final partition = partitionAndSortPersonalNotes(notes);
  return [...partition.located, ...partition.missing];
}
