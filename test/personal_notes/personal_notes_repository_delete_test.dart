import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../test_helpers/memory_cache_provider.dart';

const _bookId = 'ספר בדיקה';

class _CountingFiles extends Fake implements FileSystemData {
  int textReads = 0;

  @override
  Future<String> getBookText(
    String title, {
    int? categoryId,
    String? fileType,
  }) async {
    textReads++;
    return 'שורה ראשונה\nשורה שנייה';
  }
}

PersonalNote _note(String id) => PersonalNote(
  id: id,
  bookId: _bookId,
  lineNumber: 1,
  displayTitle: 'שורה ראשונה',
  lastKnownLineNumber: null,
  status: PersonalNoteStatus.located,
  content: 'תוכן $id',
  contentPlain: 'תוכן $id',
  contentFormat: PersonalNoteContentFormat.plain,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final database = PersonalNotesDatabase.instance;
  late Directory root;
  late _CountingFiles files;
  late PersonalNotesRepository repository;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await database.close();
    root = await Directory.systemTemp.createTemp('notes_repository_delete_');
    AppPaths.debugOverrideDataRootPath(root.path);
    await Settings.setValue(
      SettingsRepository.keyDatabasesPath,
      '${root.path}/databases',
    );
    files = _CountingFiles();
    repository = PersonalNotesRepository(fileSystemData: files);
    await database.batchInsertNotes([_note('a'), _note('b')]);
  });

  tearDown(() async {
    await database.close();
    AppPaths.debugOverrideDataRootPath(null);
    await Settings.setValue(SettingsRepository.keyDatabasesPath, '');
    await root.delete(recursive: true);
  });

  test('מחיקת הערה אינה קוראת את תוכן הספר', () async {
    await repository.deleteNote(bookId: _bookId, noteId: 'a');

    expect(files.textReads, 0);
  });

  test('מחיקה מאושרת אינה קוראת את תוכן הספר', () async {
    await repository.removeNote(noteId: 'a');

    expect(files.textReads, 0);
    expect(await database.getNote('a'), isNull);
    expect((await database.loadNotes(_bookId)).map((note) => note.id), ['b']);
  });

  test('מחיקת הערה מחזירה את שאר הערות הספר', () async {
    final remaining = await repository.deleteNote(
      bookId: _bookId,
      noteId: 'a',
    );

    expect(remaining.map((note) => note.id), ['b']);
    expect(await database.getNote('a'), isNull);
  });

  test('טעינת הערות עדיין קוראת את תוכן הספר', () async {
    await repository.loadNotes(_bookId);

    expect(files.textReads, 1);
  });
}
