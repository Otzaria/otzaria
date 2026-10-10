import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_changes.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_filter.dart';

class PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState> {
  PersonalNotesBloc({PersonalNotesRepository? repository})
    : _repository = repository ?? PersonalNotesRepository(),
      super(const PersonalNotesState.initial()) {
    on<LoadPersonalNotes>(_onLoadNotes, transformer: restartable());
    on<AddPersonalNote>(_onAddNote);
    on<UpdatePersonalNote>(_onUpdateNote);
    on<DeletePersonalNote>(_onDeleteNote);
    on<RepositionPersonalNote>(_onRepositionNote);
    on<RequestExpandNotesForLine>(_onRequestExpandNotesForLine);
    on<StartCreatingPersonalNote>(_onStartCreatingNote);
    on<CancelCreatingPersonalNote>(_onCancelCreatingNote);
    on<UpdateSearchQuery>(_onUpdateSearchQuery);
    // debounce לעדכוני גלילה - מעבד רק את האירוע האחרון תוך 100ms
    on<UpdateVisibleLines>(
      _onUpdateVisibleLines,
      transformer: restartable(),
    );
    on<ToggleShowOnlyVisible>(_onToggleShowOnlyVisible);
    on<_StoredNotesChanged>(_onStoredNotesChanged, transformer: restartable());
    _changesSubscription = PersonalNotesChanges.stream.listen((bookId) {
      if (bookId == state.bookId) add(_StoredNotesChanged(bookId));
    });
  }

  final PersonalNotesRepository _repository;
  late final StreamSubscription<String> _changesSubscription;

  /// שינוי שהגיע בזמן טעינה — נבדק שוב כשהיא מסתיימת, כי ייתכן שקדם לקריאתה.
  bool _storageChangedWhileLoading = false;

  @override
  void onChange(Change<PersonalNotesState> change) {
    super.onChange(change);
    final bookId = change.nextState.bookId;
    if (_storageChangedWhileLoading &&
        !change.nextState.isLoading &&
        bookId != null) {
      _storageChangedWhileLoading = false;
      add(_StoredNotesChanged(bookId));
    }
  }

  @override
  Future<void> close() async {
    await _changesSubscription.cancel();
    return super.close();
  }

  /// הערות שנכתבו מחוץ ל-bloc (דיאלוג הערת מפרש, תוסף, חלונית אחרת).
  /// שינוי שה-bloc עצמו ביצע כבר משתקף ב-state, ולכן אינו נטען שוב.
  Future<void> _onStoredNotesChanged(
    _StoredNotesChanged event,
    Emitter<PersonalNotesState> emit,
  ) async {
    try {
      if (event.bookId != state.bookId || _deferWhileLoading()) return;
      final stored = await _repository.loadStoredNotes(event.bookId);
      if (event.bookId != state.bookId || _matchesState(stored)) return;
      if (_deferWhileLoading()) return;
      // טעינה כאן ולא LoadPersonalNotes: זו הייתה מבטלת טעינה ממתינה של ספר אחר.
      final notes = await _repository.loadNotes(
        event.bookId,
        categoryId: state.categoryId,
      );
      if (event.bookId != state.bookId || _deferWhileLoading()) return;
      _emitNotes(event.bookId, notes, emit);
    } catch (error) {
      // רענון רקע: ההערות המוצגות נשארות, והשגיאה תופיע בטעינה הבאה.
      debugPrint('PersonalNotesBloc: רענון ההערות נכשל: $error');
    }
  }

  /// טעינה שרצה עכשיו עלולה לקרוא את המסד לפני השינוי — בודקים שוב כשהיא נגמרת.
  bool _deferWhileLoading() {
    if (!state.isLoading) return false;
    _storageChangedWhileLoading = true;
    return true;
  }

  bool _matchesState(List<PersonalNote> stored) {
    final current = {
      for (final note in [...state.locatedNotes, ...state.missingNotes])
        note.id: note,
    };
    return stored.length == current.length &&
        stored.every((note) => current[note.id] == note);
  }

  Future<void> _onLoadNotes(
    LoadPersonalNotes event,
    Emitter<PersonalNotesState> emit,
  ) async {
    // רענון אותו ספר חייב לשמר את השורות הגלויות; איפוסן היה מבטל את הסינון
    // "הצג רק הערות לטקסט הנראה" ומציג את כל הספר עד הגלילה הבאה.
    final isSameBook =
        state.bookId == event.bookId && state.categoryId == event.categoryId;

    emit(
      state.copyWith(
        isLoading: true,
        bookId: event.bookId,
        categoryId: event.categoryId,
        errorMessage: null,
        // ספר אחר: ההערות של הספר הקודם אינן שלו — גם בזמן הטעינה וגם אם
        // היא תיכשל, אחרת מסך ההערות שומר אותן תחת הספר השגוי (issue #1313).
        locatedNotes: isSameBook ? null : const [],
        missingNotes: isSameBook ? null : const [],
        filteredLocatedNotes: isSameBook ? null : const [],
        filteredMissingNotes: isSameBook ? null : const [],
        searchQuery: isSameBook ? state.searchQuery : '',
        visibleLineIndices: isSameBook ? state.visibleLineIndices : [],
        // איפוס בקשת פתיחת הערה, כדי שלא תיפתח אוטומטית הערה באותה שורה בספר החדש
        clearExpandRequest: true,
      ),
    );

    try {
      final notes = await _repository.loadNotes(
        event.bookId,
        categoryId: event.categoryId,
      );
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
        selectionColumn: event.selectionColumn,
        punctuationHidden: event.punctuationHidden,
        categoryId: state.categoryId,
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
        categoryId: state.categoryId,
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
        categoryId: state.categoryId,
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
        categoryId: state.categoryId,
      );
      _emitNotes(event.bookId, notes, emit);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onRequestExpandNotesForLine(
    RequestExpandNotesForLine event,
    Emitter<PersonalNotesState> emit,
  ) {
    emit(
      state.copyWith(
        expandRequestLineNumber: event.lineNumber,
        expandRequestToken: state.expandRequestToken + 1,
      ),
    );
  }

  void _onStartCreatingNote(
    StartCreatingPersonalNote event,
    Emitter<PersonalNotesState> emit,
  ) {
    emit(
      state.copyWith(
        isCreatingNewNote: true,
        newNoteBookId: event.bookId,
        newNoteLineNumber: event.lineNumber,
        newNoteReferenceText: event.referenceText,
        newNoteSelectedText: event.selectedText,
        newNoteSelectionColumn: event.selectionColumn,
        newNotePunctuationHidden: event.punctuationHidden,
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
    final filtered = filterPersonalNotes(
      locatedNotes: state.locatedNotes,
      missingNotes: state.missingNotes,
      searchQuery: event.query,
      showOnlyVisible: state.showOnlyVisible,
      visibleLineIndices: state.visibleLineIndices,
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
    final filtered = filterPersonalNotes(
      locatedNotes: state.locatedNotes,
      missingNotes: state.missingNotes,
      searchQuery: state.searchQuery,
      showOnlyVisible: state.showOnlyVisible,
      visibleLineIndices: event.visibleLineIndices,
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
    final filtered = filterPersonalNotes(
      locatedNotes: state.locatedNotes,
      missingNotes: state.missingNotes,
      searchQuery: state.searchQuery,
      showOnlyVisible: newShowOnlyVisible,
      visibleLineIndices: state.visibleLineIndices,
    );
    emit(
      state.copyWith(
        showOnlyVisible: newShowOnlyVisible,
        filteredLocatedNotes: filtered.locatedNotes,
        filteredMissingNotes: filtered.missingNotes,
      ),
    );
  }

  void _emitNotes(
    String bookId,
    List<PersonalNote> notes,
    Emitter<PersonalNotesState> emit, {
    bool clearCreatingState = false,
  }) {
    final split = _splitNotes(notes);
    final filtered = filterPersonalNotes(
      locatedNotes: split.locatedNotes,
      missingNotes: split.missingNotes,
      searchQuery: state.searchQuery,
      showOnlyVisible: state.showOnlyVisible,
      visibleLineIndices: state.visibleLineIndices,
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

class _StoredNotesChanged extends PersonalNotesEvent {
  final String bookId;

  const _StoredNotesChanged(this.bookId);

  @override
  List<Object?> get props => [bookId];
}

class _NotesPartition {
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;

  _NotesPartition({required this.locatedNotes, required this.missingNotes});
}
