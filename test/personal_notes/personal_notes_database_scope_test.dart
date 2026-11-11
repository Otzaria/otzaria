import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
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

  test('גרסה ישנה, שאינה מכירה את scope, קוראת הערת ספר כחסרת מיקום', () async {
    await database.insertNote(_note('book', status: PersonalNoteStatus.book));
    final db = await database.database;
    final row = db.select("SELECT status, scope FROM personal_notes").single;
    expect(row['status'], 'missing');
    expect(row['scope'], 'book');
  });
}
