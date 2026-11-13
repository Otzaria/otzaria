import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

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
  const line = '<b>וַיֹּאמֶר</b> אֱלֹהִים יְהִי אוֹר, וַיְהִי אוֹר';
  const source = 'וַיֹּאמֶר אֱלֹהִים יְהִי אוֹר, וַיְהִי אוֹר';
  const book =
      'שורה ראשונה\n$line\nוירא אלהים את האור כי טוב\nויבדל אלהים בין האור ובין החשך';

  late _MemoryNotesDb database;
  late PersonalNotesService service;

  setUp(() {
    database = _MemoryNotesDb();
    service = PersonalNotesService(database: database, random: Random(1));
  });

  Future<PersonalNote> add({
    int? lineNumber = 2,
    int? endLineNumber,
    String? selectedText,
    int? occurrenceIndex,
    bool requireWordAnchor = false,
    String content = book,
  }) async {
    final before = database.notes.keys.toSet();
    await service.addNote(
      bookId: 'ספר',
      bookContent: content,
      lineNumber: lineNumber,
      endLineNumber: endLineNumber,
      content: 'הערה',
      contentPlain: 'הערה',
      contentFormat: PersonalNoteContentFormat.plain,
      selectedText: selectedText,
      occurrenceIndex: occurrenceIndex,
      requireWordAnchor: requireWordAnchor,
    );
    return database.notes.values.singleWhere(
      (note) => !before.contains(note.id),
    );
  }

  Future<PersonalNote> move(
    PersonalNote note,
    PersonalNoteScope scope, {
    int? lineNumber,
    int? endLineNumber,
    String? sourceText,
    int? sourceOffset,
  }) => service.setNoteLocation(
    bookId: 'ספר',
    bookContent: book,
    noteId: note.id,
    scope: scope,
    lineNumber: lineNumber,
    endLineNumber: endLineNumber,
    sourceText: sourceText,
    sourceOffset: sourceOffset,
  );

  test('הערה עוברת בין מילים, שורות והספר כולו', () async {
    final note = await add();
    expect(note.scope, PersonalNoteScope.lines);

    final words = await move(
      note,
      PersonalNoteScope.words,
      lineNumber: 2,
      sourceText: 'אוֹר',
      sourceOffset: source.lastIndexOf('אוֹר'),
    );
    expect(words.scope, PersonalNoteScope.words);
    expect(words.anchorText, 'אור');
    expect(words.anchorStart, line.lastIndexOf('אוֹר'));
    expect(words.displayTitle, 'אור');

    final lines = await move(
      words,
      PersonalNoteScope.lines,
      lineNumber: 2,
      endLineNumber: 4,
    );
    expect(lines.scope, PersonalNoteScope.lines);
    expect((lines.lineNumber, lines.lastLineNumber), (2, 4));
    expect(lines.anchorText, isNull);
    expect(lines.coversLine(3), isTrue);

    final whole = await move(lines, PersonalNoteScope.book);
    expect(whole.scope, PersonalNoteScope.book);
    expect(whole.lineNumber, isNull);
    expect(whole.endLineNumber, isNull);
    expect(whole.hasLocation, isFalse);

    final reloaded = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: book,
    )).single;
    expect(reloaded.status, PersonalNoteStatus.book);
  });

  test('מיקום שאינו בספר, או מילים שאינן בשורה, אינם משנים את ההערה', () async {
    final note = await add();
    await expectLater(
      move(note, PersonalNoteScope.words, lineNumber: 2, sourceText: 'חושך'),
      throwsArgumentError,
    );
    await expectLater(
      move(note, PersonalNoteScope.lines, lineNumber: 3, endLineNumber: 9),
      throwsArgumentError,
    );
    expect(database.notes[note.id], note);
  });

  test('הערה על הספר נוצרת בלי שורה ובלי תוכן הספר', () async {
    final note = await add(lineNumber: null, content: '');
    expect(note.status, PersonalNoteStatus.book);
    expect(note.lineNumber, isNull);
    expect(note.displayTitle, isNull);
    expect(note.title, 'הערה', reason: 'הכותרת היא תחילת התוכן');
  });

  test('הערה על כמה שורות, ובחירה שחוצה שורות', () async {
    final range = await add(lineNumber: 3, endLineNumber: 9);
    expect((range.lineNumber, range.endLineNumber), (3, 4));

    final selected = await add(selectedText: 'וַיְהִי אוֹר\nוירא אלהים');
    expect((selected.lineNumber, selected.endLineNumber), (2, 3));
    expect(selected.isWordAnchored, isFalse);
    expect(selected.displayTitle, isNot(contains('וירא')));

    final reloaded = await service.loadNotes(bookId: 'ספר', bookContent: book);
    expect(
      reloaded.where((note) => note.id == selected.id).single.status,
      PersonalNoteStatus.located,
    );
  });

  test('בחירה שאינה ממשיכה בשורה הבאה נשארת בשורה אחת', () async {
    final note = await add(selectedText: 'אחר לגמרי');
    expect(note.endLineNumber, isNull);
  });

  test('הערה על כמה שורות זזה כולה כשהספר משתנה', () async {
    final note = await add(lineNumber: 3, endLineNumber: 4);
    final shifted = 'שורה חדשה\n$book';
    final reloaded = (await service.loadNotes(
      bookId: 'ספר',
      bookContent: shifted,
    )).single;
    expect(reloaded.id, note.id);
    expect((reloaded.lineNumber, reloaded.endLineNumber), (4, 5));
  });

  test('occurrenceIndex בוחר מופע, ומופע שאינו קיים אינו יוצר הערה', () async {
    final second = await add(
      selectedText: 'אור',
      occurrenceIndex: 1,
      requireWordAnchor: true,
    );
    expect(second.anchorStart, line.lastIndexOf('אוֹר'));

    await expectLater(
      add(selectedText: 'אור', occurrenceIndex: 2, requireWordAnchor: true),
      throwsArgumentError,
    );
    expect(database.notes, hasLength(1));
  });

  test('JSON: הערת ספר נשמרת כ-missing עם scope, וחוזרת כהערת ספר', () async {
    final note = await add(lineNumber: null, content: '');
    final json = note.toJson();
    expect(json['status'], 'missing');
    expect(json['scope'], 'book');
    expect(PersonalNote.fromJson(json), note);

    final range = await add(lineNumber: 3, endLineNumber: 4);
    expect(PersonalNote.fromJson(range.toJson()).endLineNumber, 4);
  });
}
