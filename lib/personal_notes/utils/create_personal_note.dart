import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';

/// פותח עורך בחלונית הערות פעילה, או דיאלוג בלי לשנות את מצב החלוניות.
Future<void> createPersonalNote(
  BuildContext context, {
  required bool isNotesPanelOpen,
  required String bookId,
  required int lineNumber,
  String title = 'הערה חדשה',
  int? categoryId,
  String? referenceText,
  String? selectedText,
  int? selectionColumn,
  String? sourceSelectedText,
  int? sourceSelectionOffset,
  bool punctuationHidden = false,
  PdfNoteAnchor? pdfAnchor,
  VoidCallback? openNotesPanel,
  PersonalNotesRepository? repository,
}) async {
  final bloc = context.read<PersonalNotesBloc?>();
  final draft = await PersonalNoteDraftService().loadDraft(
    bookId: bookId,
    categoryId: categoryId,
    lineNumber: lineNumber,
    pdfAnchor: pdfAnchor,
  );
  if (!context.mounted) return;

  if (isNotesPanelOpen) {
    final notesBloc = bloc ?? context.read<PersonalNotesBloc>();
    if (openNotesPanel != null) {
      openNotesPanel();
      // מעבר מהערות מפרש לספר הראשי מעדכן את יעד ה-sidebar. נותנים לו
      // להשלים את ביטול העורך הקודם לפני הבקשה החדשה.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
    }
    if (notesBloc.state.bookId != bookId ||
        notesBloc.state.categoryId != categoryId) {
      notesBloc.add(LoadPersonalNotes(bookId, categoryId: categoryId));
    }
    notesBloc.add(
      StartCreatingPersonalNote(
        bookId: bookId,
        lineNumber: lineNumber,
        referenceText: referenceText,
        selectedText: selectedText,
        selectionColumn: selectionColumn,
        sourceSelectedText: sourceSelectedText,
        sourceSelectionOffset: sourceSelectionOffset,
        punctuationHidden: punctuationHidden,
        pdfAnchor: pdfAnchor,
        initialContent: draft?.content ?? '',
        initialFormat: draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      ),
    );
    return;
  }

  final notesRepository = repository ?? PersonalNotesRepository();
  await showDialogUntilTornDown<PersonalNoteEditorResult>(
    context: context,
    builder: (_) => PersonalNoteEditorDialog(
      title: title,
      referenceText: referenceText,
      icon: FluentIcons.note_add_24_regular,
      bookId: bookId,
      categoryId: categoryId,
      draftLineNumber: lineNumber,
      pdfAnchor: pdfAnchor,
      initialContent: draft?.content ?? '',
      initialContentFormat:
          draft?.contentFormat ?? PersonalNoteContentFormat.plain,
      linkableNotes: bloc?.state.bookId == bookId
          ? [...bloc!.state.locatedNotes, ...bloc.state.missingNotes]
          : const [],
      onSave: (result) => notesRepository.createNote(
        bookId: bookId,
        lineNumber: lineNumber,
        content: result.content,
        contentPlain: result.contentPlain,
        contentFormat: result.contentFormat,
        selectedText: selectedText,
        selectionColumn: selectionColumn,
        sourceSelectedText: sourceSelectedText,
        sourceSelectionOffset: sourceSelectionOffset,
        punctuationHidden: punctuationHidden,
        categoryId: categoryId,
        pdfAnchor: pdfAnchor,
      ),
    ),
  );
}

/// מצב החלונית בפועל, לקריאה בעת קיצור מקלדת מהמסך העוטף.
abstract interface class PersonalNotesPanelVisibility {
  bool get isPersonalNotesPanelOpen;

  void revealPersonalNotesTarget(
    String bookId,
    int? categoryId,
    int lineNumber,
  );
}

/// תפריט מפרש יכול להופיע בכמה מסכי קריאה. משתמשים בפאנל של המסך הקרוב
/// בלבד, וקוראים את מצבו בעת הפעולה — גם אם כרטיס המפרש נשמר במטמון.
PersonalNotesPanelVisibility? findPersonalNotesPanel(BuildContext context) {
  PersonalNotesPanelVisibility? panel;
  context.visitAncestorElements((element) {
    if (element is StatefulElement) {
      final Object state = element.state;
      if (state is PersonalNotesPanelVisibility) {
        panel = state;
        return false;
      }
    }
    return true;
  });
  return panel;
}
