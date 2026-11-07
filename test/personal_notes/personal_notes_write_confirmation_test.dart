import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

const _bookId = 'ספר בדיקת שמירה';
const _bookContent = 'פתיחה\nמקטע מדויק לסימון\nסיום';

class _ControlledDatabase extends Fake implements PersonalNotesDatabase {
  final notes = <String, PersonalNote>{};
  bool failReads = true;
  bool failInsert = false;
  bool failDelete = false;
  bool failUpdate = false;
  int listReads = 0;
  int inserts = 0;
  int updates = 0;
  int deletes = 0;

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async {
    listReads++;
    if (failReads) throw StateError('list refresh failed after the write');
    return notes.values.where((note) => note.bookId == bookId).toList();
  }

  @override
  Future<PersonalNote?> getNote(String id) async => notes[id];

  @override
  Future<void> insertNote(PersonalNote note) async {
    inserts++;
    if (failInsert) throw StateError('insert failed');
    notes[note.id] = note;
  }

  @override
  Future<void> updateNote(PersonalNote note) async {
    updates++;
    if (failUpdate) throw StateError('update failed');
    if (!notes.containsKey(note.id)) throw StateError('note no longer exists');
    notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(String noteId) async {
    deletes++;
    if (failDelete) throw StateError('delete failed');
    notes.remove(noteId);
  }

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> changed) async {
    for (final note in changed) {
      await updateNote(note);
    }
  }
}

class _DeleteBeforeUpdateDatabase extends Fake
    implements PersonalNotesDatabase {
  _DeleteBeforeUpdateDatabase(this.delegate);

  final PersonalNotesDatabase delegate;

  @override
  Future<PersonalNote?> getNote(String id) => delegate.getNote(id);

  @override
  Future<void> updateNote(PersonalNote note) async {
    // A real concurrent deletion after the service read the original record.
    await delegate.deleteNote(note.id);
    await delegate.updateNote(note);
  }
}

PersonalNote _note({String bookId = _bookId}) => PersonalNote(
  id: 'existing-note',
  bookId: bookId,
  lineNumber: 2,
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: 'תוכן קודם',
  contentPlain: 'תוכן קודם',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Future<PersonalNote> _create(PersonalNotesService service) =>
    service.createNote(
      bookId: _bookId,
      bookContent: _bookContent,
      lineNumber: 2,
      selectedText: 'מקטע מדויק',
      content: 'תוכן חדש  \n',
      contentPlain: 'תוכן חדש  \n',
      contentFormat: PersonalNoteContentFormat.plain,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'create confirms one committed write without reading the list',
    () async {
      final database = _ControlledDatabase();
      final service = PersonalNotesService(
        database: database,
        random: Random(1),
      );

      final created = await _create(service);

      expect(database.inserts, 1);
      expect(database.listReads, 0);
      expect(database.notes.values, [created]);
      expect(created.bookId, _bookId);
      expect(created.lineNumber, 2);
      expect(created.contentPlain, 'תוכן חדש');
      expect(created.anchorText, 'מקטע מדויק');
      expect(created.createdAt, created.updatedAt);

      database.failReads = false;
      expect(await database.loadNotes(_bookId), [created]);
    },
  );

  test(
    'an unsuccessful insert still fails and is never acknowledged',
    () async {
      final database = _ControlledDatabase()..failInsert = true;
      final service = PersonalNotesService(database: database);

      await expectLater(_create(service), throwsStateError);

      expect(database.inserts, 1);
      expect(database.notes, isEmpty);
      expect(database.listReads, 0);
    },
  );

  test(
    'persist confirms and reconciles the edited note before the write',
    () async {
      final database = _ControlledDatabase();
      final service = PersonalNotesService(
        database: database,
        random: Random(1),
      );
      final created = await _create(service);
      final unrelated = _note().copyWith(id: 'unrelated-note');
      database.notes[unrelated.id] = unrelated;

      final updated = await service.persistNote(
        bookId: _bookId,
        bookContent: 'כותרת נוספת\n$_bookContent',
        noteId: created.id,
        content: 'תוכן ערוך\n',
        contentPlain: 'תוכן ערוך\n',
        contentFormat: PersonalNoteContentFormat.plain,
      );

      expect(database.updates, 1);
      expect(database.listReads, 0);
      expect(updated.id, created.id);
      expect(updated.createdAt, created.createdAt);
      expect(updated.contentPlain, 'תוכן ערוך');
      expect(updated.lineNumber, 3);
      expect(updated.status, PersonalNoteStatus.located);
      expect(database.notes[updated.id], updated);
      expect(database.notes[unrelated.id], unrelated);
    },
  );

  test(
    'persist refuses an already deleted note instead of reporting success',
    () async {
      final database = _ControlledDatabase();
      final service = PersonalNotesService(database: database);

      await expectLater(
        service.persistNote(
          bookId: _bookId,
          bookContent: _bookContent,
          noteId: 'deleted-note',
          content: 'תוכן ערוך',
        ),
        throwsStateError,
      );

      expect(database.updates, 0);
      expect(database.listReads, 0);
      expect(database.notes, isEmpty);
    },
  );

  test('persist refuses an id belonging to a different book', () async {
    final database = _ControlledDatabase();
    final original = _note(bookId: 'ספר אחר');
    database.notes[original.id] = original;
    final service = PersonalNotesService(database: database);

    await expectLater(
      service.persistNote(
        bookId: _bookId,
        bookContent: _bookContent,
        noteId: original.id,
        content: 'תוכן ערוך',
      ),
      throwsStateError,
    );

    expect(database.updates, 0);
    expect(database.listReads, 0);
    expect(database.notes[original.id], original);
  });

  test(
    'compatibility add and update APIs still return refreshed lists',
    () async {
      final database = _ControlledDatabase()..failReads = false;
      final existing = _note();
      database.notes[existing.id] = existing;
      final service = PersonalNotesService(
        database: database,
        random: Random(1),
      );

      final added = await service.addNote(
        bookId: _bookId,
        bookContent: _bookContent,
        lineNumber: 3,
        content: 'הערה נוספת',
        contentPlain: 'הערה נוספת',
        contentFormat: PersonalNoteContentFormat.plain,
      );
      expect(added, hasLength(2));
      expect(added.map((note) => note.id), contains(existing.id));
      final created = added.singleWhere((note) => note.id != existing.id);

      final updated = await service.updateNote(
        bookId: _bookId,
        bookContent: _bookContent,
        noteId: created.id,
        content: 'הערה נוספת מעודכנת',
        contentPlain: 'הערה נוספת מעודכנת',
      );
      expect(updated, hasLength(2));
      expect(
        updated.singleWhere((note) => note.id == created.id).contentPlain,
        'הערה נוספת מעודכנת',
      );
      expect(database.listReads, 2);
    },
  );

  test('delete confirms a committed write without reading the list', () async {
    final original = _note();
    final retained = original.copyWith(id: 'retained-note');
    final database = _ControlledDatabase()
      ..notes[original.id] = original
      ..notes[retained.id] = retained;
    final service = PersonalNotesService(database: database);

    await service.removeNote(noteId: original.id);

    expect(database.deletes, 1);
    expect(database.listReads, 0);
    expect(database.notes.values, [retained]);
    await expectLater(database.loadNotes(_bookId), throwsStateError);
    expect(database.notes.values, [retained]);
  });

  test('a failed delete is not acknowledged', () async {
    final original = _note();
    final database = _ControlledDatabase()
      ..notes[original.id] = original
      ..failDelete = true;
    final service = PersonalNotesService(database: database);

    await expectLater(
      service.removeNote(noteId: original.id),
      throwsStateError,
    );

    expect(database.deletes, 1);
    expect(database.listReads, 0);
    expect(database.notes.values, [original]);
  });

  test(
    'reposition confirms a committed write without reading the list',
    () async {
      final database = _ControlledDatabase();
      final service = PersonalNotesService(database: database);
      final original = await _create(service);
      final retained = _note();
      database.notes[retained.id] = retained;

      final moved = await service.moveNote(
        bookId: _bookId,
        bookContent: _bookContent,
        noteId: original.id,
        lineNumber: 3,
      );

      expect(database.updates, 1);
      expect(database.listReads, 0);
      expect(database.notes[original.id], moved);
      expect(database.notes[retained.id], retained);
      expect(moved.lineNumber, 3);
      expect(moved.status, PersonalNoteStatus.located);
      expect(moved.anchorText, isNull);
      expect(moved.createdAt, original.createdAt);
      expect(moved.content, original.content);
      await expectLater(database.loadNotes(_bookId), throwsStateError);
      expect(database.notes[original.id], moved);
    },
  );

  test('a failed reposition is not acknowledged', () async {
    final original = _note();
    final database = _ControlledDatabase()
      ..notes[original.id] = original
      ..failUpdate = true;
    final service = PersonalNotesService(database: database);

    await expectLater(
      service.moveNote(
        bookId: _bookId,
        bookContent: _bookContent,
        noteId: original.id,
        lineNumber: 3,
      ),
      throwsStateError,
    );

    expect(database.updates, 1);
    expect(database.listReads, 0);
    expect(database.notes.values, [original]);
  });

  test('compatibility mutations still return refreshed lists', () async {
    final original = _note();
    final retained = original.copyWith(id: 'retained-note');
    final database = _ControlledDatabase()
      ..failReads = false
      ..notes[original.id] = original
      ..notes[retained.id] = retained;
    final service = PersonalNotesService(database: database);

    final moved = await service.repositionNote(
      bookId: _bookId,
      bookContent: _bookContent,
      noteId: original.id,
      lineNumber: 3,
    );
    expect(moved, hasLength(2));
    expect(moved.singleWhere((note) => note.id == original.id).lineNumber, 3);
    expect(moved, contains(retained));

    final remaining = await service.deleteNote(
      bookId: _bookId,
      noteId: original.id,
    );
    expect(remaining, [retained]);
    expect(database.listReads, 2);
  });

  for (final reposition in [false, true]) {
    test(
      'list-returning ${reposition ? "reposition" : "delete"} still reports a refresh failure',
      () async {
        final original = _note();
        final database = _ControlledDatabase()..notes[original.id] = original;
        final service = PersonalNotesService(database: database);

        await expectLater(
          reposition
              ? service.repositionNote(
                  bookId: _bookId,
                  bookContent: _bookContent,
                  noteId: original.id,
                  lineNumber: 3,
                )
              : service.deleteNote(bookId: _bookId, noteId: original.id),
          throwsStateError,
        );

        expect(database.listReads, 1);
        if (reposition) {
          expect(database.notes[original.id]!.lineNumber, 3);
        } else {
          expect(database.notes, isEmpty);
        }
      },
    );
  }

  group('real SQLite write confirmation', () {
    final database = PersonalNotesDatabase.instance;
    late Directory temporaryRoot;

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await database.close();
      temporaryRoot = await Directory.systemTemp.createTemp(
        'note_write_confirmation_',
      );
      AppPaths.debugOverrideDataRootPath(temporaryRoot.path);
      await Settings.setValue(
        SettingsRepository.keyDatabasesPath,
        '${temporaryRoot.path}/databases',
      );
    });

    tearDown(() async {
      await database.close();
      AppPaths.debugOverrideDataRootPath(null);
      await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
      await temporaryRoot.delete(recursive: true);
    });

    test(
      'an UPDATE after DELETE is rejected without a success notification',
      () async {
        final note = _note();
        await database.insertNote(note);
        await database.deleteNote(note.id);
        final revisionAfterDelete = database.revision.value;

        await expectLater(
          database.updateNote(note.copyWith(content: 'תוכן שלא נשמר')),
          throwsStateError,
        );

        expect(await database.getNote(note.id), isNull);
        expect(database.revision.value, revisionAfterDelete);
      },
    );

    test(
      'persist also detects deletion between its initial read and UPDATE',
      () async {
        final note = _note();
        await database.insertNote(note);
        final revisionBeforeDelete = database.revision.value;
        final service = PersonalNotesService(
          database: _DeleteBeforeUpdateDatabase(database),
        );

        await expectLater(
          service.persistNote(
            bookId: note.bookId,
            bookContent: _bookContent,
            noteId: note.id,
            content: 'תוכן ערוך',
            contentPlain: 'תוכן ערוך',
          ),
          throwsStateError,
        );

        expect(await database.getNote(note.id), isNull);
        expect(database.revision.value, revisionBeforeDelete + 1);
      },
    );

    test(
      'reposition detects deletion between its initial read and UPDATE',
      () async {
        final note = _note();
        await database.insertNote(note);
        final revisionBeforeDelete = database.revision.value;
        final service = PersonalNotesService(
          database: _DeleteBeforeUpdateDatabase(database),
        );

        await expectLater(
          service.moveNote(
            bookId: note.bookId,
            bookContent: _bookContent,
            noteId: note.id,
            lineNumber: 3,
          ),
          throwsStateError,
        );

        expect(await database.getNote(note.id), isNull);
        expect(database.revision.value, revisionBeforeDelete + 1);
      },
    );
  });
}
