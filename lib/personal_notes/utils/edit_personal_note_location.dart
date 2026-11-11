import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/utils/note_location_edit.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/personal_notes/widgets/note_location_editor.dart';
import 'package:otzaria/search/utils/search_result_book_display.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

/// שינוי המיקום של הערת טקסט [note]: מילים, שורות או הספר כולו.
/// [readerProfile] — הגדרות התצוגה של הקורא, כשההערה היא של הספר הפתוח בו.
/// [selectedLine] (1-based) — השורה שנבחרה בקורא, שהערה בלי מיקום נפתחת בה.
Future<void> editPersonalNoteLocation(
  BuildContext context, {
  required PersonalNote note,
  required PersonalNotesRepository repository,
  int? categoryId,
  TextDisplayProfile? readerProfile,
  List<TocEntry>? tableOfContents,
  int? selectedLine,
}) async {
  if (note.pdfAnchor != null) {
    UiSnack.show(NotesMessages.noteAnchorUnavailable);
    return;
  }
  final library = context.read<LibraryBloc?>()?.state.library;
  final settings = context.read<SettingsBloc?>()?.state;
  NoteLocationEdit? edit;
  var profile = readerProfile;
  var toc = tableOfContents;
  try {
    edit = NoteLocationEdit.of(
      note,
      splitBookContentIntoLines(
        await repository.loadBookContent(note.bookId, categoryId: categoryId),
      ),
      fallbackLine: selectedLine,
    );
    final book = library == null
        ? null
        : findTextBookForPersonalNotesKey(library, note.bookId);
    if (profile == null && book != null && settings != null) {
      profile = (await SearchResultBookDisplay.load(
        book,
        perBookSettingsEnabled: settings.enablePerBookSettings,
      )).profile(settings.textDisplayPolicy);
    }
    toc ??= await book?.tableOfContents;
  } catch (error) {
    debugPrint('PersonalNotes: reading the book of ${note.id} failed: $error');
  }
  if (!context.mounted) return;
  if (edit == null) {
    UiSnack.showError(NotesMessages.noteLineUnavailable);
    return;
  }
  final render = RenderSettings.fromProfile(
    profile ?? TextDisplayProfile.defaults,
  );
  final contents = toc;
  final result = await showNoteLocationEditor(
    context,
    edit: edit,
    display: (source) => TextRendererService.stripHtml(
      TextRendererService.processText(source, render),
    ),
    lineLabel: contents == null || contents.isEmpty
        ? null
        : (index) => _lineLabel(index, contents),
    selectedLine: selectedLine,
  );
  if (result == null) return;
  final range = result.range;
  final words = result.scope == PersonalNoteScope.words;
  try {
    await repository.setNoteLocation(
      bookId: note.bookId,
      noteId: note.id,
      scope: result.scope,
      lineNumber: range.start.paragraph + 1,
      endLineNumber: range.end.paragraph + 1,
      sourceText: words ? range.text : null,
      sourceOffset: words ? range.start.offset : null,
      categoryId: categoryId,
    );
    UiSnack.showSuccess(NotesMessages.noteRepositioned);
  } catch (error) {
    debugPrint('PersonalNotes: moving ${note.id} failed: $error');
    UiSnack.showError(NotesMessages.noteAnchorSaveFailed);
  }
}

String _lineLabel(int index, List<TocEntry> toc) {
  final ref = refFromTocList(index, toc).trim();
  return ref.isEmpty ? 'שורה ${index + 1}' : ref;
}
