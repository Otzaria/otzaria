import 'package:equatable/equatable.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNotesState extends Equatable {
  final bool isLoading;
  final String? bookId;
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;
  final String? errorMessage;

  // סינון והצגה
  final List<PersonalNote> filteredLocatedNotes;
  final List<PersonalNote> filteredMissingNotes;
  final String searchQuery;
  final bool showOnlyVisible;
  final List<int> visibleLineIndices;

  // מצב יצירת הערה חדשה
  final bool isCreatingNewNote;
  final int? newNoteLineNumber;
  final String? newNoteReferenceText;
  final String? newNoteSelectedText;
  final String? newNoteInitialContent;
  final PersonalNoteContentFormat? newNoteInitialFormat;

  const PersonalNotesState({
    required this.isLoading,
    required this.bookId,
    required this.locatedNotes,
    required this.missingNotes,
    required this.errorMessage,
    this.filteredLocatedNotes = const [],
    this.filteredMissingNotes = const [],
    this.searchQuery = '',
    this.showOnlyVisible = true,
    this.visibleLineIndices = const [],
    this.isCreatingNewNote = false,
    this.newNoteLineNumber,
    this.newNoteReferenceText,
    this.newNoteSelectedText,
    this.newNoteInitialContent,
    this.newNoteInitialFormat,
  });

  const PersonalNotesState.initial()
      : isLoading = false,
        bookId = null,
        locatedNotes = const [],
        missingNotes = const [],
        errorMessage = null,
        filteredLocatedNotes = const [],
        filteredMissingNotes = const [],
        searchQuery = '',
        showOnlyVisible = true,
        visibleLineIndices = const [],
        isCreatingNewNote = false,
        newNoteLineNumber = null,
        newNoteReferenceText = null,
        newNoteSelectedText = null,
        newNoteInitialContent = null,
        newNoteInitialFormat = null;

  PersonalNotesState copyWith({
    bool? isLoading,
    String? bookId,
    List<PersonalNote>? locatedNotes,
    List<PersonalNote>? missingNotes,
    String? errorMessage,
    List<PersonalNote>? filteredLocatedNotes,
    List<PersonalNote>? filteredMissingNotes,
    String? searchQuery,
    bool? showOnlyVisible,
    List<int>? visibleLineIndices,
    bool? isCreatingNewNote,
    int? newNoteLineNumber,
    String? newNoteReferenceText,
    String? newNoteSelectedText,
    String? newNoteInitialContent,
    PersonalNoteContentFormat? newNoteInitialFormat,
    bool clearNewNoteData = false,
  }) {
    return PersonalNotesState(
      isLoading: isLoading ?? this.isLoading,
      bookId: bookId ?? this.bookId,
      locatedNotes: locatedNotes ?? this.locatedNotes,
      missingNotes: missingNotes ?? this.missingNotes,
      errorMessage: errorMessage,
      filteredLocatedNotes: filteredLocatedNotes ?? this.filteredLocatedNotes,
      filteredMissingNotes: filteredMissingNotes ?? this.filteredMissingNotes,
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyVisible: showOnlyVisible ?? this.showOnlyVisible,
      visibleLineIndices: visibleLineIndices ?? this.visibleLineIndices,
      isCreatingNewNote: clearNewNoteData
          ? false
          : (isCreatingNewNote ?? this.isCreatingNewNote),
      newNoteLineNumber: clearNewNoteData
          ? null
          : (newNoteLineNumber ?? this.newNoteLineNumber),
      newNoteReferenceText: clearNewNoteData
          ? null
          : (newNoteReferenceText ?? this.newNoteReferenceText),
      newNoteSelectedText: clearNewNoteData
          ? null
          : (newNoteSelectedText ?? this.newNoteSelectedText),
      newNoteInitialContent: clearNewNoteData
          ? null
          : (newNoteInitialContent ?? this.newNoteInitialContent),
      newNoteInitialFormat: clearNewNoteData
          ? null
          : (newNoteInitialFormat ?? this.newNoteInitialFormat),
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        bookId,
        locatedNotes,
        missingNotes,
        errorMessage,
        filteredLocatedNotes,
        filteredMissingNotes,
        searchQuery,
        showOnlyVisible,
        visibleLineIndices,
        isCreatingNewNote,
        newNoteLineNumber,
        newNoteReferenceText,
        newNoteSelectedText,
        newNoteInitialContent,
        newNoteInitialFormat,
      ];
}
