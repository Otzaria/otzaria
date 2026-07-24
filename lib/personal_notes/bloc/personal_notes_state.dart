import 'package:equatable/equatable.dart';

import 'package:otzaria/personal_notes/models/personal_note.dart';

class PersonalNotesState extends Equatable {
  final bool isLoading;
  final String? bookId;
  final int? categoryId;
  final List<PersonalNote> locatedNotes;
  final List<PersonalNote> missingNotes;
  final String? errorMessage;

  // סינון והצגה
  final List<PersonalNote> filteredLocatedNotes;
  final List<PersonalNote> filteredMissingNotes;
  final String searchQuery;
  final bool showOnlyVisible;
  final List<int> visibleLineIndices;

  // בקשת הרחבה של הערות לשורה מסוימת (לחיצה על סימון inline).
  // הטוקן עולה בכל בקשה כדי לאפשר הרחבה חוזרת גם אחרי כיווץ ידני.
  final int? expandRequestLineNumber;
  final int expandRequestToken;

  // מצב יצירת הערה חדשה — מתויג ב-bookId נפרד כדי לקשר את הטיוטה
  // לספר שבו היא נוצרה, ללא תלות בספר שעבורו טעונות כעת ההערות
  // (state.bookId משקף את הספר האחרון שעבורו נטענו הערות, לא את הטיוטה).
  final bool isCreatingNewNote;
  final String? newNoteBookId;
  final int? newNoteLineNumber;
  final String? newNoteReferenceText;
  final String? newNoteSelectedText;
  final int? newNoteSelectionColumn;
  final String? newNoteInitialContent;
  final PersonalNoteContentFormat? newNoteInitialFormat;

  const PersonalNotesState({
    required this.isLoading,
    required this.bookId,
    this.categoryId,
    required this.locatedNotes,
    required this.missingNotes,
    required this.errorMessage,
    this.filteredLocatedNotes = const [],
    this.filteredMissingNotes = const [],
    this.searchQuery = '',
    this.showOnlyVisible = true,
    this.visibleLineIndices = const [],
    this.expandRequestLineNumber,
    this.expandRequestToken = 0,
    this.isCreatingNewNote = false,
    this.newNoteBookId,
    this.newNoteLineNumber,
    this.newNoteReferenceText,
    this.newNoteSelectedText,
    this.newNoteSelectionColumn,
    this.newNoteInitialContent,
    this.newNoteInitialFormat,
  });

  const PersonalNotesState.initial()
    : isLoading = false,
      bookId = null,
      categoryId = null,
      locatedNotes = const [],
      missingNotes = const [],
      errorMessage = null,
      filteredLocatedNotes = const [],
      filteredMissingNotes = const [],
      searchQuery = '',
      showOnlyVisible = true,
      visibleLineIndices = const [],
      expandRequestLineNumber = null,
      expandRequestToken = 0,
      isCreatingNewNote = false,
      newNoteBookId = null,
      newNoteLineNumber = null,
      newNoteReferenceText = null,
      newNoteSelectedText = null,
      newNoteSelectionColumn = null,
      newNoteInitialContent = null,
      newNoteInitialFormat = null;

  PersonalNotesState copyWith({
    bool? isLoading,
    String? bookId,
    int? categoryId,
    List<PersonalNote>? locatedNotes,
    List<PersonalNote>? missingNotes,
    String? errorMessage,
    List<PersonalNote>? filteredLocatedNotes,
    List<PersonalNote>? filteredMissingNotes,
    String? searchQuery,
    bool? showOnlyVisible,
    List<int>? visibleLineIndices,
    int? expandRequestLineNumber,
    int? expandRequestToken,
    bool? isCreatingNewNote,
    String? newNoteBookId,
    int? newNoteLineNumber,
    String? newNoteReferenceText,
    String? newNoteSelectedText,
    int? newNoteSelectionColumn,
    String? newNoteInitialContent,
    PersonalNoteContentFormat? newNoteInitialFormat,
    bool clearNewNoteData = false,
    bool clearExpandRequest = false,
  }) {
    return PersonalNotesState(
      isLoading: isLoading ?? this.isLoading,
      bookId: bookId ?? this.bookId,
      categoryId: categoryId ?? this.categoryId,
      locatedNotes: locatedNotes ?? this.locatedNotes,
      missingNotes: missingNotes ?? this.missingNotes,
      errorMessage: errorMessage,
      filteredLocatedNotes: filteredLocatedNotes ?? this.filteredLocatedNotes,
      filteredMissingNotes: filteredMissingNotes ?? this.filteredMissingNotes,
      searchQuery: searchQuery ?? this.searchQuery,
      showOnlyVisible: showOnlyVisible ?? this.showOnlyVisible,
      visibleLineIndices: visibleLineIndices ?? this.visibleLineIndices,
      expandRequestLineNumber: clearExpandRequest
          ? null
          : (expandRequestLineNumber ?? this.expandRequestLineNumber),
      expandRequestToken: expandRequestToken ?? this.expandRequestToken,
      isCreatingNewNote: clearNewNoteData
          ? false
          : (isCreatingNewNote ?? this.isCreatingNewNote),
      newNoteBookId: clearNewNoteData
          ? null
          : (newNoteBookId ?? this.newNoteBookId),
      newNoteLineNumber: clearNewNoteData
          ? null
          : (newNoteLineNumber ?? this.newNoteLineNumber),
      newNoteReferenceText: clearNewNoteData
          ? null
          : (newNoteReferenceText ?? this.newNoteReferenceText),
      newNoteSelectedText: clearNewNoteData
          ? null
          : (newNoteSelectedText ?? this.newNoteSelectedText),
      newNoteSelectionColumn: clearNewNoteData
          ? null
          : (newNoteSelectionColumn ?? this.newNoteSelectionColumn),
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
    categoryId,
    locatedNotes,
    missingNotes,
    errorMessage,
    filteredLocatedNotes,
    filteredMissingNotes,
    searchQuery,
    showOnlyVisible,
    visibleLineIndices,
    expandRequestLineNumber,
    expandRequestToken,
    isCreatingNewNote,
    newNoteBookId,
    newNoteLineNumber,
    newNoteReferenceText,
    newNoteSelectedText,
    newNoteSelectionColumn,
    newNoteInitialContent,
    newNoteInitialFormat,
  ];
}
