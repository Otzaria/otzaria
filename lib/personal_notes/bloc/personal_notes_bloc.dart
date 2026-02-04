import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';

class PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState> {
  PersonalNotesBloc({PersonalNotesRepository? repository})
      : _repository = repository ?? PersonalNotesRepository(),
        super(const PersonalNotesState.initial()) {
    on<LoadPersonalNotes>(_onLoadNotes);
    on<AddPersonalNote>(_onAddNote);
    on<UpdatePersonalNote>(_onUpdateNote);
    on<DeletePersonalNote>(_onDeleteNote);
    on<RepositionPersonalNote>(_onRepositionNote);
    on<StartCreatingPersonalNote>(_onStartCreatingNote);
    on<CancelCreatingPersonalNote>(_onCancelCreatingNote);
    on<UpdateSearchQuery>(_onUpdateSearchQuery);
    // debounce לעדכוני גלילה - מעבד רק את האירוע האחרון תוך 100ms
    on<UpdateVisibleLines>(
      _onUpdateVisibleLines,
      transformer: restartable(),
    );
    on<ToggleShowOnlyVisible>(_onToggleShowOnlyVisible);
  }

  final PersonalNotesRepository _repository;

  Future<void> _onLoadNotes(
    LoadPersonalNotes event,
    Emitter<PersonalNotesState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        bookId: event.bookId,
        errorMessage: null,
        // איפוס החיפוש כשטוענים ספר חדש
        searchQuery: '',
        visibleLineIndices: [],
      ),
    );

    try {
      final notes = await _repository.loadNotes(event.bookId);
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          bookId: event.bookId,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  Future<void> _onAddNote(
    AddPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.addNote(
        bookId: event.bookId,
        lineNumber: event.lineNumber,
        content: event.content,
        contentPlain: event.contentPlain,
        contentFormat: event.contentFormat,
        selectedText: event.selectedText,
      );
      _emitNotes(event.bookId, notes, emit, clearCreatingState: true);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onUpdateNote(
    UpdatePersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    if (state.bookId == null) return;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.updateNote(
        bookId: event.bookId,
        noteId: event.noteId,
        content: event.content,
        contentPlain: event.contentPlain,
        contentFormat: event.contentFormat,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onDeleteNote(
    DeletePersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    if (state.bookId == null) return;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.deleteNote(
        bookId: event.bookId,
        noteId: event.noteId,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onRepositionNote(
    RepositionPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) async {
    if (state.bookId == null) return;
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final notes = await _repository.repositionNote(
        bookId: event.bookId,
        noteId: event.noteId,
        lineNumber: event.lineNumber,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onStartCreatingNote(
    StartCreatingPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) {
    emit(
      state.copyWith(
        isCreatingNewNote: true,
        newNoteLineNumber: event.lineNumber,
        newNoteReferenceText: event.referenceText,
        newNoteSelectedText: event.selectedText,
        newNoteInitialContent: event.initialContent,
        newNoteInitialFormat: event.initialFormat,
      ),
    );
  }

  void _onCancelCreatingNote(
    CancelCreatingPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) {
    emit(state.copyWith(clearNewNoteData: true));
  }

  void _onUpdateSearchQuery(
    UpdateSearchQuery event,
    Emitter<PersonalNotesState> emit,
  ) {
    final filtered = _applyFilters(
      state.locatedNotes,
      state.missingNotes,
      event.query,
      state.showOnlyVisible,
      state.visibleLineIndices,
    );
    emit(
      state.copyWith(
        searchQuery: event.query,
        filteredLocatedNotes: filtered.locatedNotes,
        filteredMissingNotes: filtered.missingNotes,
      ),
    );
  }

  void _onUpdateVisibleLines(
    UpdateVisibleLines event,
    Emitter<PersonalNotesState> emit,
  ) {
    final filtered = _applyFilters(
      state.locatedNotes,
      state.missingNotes,
      state.searchQuery,
      state.showOnlyVisible,
      event.visibleLineIndices,
    );
    emit(
      state.copyWith(
        visibleLineIndices: event.visibleLineIndices,
        filteredLocatedNotes: filtered.locatedNotes,
        filteredMissingNotes: filtered.missingNotes,
      ),
    );
  }

  void _onToggleShowOnlyVisible(
    ToggleShowOnlyVisible event,
    Emitter<PersonalNotesState> emit,
  ) {
    final newShowOnlyVisible = !state.showOnlyVisible;
    final filtered = _applyFilters(
      state.locatedNotes,
      state.missingNotes,
      state.searchQuery,
      newShowOnlyVisible,
      state.visibleLineIndices,
    );
    emit(
      state.copyWith(
        showOnlyVisible: newShowOnlyVisible,
        filteredLocatedNotes: filtered.locatedNotes,
        filteredMissingNotes: filtered.missingNotes,
      ),
    );
  }

  _NotesPartition _applyFilters(
    List<PersonalNote> locatedNotes,
    List<PersonalNote> missingNotes,
    String searchQuery,
    bool showOnlyVisible,
    List<int> visibleLineIndices,
  ) {
    // סינון לפי טקסט נראה
    var filteredLocated = locatedNotes;
    if (showOnlyVisible && visibleLineIndices.isNotEmpty) {
      filteredLocated = locatedNotes.where((note) {
        if (note.lineNumber == null) return false;
        return visibleLineIndices.contains(note.lineNumber! - 1);
      }).toList();
    }

    // סינון לפי חיפוש
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      filteredLocated = filteredLocated.where((note) {
        return note.contentPlain.toLowerCase().contains(query) ||
            note.lineNumber.toString().contains(query);
      }).toList();
    }

    // הערות חסרות מיקום - מוצגות רק אם לא מסננים לפי טקסט נראה
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

    return _NotesPartition(
      locatedNotes: filteredLocated,
      missingNotes: filteredMissing,
    );
  }

  void _emitNotes(
    String bookId,
    List<PersonalNote> notes,
    Emitter<PersonalNotesState> emit, {
    bool clearCreatingState = false,
  }) {
    final split = _splitNotes(notes);
    final filtered = _applyFilters(
      split.locatedNotes,
      split.missingNotes,
      state.searchQuery,
      state.showOnlyVisible,
      state.visibleLineIndices,
    );
    emit(
      state.copyWith(
        isLoading: false,
        bookId: bookId,
        locatedNotes: split.locatedNotes,
        missingNotes: split.missingNotes,
        filteredLocatedNotes: filtered.locatedNotes,
        filteredMissingNotes: filtered.missingNotes,
        errorMessage: null,
        clearNewNoteData: clearCreatingState,
      ),
    );
  }

  _NotesPartition _splitNotes(List<PersonalNote> notes) {
    final sorted = sortPersonalNotes(notes);
    final located = <PersonalNote>[];
    final missing = <PersonalNote>[];
    for (final note in sorted) {
      if (note.hasLocation) {
        located.add(note);
      } else {
        missing.add(note);
      }
    }
    return _NotesPartition(locatedNotes: located, missingNotes: missing);
  }
}

class _NotesPartition {
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;

  _NotesPartition({required this.locatedNotes, required this.missingNotes});
}
