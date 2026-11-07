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
  final PdfNoteAnchor? expandRequestPdfAnchor;
  final int expandRequestToken;

  // יצירת הערה חדשה — הטיוטה מתויגת ב-[newNoteBookId], כי bookId הוא הספר
  // האחרון שנטענו לו הערות ולא בהכרח ספר הטיוטה.
  final bool isCreatingNewNote;
  // בקשה זהה עדיין צריכה לחשוף עורך שנגלל מחוץ למסך.
  final int newNoteRequestToken;
  // חשיפה חוזרת משמרת את היצירה; ביטול או מעבר מיקום מתחילים יצירה אחרת.
  final int newNoteSessionToken;
  final String? newNoteBookId;
  final int? newNoteLineNumber;
  final String? newNoteReferenceText;
  final String? newNoteSelectedText;
  final int? newNoteSelectionColumn;
  final String? newNoteSourceSelectedText;
  final int? newNoteSourceSelectionOffset;
  final bool newNotePunctuationHidden;
  final PdfNoteAnchor? newNotePdfAnchor;
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
    this.expandRequestPdfAnchor,
    this.expandRequestToken = 0,
    this.isCreatingNewNote = false,
    this.newNoteRequestToken = 0,
    this.newNoteSessionToken = 0,
    this.newNoteBookId,
    this.newNoteLineNumber,
    this.newNoteReferenceText,
    this.newNoteSelectedText,
    this.newNoteSelectionColumn,
    this.newNoteSourceSelectedText,
    this.newNoteSourceSelectionOffset,
    this.newNotePunctuationHidden = false,
    this.newNotePdfAnchor,
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
      expandRequestPdfAnchor = null,
      expandRequestToken = 0,
      isCreatingNewNote = false,
      newNoteRequestToken = 0,
      newNoteSessionToken = 0,
      newNoteBookId = null,
      newNoteLineNumber = null,
      newNoteReferenceText = null,
      newNoteSelectedText = null,
      newNoteSelectionColumn = null,
      newNoteSourceSelectedText = null,
      newNoteSourceSelectionOffset = null,
      newNotePunctuationHidden = false,
      newNotePdfAnchor = null,
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
    PdfNoteAnchor? expandRequestPdfAnchor,
    int? expandRequestToken,
    bool? isCreatingNewNote,
    int? newNoteRequestToken,
    int? newNoteSessionToken,
    String? newNoteBookId,
    int? newNoteLineNumber,
    String? newNoteReferenceText,
    String? newNoteSelectedText,
    int? newNoteSelectionColumn,
    String? newNoteSourceSelectedText,
    int? newNoteSourceSelectionOffset,
    bool? newNotePunctuationHidden,
    PdfNoteAnchor? newNotePdfAnchor,
    String? newNoteInitialContent,
    PersonalNoteContentFormat? newNoteInitialFormat,
    bool clearNewNoteData = false,
    bool clearNewNoteSourceSelection = false,
    bool clearNewNotePdfAnchor = false,
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
      expandRequestPdfAnchor: clearExpandRequest
          ? null
          : expandRequestLineNumber != null
          ? expandRequestPdfAnchor
          : (expandRequestPdfAnchor ?? this.expandRequestPdfAnchor),
      expandRequestToken: expandRequestToken ?? this.expandRequestToken,
      isCreatingNewNote: clearNewNoteData
          ? false
          : (isCreatingNewNote ?? this.isCreatingNewNote),
      newNoteRequestToken: newNoteRequestToken ?? this.newNoteRequestToken,
      newNoteSessionToken: newNoteSessionToken ?? this.newNoteSessionToken,
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
      newNoteSourceSelectedText: clearNewNoteData
          ? null
          : clearNewNoteSourceSelection
          ? newNoteSourceSelectedText
          : (newNoteSourceSelectedText ?? this.newNoteSourceSelectedText),
      newNoteSourceSelectionOffset: clearNewNoteData
          ? null
          : clearNewNoteSourceSelection
          ? newNoteSourceSelectionOffset
          : (newNoteSourceSelectionOffset ?? this.newNoteSourceSelectionOffset),
      newNotePunctuationHidden: clearNewNoteData
          ? false
          : (newNotePunctuationHidden ?? this.newNotePunctuationHidden),
      newNotePdfAnchor: clearNewNoteData
          ? null
          : clearNewNotePdfAnchor
          ? newNotePdfAnchor
          : (newNotePdfAnchor ?? this.newNotePdfAnchor),
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
    expandRequestPdfAnchor,
    expandRequestToken,
    isCreatingNewNote,
    newNoteRequestToken,
    newNoteSessionToken,
    newNoteBookId,
    newNoteLineNumber,
    newNoteReferenceText,
    newNoteSelectedText,
    newNoteSelectionColumn,
    newNoteSourceSelectedText,
    newNoteSourceSelectionOffset,
    newNotePunctuationHidden,
    newNotePdfAnchor,
    newNoteInitialContent,
    newNoteInitialFormat,
  ];
}
