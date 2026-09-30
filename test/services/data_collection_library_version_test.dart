import 'dart:io';
import 'dart:isolate';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import '../helpers/memory_settings_cache.dart';
import '../helpers/zdb_fixture.dart';

/// `readLibraryVersion` נקרא גם מתהליכים שלא אתחלו את `SqliteDataProvider`
/// (פקודת `otzaria info`). הבדיקות מאמתות שהוא נשען על נתיב ה-DB בפועל ולא
/// על מצב הספק — הישענות כזו החזירה 'unknown' בכל תהליך headless.
void main() {
  late Directory libraryDir;

  Future<void> initSettings() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue(SettingsRepository.keyLibraryPath, libraryDir.path);
    await Settings.setValue(SettingsRepository.keyLibraryFolderName, '');
  }

  void seedDatabase({String? dbVersion}) {
    final db = sqlite3.sqlite3.open(
      p.join(libraryDir.path, DatabaseConstants.databaseFileName),
    );
    try {
      db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
      if (dbVersion != null) {
        db.execute('INSERT INTO schema_meta (key, value) VALUES (?, ?)', [
          'db_version',
          dbVersion,
        ]);
      }
    } finally {
      db.close();
    }
  }

  setUp(() async {
    libraryDir = await Directory.systemTemp.createTemp('otzaria-libver-test-');
    await initSettings();
  });

  tearDown(() async {
    try {
      await libraryDir.delete(recursive: true);
    } catch (_) {}
  });

  test('קורא db_version בלי אתחול SqliteDataProvider', () async {
    seedDatabase(dbVersion: '21');

    expect(await DataCollectionService().readLibraryVersion(), '21');
  });

  test('DB בלי db_version מחזיר unknown', () async {
    seedDatabase();

    expect(await DataCollectionService().readLibraryVersion(), 'unknown');
  });

  test('DB חסר מחזיר unknown ולא זורק', () async {
    expect(await DataCollectionService().readLibraryVersion(), 'unknown');
  });

  test('ספריית zdb נקראת מחוץ ל-isolate הקורא, ומסד רגיל עליו', () async {
    seedDatabase(dbVersion: '21');
    final plain = DataCollectionService(versionQuery: _isolateName);
    expect(await plain.readLibraryVersion(), Isolate.current.debugName);

    final zdb = p.join(libraryDir.path, DatabaseConstants.zdbDatabaseFileName);
    await writeFixtureZdb(zdb, version: 22);
    expect(
      await plain.readLibraryVersion(databasePath: zdb),
      isNot(Isolate.current.debugName),
    );
    // הקריאה האמיתית דרך zvfs ב-isolate.
    expect(
      await DataCollectionService().readLibraryVersion(databasePath: zdb),
      '22',
    );
  });
}

String? _isolateName(String dbPath) => Isolate.current.debugName;
