import 'package:equatable/equatable.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

abstract class PersonalNotesEvent extends Equatable {
  const PersonalNotesEvent();

  @override
  List<Object?> get props => [];
}

class LoadPersonalNotes extends PersonalNotesEvent {
  final String bookId;

  const LoadPersonalNotes(this.bookId);
  @override
  List<Object?> get props => [bookId];
}

class AddPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final int lineNumber;
  final String content;
  final String contentPlain;
  final PersonalNoteContentFormat contentFormat;
  final String? selectedText;

  const AddPersonalNote({
    required this.bookId,
    required this.lineNumber,
    required this.content,
    required this.contentPlain,
    required this.contentFormat,
    this.selectedText,
  });

  @override
  List<Object?> get props =>
      [bookId, lineNumber, content, contentPlain, contentFormat, selectedText];
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
  List<Object?> get props =>
      [bookId, noteId, content, contentPlain, contentFormat];
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

class StartCreatingPersonalNote extends PersonalNotesEvent {
  final String bookId;
  final int lineNumber;
  final String? referenceText;
  final String? selectedText;
  final String? initialContent;
  final PersonalNoteContentFormat? initialFormat;

  const StartCreatingPersonalNote({
    required this.bookId,
    required this.lineNumber,
    this.referenceText,
    this.selectedText,
    this.initialContent,
    this.initialFormat,
  });

  @override
  List<Object?> get props => [
        bookId,
        lineNumber,
        referenceText,
        selectedText,
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
