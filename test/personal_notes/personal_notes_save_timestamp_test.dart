import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

class _RecordingNotesDatabase extends Fake implements PersonalNotesDatabase {
  _RecordingNotesDatabase(this.note);

  PersonalNote note;
  int writes = 0;

  @override
  Future<PersonalNote?> getNote(String id) async =>
      id == note.id ? note : null;

  @override
  Future<void> updateNote(PersonalNote updated) async {
    writes++;
    note = updated;
  }
}

PersonalNote _originalNote() => PersonalNote(
  id: 'note-1',
  bookId: 'book',
  lineNumber: 1,
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: 'Original',
  contentPlain: 'Original',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2025, 1, 1),
);

void main() {
  test('שמירה ללא שינוי משמרת את מועדי היצירה והעדכון', () async {
    final original = _originalNote();
    final database = _RecordingNotesDatabase(original);
    final service = PersonalNotesService(database: database);

    final saved = await service.persistNote(
      bookId: 'book',
      bookContent: '',
      noteId: original.id,
      content: 'Original   ',
      contentPlain: 'Original ',
      contentFormat: PersonalNoteContentFormat.plain,
    );

    expect(saved.createdAt, original.createdAt);
    expect(saved.updatedAt, original.updatedAt);
    expect(database.note, saved);
    // לא מדלגים על כתיבת המסד: אישור הכתיבה ובדיקות קיום ההערה נשמרים.
    expect(database.writes, 1);
  });

  test('שינוי תוכן אמיתי מעדכן את מועד העריכה בלבד', () async {
    final original = _originalNote();
    final database = _RecordingNotesDatabase(original);
    final service = PersonalNotesService(database: database);

    final saved = await service.persistNote(
      bookId: 'book',
      bookContent: '',
      noteId: original.id,
      content: 'Changed',
      contentPlain: 'Changed',
      contentFormat: PersonalNoteContentFormat.plain,
    );

    expect(saved.content, 'Changed');
    expect(saved.createdAt, original.createdAt);
    expect(saved.updatedAt.isAfter(original.updatedAt), isTrue);
    expect(database.writes, 1);
  });

  test('שינוי פורמט בלבד נחשב לעריכה גם בלי שינוי בטקסט', () async {
    final original = _originalNote();
    final database = _RecordingNotesDatabase(original);
    final service = PersonalNotesService(database: database);

    final saved = await service.persistNote(
      bookId: 'book',
      bookContent: '',
      noteId: original.id,
      content: original.content,
      contentPlain: original.contentPlain,
      contentFormat: PersonalNoteContentFormat.quillDelta,
    );

    expect(saved.contentFormat, PersonalNoteContentFormat.quillDelta);
    expect(saved.createdAt, original.createdAt);
    expect(saved.updatedAt.isAfter(original.updatedAt), isTrue);
    expect(database.writes, 1);
  });
}
