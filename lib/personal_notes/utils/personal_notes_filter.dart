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
  bool isPdf = false,
  List<int>? visiblePdfPages,
  String? pdfDocumentId,
  bool includeUnidentifiedPdfAnchors = false,
}) {
  bool included(PersonalNote note) {
    final anchor = note.pdfAnchor;
    if (anchor == null) return true;
    if (!isPdf) return false;
    if (anchor.documentId == null) return includeUnidentifiedPdfAnchors;
    return anchor.documentId == pdfDocumentId;
  }

  var filteredLocated = locatedNotes.where(included).toList();
  if (showOnlyVisible &&
      (visibleLineIndices.isNotEmpty || visiblePdfPages != null)) {
    final visibleLines = visibleLineIndices.toSet();
    final pdfPages = visiblePdfPages?.toSet();
    filteredLocated = filteredLocated.where((note) {
      final pdfAnchor = note.pdfAnchor;
      if (isPdf && pdfAnchor != null && pdfPages != null) {
        return pdfPages.contains(pdfAnchor.pageNumber);
      }
      if (visibleLines.isEmpty) return true;
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
    filteredMissing = missingNotes.where(included).toList();
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
