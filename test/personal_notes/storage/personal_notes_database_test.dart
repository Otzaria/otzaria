import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late List<Database> opened;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_open_test_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
    opened = [];
  });

  tearDown(() async {
    for (final connection in opened.toSet()) {
      if (!identical(connection, database.openDatabase)) connection.close();
    }
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  test('קריאות מקבילות בעת פתיחה חולקות חיבור יחיד שניתן לסגור', () async {
    opened = await Future.wait(List.generate(8, (_) => database.database));

    expect(
      opened.every((connection) => identical(connection, opened.first)),
      isTrue,
    );
    expect(identical(database.openDatabase, opened.first), isTrue);
    await database.close();
    expect(database.openDatabase, isNull);
    expect(() => opened.first.select('SELECT 1'), throwsStateError);
    opened.clear();
  });

  test('פתיחה מחדש אחרי סגירה יוצרת חיבור יחיד ושומרת את המסד', () async {
    final first = await database.database;
    await database.close();
    opened = await Future.wait(List.generate(8, (_) => database.database));

    expect(identical(opened.first, first), isFalse);
    expect(
      opened.every((connection) => identical(connection, opened.first)),
      isTrue,
    );
    expect(
      opened.first.select('PRAGMA table_info(personal_notes)'),
      isNotEmpty,
    );
  });

  test('זמני העדכון של כל ההערות זהים לאלה שבטעינה המלאה', () async {
    final notes = [
      for (var i = 0; i < 9; i++)
        PersonalNote(
          id: 'n$i',
          bookId: 'ספר ${i % 3}',
          lineNumber: i,
          lastKnownLineNumber: i,
          status: PersonalNoteStatus.located,
          content: 'תוכן',
          contentPlain: 'תוכן',
          contentFormat: PersonalNoteContentFormat.plain,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1, i, 0, 0, 0, i * 7),
        ),
    ];
    await database.batchInsertNotes(notes);

    final fromFullLoad = [
      for (final book in await database.listBooksWithNotes())
        for (final note in await database.loadNotes(book.bookId))
          note.updatedAt,
    ];
    final times = await database.listNoteUpdateTimes();

    expect(times, unorderedEquals(fromFullLoad));
    expect(times, hasLength(9));
  });

  test('הערות באותה שורה נשארות בסדר היצירה אחרי עריכה וטעינה מחדש', () async {
    final first = PersonalNote(
      id: 'first',
      bookId: 'ספר בדיקה',
      lineNumber: 2,
      lastKnownLineNumber: 2,
      status: PersonalNoteStatus.located,
      content: 'ראשונה',
      contentPlain: 'ראשונה',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final second = first.copyWith(
      id: 'second',
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    );
    final third = second.copyWith(id: 'third');
    final earlierLine = third.copyWith(id: 'earlier-line', lineNumber: 1);
    await database.batchInsertNotes([third, second, first, earlierLine]);
    final expected = ['earlier-line', 'first', 'second', 'third'];
    expect(
      (await database.loadNotes(first.bookId)).map((note) => note.id),
      expected,
    );
    await database.updateNote(first.copyWith(updatedAt: DateTime(2026, 2, 1)));
    await database.close();

    final reloaded = await database.loadNotes(first.bookId);
    expect(reloaded.map((note) => note.id), expected);
    expect(
      sortPersonalNotes(reloaded.reversed.toList()).map((note) => note.id),
      expected,
    );
  });

  test('מיון תאריכים משווה רגעים בזמן ושומר חסרות מיקום בסדר עדכון', () async {
    final instant = DateTime.utc(2026, 1, 1, 12);
    final utcNote = PersonalNote(
      id: 'a-utc',
      bookId: 'ספר בדיקה',
      lineNumber: 1,
      lastKnownLineNumber: 1,
      status: PersonalNoteStatus.located,
      content: 'תוכן',
      contentPlain: 'תוכן',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: instant,
      updatedAt: instant,
    );
    final localNote = utcNote.copyWith(
      id: 'b-local',
      createdAt: instant.toLocal(),
    );
    final missing = utcNote.copyWith(
      id: 'missing-old',
      status: PersonalNoteStatus.missing,
      clearLineNumber: true,
    );
    final newerMissing = missing.copyWith(
      id: 'missing-new',
      updatedAt: instant.add(const Duration(hours: 1)),
    );
    await database.batchInsertNotes([
      localNote,
      missing,
      newerMissing,
      utcNote,
    ]);

    final reloaded = await database.loadNotes(utcNote.bookId);
    expect(reloaded.map((note) => note.id), [
      'a-utc',
      'b-local',
      'missing-new',
      'missing-old',
    ]);
  });

  test('זמן עדכון פגום מדלג על השורה ולא מפיל את הספירה', () async {
    final db = await database.database;
    db.execute(
      "INSERT INTO personal_notes (id, book_id, status, content, created_at, updated_at) "
      "VALUES ('bad', 'ספר', 'located', '', '2026-01-01', 'לא תאריך'), "
      "('good', 'ספר', 'located', '', '2026-01-01', '2026-01-02T00:00:00.000')",
    );

    expect(await database.listNoteUpdateTimes(), [DateTime(2026, 1, 2)]);
  });
}
