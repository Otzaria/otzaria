import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

class _Database extends Fake implements PersonalNotesDatabase {
  PersonalNote? note;
  int updates = 0;
  int listReads = 0;

  @override
  Future<PersonalNote?> getNote(String id) async => note;

  @override
  Future<void> updateNote(PersonalNote value) async {
    updates++;
    note = value;
  }

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async {
    listReads++;
    final value = note;
    return value != null && value.bookId == bookId ? [value] : [];
  }
}

void main() {
  test(
    'reposition refuses an already deleted note instead of reporting success',
    () async {
      final database = _Database();
      final service = PersonalNotesService(database: database);

      await expectLater(
        service.repositionNote(
          bookId: 'requested-book',
          bookContent: 'first line\nsecond line',
          noteId: 'removed-note',
          lineNumber: 2,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            NotesMessages.noteNoLongerExists,
          ),
        ),
      );

      expect(database.updates, 0);
      expect(database.listReads, 0);
    },
  );

  test('reposition refuses an id belonging to a different book', () async {
    final original = PersonalNote(
      id: 'moved-note',
      bookId: 'other-book',
      lineNumber: 1,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: 'retained content',
      contentPlain: 'retained content',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final database = _Database()..note = original;
    final service = PersonalNotesService(database: database);

    await expectLater(
      service.repositionNote(
        bookId: 'requested-book',
        bookContent: 'first line\nsecond line',
        noteId: original.id,
        lineNumber: 2,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          NotesMessages.noteMovedToDifferentBook,
        ),
      ),
    );

    expect(database.note, original);
    expect(database.updates, 0);
    expect(database.listReads, 0);
  });
}
