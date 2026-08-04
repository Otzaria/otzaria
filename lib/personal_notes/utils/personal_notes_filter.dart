import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNotesFilterResult {
  const PersonalNotesFilterResult({
    required this.locatedNotes,
    required this.missingNotes,
  });

  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;
}

PersonalNotesFilterResult filterPersonalNotes({
  required List<PersonalNote> locatedNotes,
  required List<PersonalNote> missingNotes,
  required String searchQuery,
  required bool showOnlyVisible,
  required List<int> visibleLineIndices,
}) {
  var filteredLocated = locatedNotes;
  if (showOnlyVisible && visibleLineIndices.isNotEmpty) {
    final visibleLines = visibleLineIndices.toSet();
    filteredLocated = locatedNotes.where((note) {
      final lineNumber = note.lineNumber;
      return lineNumber != null && visibleLines.contains(lineNumber - 1);
    }).toList();
  }

  if (searchQuery.isNotEmpty) {
    final query = searchQuery.toLowerCase();
    filteredLocated = filteredLocated.where((note) {
      return note.contentPlain.toLowerCase().contains(query) ||
          (note.lineNumber?.toString().contains(query) ?? false);
    }).toList();
  }

  var filteredMissing = <PersonalNote>[];
  if (!showOnlyVisible) {
    filteredMissing = missingNotes;
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filteredMissing = filteredMissing.where((note) {
        return note.contentPlain.toLowerCase().contains(query) ||
            (note.lastKnownLineNumber?.toString().contains(query) ?? false);
      }).toList();
    }
  }

  return PersonalNotesFilterResult(
    locatedNotes: filteredLocated,
    missingNotes: filteredMissing,
  );
}
