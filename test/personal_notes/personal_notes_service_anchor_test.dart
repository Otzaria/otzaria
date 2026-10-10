import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class _MemoryNotesDb implements PersonalNotesDatabase {
  final notes = <String, PersonalNote>{};

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async =>
      notes.values.where((note) => note.bookId == bookId).toList();

  @override
  Future<void> insertNote(PersonalNote note) async => notes[note.id] = note;

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> changed) async {
    for (final note in changed) {
      notes[note.id] = note;
    }
  }

  @override
  Future<PersonalNote?> getNote(String id) async => notes[id];

  @override
  Future<void> updateNote(PersonalNote note) async => notes[note.id] = note;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('בחירה ללא פיסוק מאמצע השורה נשארת במקומה לאחר טעינה מחדש', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    const raw =
        'אחד שתים שלוש ארבע חמש שש שבע שמונה תשע רבי יוחנן, מאי דכתיב? עוד טקסט';
    final shown = removePunctuation(raw);
    final selected = shown
        .substring(shown.indexOf('רבי יוחנן'), shown.indexOf('עוד טקסט'))
        .trim();

    final added = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: selected,
    )).single;
    expect(added.anchorText, isNotNull);
    expect(added.status, PersonalNoteStatus.located);

    final reloaded = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: raw,
    )).single;
    expect(reloaded.status, PersonalNoteStatus.located);
    expect(reloaded.lineNumber, 1);
    expect(reloaded.anchorStart, raw.indexOf('רבי יוחנן'));
  });

  test('רמז המיקום של תצוגה בלי פיסוק עובר דרך שירות ההערות', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    final raw = '${List.filled(40, 'א,').join()} מילה משהו מילה';
    final shown = removePunctuation(raw);

    final note = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: 'מילה',
      selectionColumn: shown.lastIndexOf('מילה'),
      punctuationHidden: true,
    )).single;

    expect(note.anchorStart, raw.lastIndexOf('מילה'));
  });

  test('הערה ישנה שסומנה כחסרה בגלל פיסוק חוזרת לשורה המקורית', () async {
    final database = _MemoryNotesDb();
    final service = PersonalNotesService(database: database, random: Random(1));
    const raw =
        'אחד שתים שלוש ארבע חמש שש שבע שמונה תשע רבי יוחנן, מאי דכתיב? עוד טקסט';
    final shown = removePunctuation(raw);
    final selected = shown
        .substring(shown.indexOf('רבי יוחנן'), shown.indexOf('עוד טקסט'))
        .trim();
    final note = (await service.addNote(
      bookId: 'ספר',
      bookContent: raw,
      lineNumber: 1,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: selected,
    )).single;
    database.notes[note.id] = note.copyWith(
      clearAnchor: true,
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: 1,
    );

    final restored = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: raw,
    )).single;
    expect(restored.status, PersonalNoteStatus.located);
    expect(restored.lineNumber, 1);

    database.notes[note.id] = note.copyWith(
      clearAnchor: true,
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: 1,
    );
    final stillMissing = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: 'שורה אחרת בלי הביטוי המקורי',
    )).single;
    expect(stillMissing.status, PersonalNoteStatus.missing);
  });

  test(
    'הערה שאיבדה את מיקומה נשמרת ללא שורה, ומיקום מחדש מנקה את השורה הקודמת',
    () async {
      final database = _MemoryNotesDb();
      final service = PersonalNotesService(
        database: database,
        random: Random(1),
      );
      const book = 'שורה ראשונה בספר\nשורה שנייה עם רבי יוחנן';
      final note = (await service.addNote(
        bookId: 'ספר',
        bookContent: book,
        lineNumber: 2,
        content: 'הערה',
        contentPlain: 'הערה',
        contentFormat: PersonalNoteContentFormat.plain,
      )).single;

      final missing = (await service.loadNotes(
        bookId: 'ספר',
        bookContent: 'טקסט אחר לגמרי',
      )).single;
      expect(missing.status, PersonalNoteStatus.missing);
      expect(missing.lineNumber, isNull);
      expect(missing.lastKnownLineNumber, 2);
      expect(database.notes[note.id]!.lineNumber, isNull);

      database.notes[note.id] = note;
      final replaced = (await service.loadNotes(
        bookId: 'ספר',
        bookContent: 'שורה ראשונה בספר\nמשהו אחר לגמרי',
      )).single;
      expect(replaced.status, PersonalNoteStatus.missing);
      expect(replaced.lineNumber, isNull);
      expect(replaced.lastKnownLineNumber, 2);

      final moved = (await service.repositionNote(
        bookId: 'ספר',
        noteId: note.id,
        bookContent: book,
        lineNumber: 1,
      )).single;
      expect(moved.lineNumber, 1);
      expect(moved.lastKnownLineNumber, isNull);
    },
  );
}
