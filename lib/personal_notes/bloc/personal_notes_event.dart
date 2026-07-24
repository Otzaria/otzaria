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
  final int lineNumber;
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;
  final String? selectedText;

  /// עמודת ההתחלה המשוערת של הבחירה (לזיהוי המופע הנכון כשהטקסט חוזר בשורה).
  final int? selectionColumn;

  const AddPersonalNote({
    required this.bookId,
    required this.lineNumber,
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    this.selectedText,
    this.selectionColumn,
  });

  @override
  List<Object?> get props => [
    bookId,
    lineNumber,
    content,
    contentPlain,
    contentFormat,
    selectedText,
    selectionColumn,
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

  const DeletePersonalNote({
    required this.bookId,
    required this.noteId,
  });

  @override
  List<Object?> get props => [bookId, noteId];
}

class RepositionPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final String noteId;
  final int lineNumber;

  const RepositionPersonalNote({
    required this.bookId,
    required this.noteId,
    required this.lineNumber,
  });

  @override
  List<Object?> get props => [bookId, noteId, lineNumber];
}

/// בקשה להרחיב (לפתוח) את ההערות המשויכות לשורה [lineNumber] (1-based),
/// גם אם ההגדרה היא "סגור כברירת מחדל". נשלח בלחיצה על סימון הערה inline.
class RequestExpandNotesForLine extends PersonalNotesEvent {
  final int lineNumber;

  const RequestExpandNotesForLine(this.lineNumber);

  @override
  List<Object?> get props => [lineNumber];
}

class StartCreatingPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final int lineNumber;
  final String? referenceText;
  final String? selectedText;
  final int? selectionColumn;
  final String? initialContent;
  final PersonalNoteContentFormat? initialFormat;

  const StartCreatingPersonalNote({
    required this.bookId,
    required this.lineNumber,
    this.referenceText,
    this.selectedText,
    this.selectionColumn,
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
    initialContent,
    initialFormat,
  ];
}

class CancelCreatingPersonalNote extends PersonalNotesEvent {
  const CancelCreatingPersonalNote();
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
