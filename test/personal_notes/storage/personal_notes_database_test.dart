import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
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
}
