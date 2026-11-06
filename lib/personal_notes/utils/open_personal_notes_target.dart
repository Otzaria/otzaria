import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/pdf_note_anchor.dart';

/// טוען ספר בלשונית ההערות ומבקש להרחיב את הערות השורה שנבחרה.
void openPersonalNotesTarget(
  PersonalNotesBloc bloc, {
  required String bookId,
  required int lineNumber,
  int? categoryId,
  PdfNoteAnchor? pdfAnchor,
}) {
  if (bloc.state.showOnlyVisible) {
    bloc.add(const ToggleShowOnlyVisible());
  }
  if (bloc.state.searchQuery.isNotEmpty) {
    bloc.add(const UpdateSearchQuery(''));
  }
  bloc.add(LoadPersonalNotes(bookId, categoryId: categoryId));
  bloc.add(RequestExpandNotesForLine(lineNumber, pdfAnchor: pdfAnchor));
}
