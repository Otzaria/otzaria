import 'package:otzaria/personal_notes/models/personal_note.dart';

List<PersonalNote> sortPersonalNotes(List<PersonalNote> notes) {
  final located = notes.where((n) => n.hasLocation).toList()
    ..sort((a, b) {
      final lineOrder = a.lineNumber!.compareTo(b.lineNumber!);
      if (lineOrder != 0) return lineOrder;
      final creationOrder = a.createdAt.compareTo(b.createdAt);
      return creationOrder != 0 ? creationOrder : a.id.compareTo(b.id);
    });
  final missing = notes.where((n) => !n.hasLocation).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return [...located, ...missing];
}
