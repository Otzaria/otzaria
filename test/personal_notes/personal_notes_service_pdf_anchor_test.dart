import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

/// מסד נתונים בזיכרון לבדיקה — מממש רק את ה-methods שה-service צורך.
class _InMemoryNotesDb implements PersonalNotesDatabase {
  final Map<String, PersonalNote> _notes = {};

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async =>
      _notes.values.where((n) => n.bookId == bookId).toList();

  @override
  Future<void> insertNote(PersonalNote note) async => _notes[note.id] = note;

  @override
  Future<void> updateNote(PersonalNote note) async => _notes[note.id] = note;

  @override
  Future<PersonalNote?> getNote(String noteId) async => _notes[noteId];

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> notes) async {
    for (final note in notes) {
      _notes[note.id] = note;
    }
  }

  @override
  Future<void> deleteNote(String noteId) async => _notes.remove(noteId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PersonalNotesService PDF anchoring (empty book content)', () {
    late _InMemoryNotesDb db;
    late PersonalNotesService service;

    setUp(() {
      db = _InMemoryNotesDb();
      service = PersonalNotesService(database: db, random: Random(1));
    });

    Future<void> addPdfNote(int page) => service.addNote(
          bookId: 'ספר PDF',
          bookContent: '', // PDF — אין תוכן טקסטואלי
          lineNumber: page,
          content: 'הערה לעמוד $page',
          contentPlain: 'הערה לעמוד $page',
          contentFormat: PersonalNoteContentFormat.plain,
        );

    test('שומר את מספר העמוד במקום לכווץ את כל ההערות לעמוד 1', () async {
      await addPdfNote(47);

      final saved = (await db.loadNotes('ספר PDF')).single;
      expect(saved.lineNumber, 47);
      expect(saved.status, PersonalNoteStatus.located);
    });

    test('הערות PDF שונות שומרות עמודים שונים', () async {
      await addPdfNote(47);
      await addPdfNote(12);

      final pages =
          (await db.loadNotes('ספר PDF')).map((n) => n.lineNumber).toSet();
      expect(pages, {47, 12});
    });

    test('טעינה מחדש לא מסמנת הערות PDF כחסרות', () async {
      await addPdfNote(47);

      final reloaded =
          await service.loadNotes(bookId: 'ספר PDF', bookContent: '');
      expect(reloaded.single.lineNumber, 47);
      expect(reloaded.single.status, PersonalNoteStatus.located);
    });
  });
}
