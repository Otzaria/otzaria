import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';

class _RecordingNotesDatabase extends Fake implements PersonalNotesDatabase {
  _RecordingNotesDatabase(this.note);

  PersonalNote note;
  int writes = 0;

  @override
  Future<PersonalNote?> getNote(String id) async => id == note.id ? note : null;

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

  test('פתיחה ושמירה דרך העורך בלי עריכה משמרות פורמט plain ותאריכים', () async {
    final original = _originalNote();
    final database = _RecordingNotesDatabase(original);
    final editor = buildPersonalNoteEditorController(
      initialContent: original.content,
      initialContentPlain: original.contentPlain,
      initialFormat: original.contentFormat,
    );
    addTearDown(editor.dispose);

    final result = editor.buildResult();
    expect(result.content, original.content);
    expect(result.contentPlain, original.contentPlain);
    expect(result.contentFormat, PersonalNoteContentFormat.plain);

    final saved = await PersonalNotesService(database: database).persistNote(
      bookId: original.bookId,
      bookContent: '',
      noteId: original.id,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
    );
    expect(saved.createdAt, original.createdAt);
    expect(saved.updatedAt, original.updatedAt);
    expect(database.writes, 1);
  });

  test('פתיחת Delta ללא עריכה משמרת את ה-JSON המקורי והתאריכים', () async {
    final canonicalDelta = jsonEncode([
      {'insert': 'אב״ג\n'},
    ]);
    final original = _originalNote().copyWith(
      content: canonicalDelta.replaceFirst('{"insert":', '{  "insert":'),
      contentPlain: 'אב״ג',
      contentFormat: PersonalNoteContentFormat.quillDelta,
    );
    final editor = buildPersonalNoteEditorController(
      initialContent: original.content,
      initialContentPlain: original.contentPlain,
      initialFormat: original.contentFormat,
    );
    addTearDown(editor.dispose);
    final result = editor.buildResult();
    expect(result.content, original.content);
    expect(result.contentPlain, original.contentPlain);
    expect(result.contentFormat, original.contentFormat);

    final saved = await PersonalNotesService(
      database: _RecordingNotesDatabase(original),
    ).persistNote(
      bookId: original.bookId,
      bookContent: '',
      noteId: original.id,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
    );
    expect(saved.createdAt, original.createdAt);
    expect(saved.updatedAt, original.updatedAt);
  });

  test('עיצוב, undo ו-redo: רק שינוי עיצוב פעיל מקדם את התאריך', () async {
    final original = _originalNote();
    final editor = buildPersonalNoteEditorController(
      initialContent: original.content,
      initialContentPlain: original.contentPlain,
      initialFormat: original.contentFormat,
    );
    addTearDown(editor.dispose);
    final controller = editor.quillController;

    controller.formatText(0, original.content.length, quill.Attribute.bold);
    final formatted = editor.buildResult();
    expect(formatted.contentFormat, PersonalNoteContentFormat.quillDelta);
    expect(formatted.contentPlain, original.contentPlain);

    controller.undo();
    final undone = editor.buildResult();
    expect(undone.content, original.content);
    expect(undone.contentFormat, original.contentFormat);
    final unchanged = await PersonalNotesService(
      database: _RecordingNotesDatabase(original),
    ).persistNote(
      bookId: original.bookId,
      bookContent: '',
      noteId: original.id,
      content: undone.content,
      contentPlain: undone.contentPlain,
      contentFormat: undone.contentFormat,
    );
    expect(unchanged.updatedAt, original.updatedAt);

    controller.redo();
    final redone = editor.buildResult();
    expect(redone.contentFormat, PersonalNoteContentFormat.quillDelta);
    final changed = await PersonalNotesService(
      database: _RecordingNotesDatabase(original),
    ).persistNote(
      bookId: original.bookId,
      bookContent: '',
      noteId: original.id,
      content: redone.content,
      contentPlain: redone.contentPlain,
      contentFormat: redone.contentFormat,
    );
    expect(changed.createdAt, original.createdAt);
    expect(changed.updatedAt.isAfter(original.updatedAt), isTrue);
  });

  test('שינוי טקסט בעורך Quill מקדם updatedAt ושומר createdAt', () async {
    final original = _originalNote();
    final editor = buildPersonalNoteEditorController(
      initialContent: original.content,
      initialContentPlain: original.contentPlain,
      initialFormat: original.contentFormat,
    );
    addTearDown(editor.dispose);
    editor.quillController.replaceText(
      0,
      0,
      'X',
      const TextSelection.collapsed(offset: 1),
    );
    final result = editor.buildResult();
    expect(result.contentFormat, PersonalNoteContentFormat.quillDelta);
    expect(result.contentPlain, 'XOriginal');

    final changed = await PersonalNotesService(
      database: _RecordingNotesDatabase(original),
    ).persistNote(
      bookId: original.bookId,
      bookContent: '',
      noteId: original.id,
      content: result.content,
      contentPlain: result.contentPlain,
      contentFormat: result.contentFormat,
    );
    expect(changed.createdAt, original.createdAt);
    expect(changed.updatedAt.isAfter(original.updatedAt), isTrue);
  });
}
