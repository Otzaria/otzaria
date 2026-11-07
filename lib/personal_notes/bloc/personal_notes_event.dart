import 'package:equatable/equatable.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

abstract class PersonalNotesEvent extends Equatable {
  const PersonalNotesEvent();

  @override
  List<Object?> get props => [];
}

class LoadPersonalNotes extends PersonalNotesEvent {
  final String bookId;
  final int? categoryId;

  const LoadPersonalNotes(this.bookId, {this.categoryId});
  @override
  List<Object?> get props => [bookId, categoryId];
}

class AddPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final int? categoryId;
  final int lineNumber;
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;
  final String? selectedText;

  /// עמודת ההתחלה המשוערת של הבחירה (לזיהוי המופע הנכון כשהטקסט חוזר בשורה).
  final int? selectionColumn;
  final String? sourceSelectedText;
  final int? sourceSelectionOffset;
  final bool punctuationHidden;
  final PdfNoteAnchor? pdfAnchor;

  const AddPersonalNote({
    required this.bookId,
    this.categoryId,
    required this.lineNumber,
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    this.selectedText,
    this.selectionColumn,
    this.sourceSelectedText,
    this.sourceSelectionOffset,
    this.punctuationHidden = false,
    this.pdfAnchor,
  });

  @override
  List<Object?> get props => [
    bookId,
    categoryId,
    lineNumber,
    content,
    contentPlain,
    contentFormat,
    selectedText,
    selectionColumn,
    sourceSelectedText,
    sourceSelectionOffset,
    punctuationHidden,
    pdfAnchor,
  ];
}

class UpdatePersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;

  const UpdatePersonalNote({
    required this.bookId,
    required this.noteId,
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
  });

  @override
  List<Object?> get props => [
    bookId,
    noteId,
    content,
    contentPlain,
    contentFormat,
  ];
}

class DeletePersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;

  const DeletePersonalNote({required this.bookId, required this.noteId});

  @override
  List<Object?> get props => [bookId, noteId];
}

class RepositionPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;
  final int lineNumber;
  final PdfNoteAnchor? pdfAnchor;
  final int? categoryId;

  const RepositionPersonalNote({
    required this.bookId,
    required this.noteId,
    required this.lineNumber,
    this.pdfAnchor,
    this.categoryId,
  });

  @override
  List<Object?> get props => [
    bookId,
    noteId,
    lineNumber,
    pdfAnchor,
    categoryId,
  ];
}

/// בקשה להרחיב (לפתוח) את ההערות המשויכות לשורה [lineNumber] (1-based),
/// גם אם ההגדרה היא "סגור כברירת מחדל". נשלח בלחיצה על סימון הערה inline.
class RequestExpandNotesForLine extends PersonalNotesEvent {
  final int lineNumber;
  final PdfNoteAnchor? pdfAnchor;

  const RequestExpandNotesForLine(this.lineNumber, {this.pdfAnchor});

  @override
  List<Object?> get props => [lineNumber, pdfAnchor];
}

class StartCreatingPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final int lineNumber;
  final String? referenceText;
  final String? selectedText;
  final int? selectionColumn;
  final String? sourceSelectedText;
  final int? sourceSelectionOffset;
  final bool punctuationHidden;
  final PdfNoteAnchor? pdfAnchor;
  final String? initialContent;
  final PersonalNoteContentFormat? initialFormat;

  const StartCreatingPersonalNote({
    required this.bookId,
    required this.lineNumber,
    this.referenceText,
    this.selectedText,
    this.selectionColumn,
    this.sourceSelectedText,
    this.sourceSelectionOffset,
    this.punctuationHidden = false,
    this.pdfAnchor,
    this.initialContent,
    this.initialFormat,
  });

  @override
  List<Object?> get props => [
    bookId,
    lineNumber,
    referenceText,
    selectedText,
    selectionColumn,
    sourceSelectedText,
    sourceSelectionOffset,
    punctuationHidden,
    pdfAnchor,
    initialContent,
    initialFormat,
  ];
}

class CancelCreatingPersonalNote extends PersonalNotesEvent {
  final int? sessionToken;
  final String? bookId;
  final int? lineNumber;

  const CancelCreatingPersonalNote({
    this.sessionToken,
    this.bookId,
    this.lineNumber,
  });

  @override
  List<Object?> get props => [sessionToken, bookId, lineNumber];
}

class UpdateSearchQuery extends PersonalNotesEvent {
  final String query;

  const UpdateSearchQuery(this.query);

  @override
  List<Object?> get props => [query];
}

class UpdateVisibleLines extends PersonalNotesEvent {
  final List<int> visibleLineIndices;

  const UpdateVisibleLines(this.visibleLineIndices);

  @override
  List<Object?> get props => [visibleLineIndices];
}

class ToggleShowOnlyVisible extends PersonalNotesEvent {
  const ToggleShowOnlyVisible();
}
