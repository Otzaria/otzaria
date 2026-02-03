import 'package:equatable/equatable.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNotesState extends Equatable {
  final bool isLoading;
  final String? bookId;
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;
  final String? errorMessage;

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
        isCreatingNewNote,
        newNoteLineNumber,
        newNoteReferenceText,
        newNoteSelectedText,
        newNoteInitialContent,
        newNoteInitialFormat,
      ];
}
