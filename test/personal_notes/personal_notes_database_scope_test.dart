import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

PersonalNote _note(
  String id, {
  int? line,
  int? endLine,
  PersonalNoteStatus status = PersonalNoteStatus.located,
}) => PersonalNote(
  id: id,
  bookId: 'ספר',
  lineNumber: line,
  endLineNumber: endLine,
  lastKnownLineNumber: null,
  status: status,
  content: id,
  contentPlain: id,
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_scope_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  test('הערת ספר וטווח שורות נשמרים ונקראים בחזרה', () async {
    await database.batchInsertNotes([
      _note('book', status: PersonalNoteStatus.book),
      _note('range', line: 3, endLine: 5),
    ]);
    final notes = {
      for (final note in await database.loadNotes('ספר')) note.id: note,
    };
    expect(notes['book']!.status, PersonalNoteStatus.book);
    expect(notes['range']!.endLineNumber, 5);
  });

  test('מסד קיים מקבל את עמודות המיקום בלי לאבד הערות', () async {
    final legacy = _note('legacy', line: 2);
    await database.insertNote(legacy);
    final db = await database.database;
    db.execute('ALTER TABLE personal_notes DROP COLUMN end_line_number');
    db.execute('ALTER TABLE personal_notes DROP COLUMN scope');
    await database.close();
    expect(await database.loadNotes('ספר'), [legacy]);
    final range = _note('range', line: 3, endLine: 5);
    final book = _note('book', status: PersonalNoteStatus.book);
    await database.batchInsertNotes([range, book]);
    await database.close();
    expect(await database.loadNotes('ספר'), containsAll([legacy, range, book]));
  });

  test('גרסה ישנה, שאינה מכירה את scope, קוראת הערת ספר כחסרת מיקום', () async {
    await database.insertNote(_note('book', status: PersonalNoteStatus.book));
    final db = await database.database;
    final row = db.select("SELECT status, scope FROM personal_notes").single;
    expect(row['status'], 'missing');
    expect(row['scope'], 'book');
  });

  test('קריאה שמתחילה אחרי בקשת סגירה מקבלת חיבור חדש', () async {
    final previous = await database.database;

    final closing = database.close();
    final reading = database.loadNotes('ספר');

    await closing;
    expect(await reading, isEmpty);
    expect(database.openDatabase, isNot(same(previous)));
  });

  test('סגירה באמצע פתיחה ממתינה לקריאה ומאפשרת פתיחה מחדש', () async {
    final firstReading = database.loadNotes('ספר');
    final closing = database.close();
    final secondReading = database.loadNotes('ספר');

    expect(await firstReading, isEmpty);
    await closing;
    expect(await secondReading, isEmpty);
    expect(database.openDatabase, isNotNull);
  });

  test('קריאה בזמן העברה ממתינה ופותחת את המסד במיקום החדש', () async {
    await database.insertNote(_note('old'));
    final moved = Completer<void>();
    addTearDown(() {
      if (!moved.isCompleted) moved.complete();
    });
    await database.close(reopenAfter: moved.future);
    final pendingRead = database.loadNotes('ספר');
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/new-databases',
    );

    expect(database.openDatabase, isNull);
    moved.complete();
    expect(await pendingRead, isEmpty);
    expect(
      await File('${root.path}/new-databases/personal_notes.db').exists(),
      isTrue,
    );
  });

  test('פתיחת המסד אינה חוסמת את ה-isolate הקורא (issue #5827)', () async {
    await database.loadNotes('ספר');
    final path = await AppPaths.resolveNotesDbPath('personal_notes.db');
    await database.close();
    final locker = sqlite3.open(path)..execute('BEGIN IMMEDIATE');
    // הנעילה משתחררת רק בטיימר של ה-isolate הזה; פתיחה עליו הייתה ממתינה לשווא.
    Timer(const Duration(milliseconds: 200), () {
      locker.execute('ROLLBACK');
      locker.close();
    });

    expect(await database.loadNotes('ספר'), isEmpty);
  });
}
