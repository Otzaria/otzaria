import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

/// מסד בסכמה חדשה מזו שהגרסה קוראת אינו נפתח, והספרייה מוצגת כחסומה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const readable = DatabaseConstants.readableDbSchemaVersion;
  late Directory tempDir;
  late String dbPath;

  void writeLibraryWithSchema(int? schema) {
    final fixture = SeforimFixtureDb.create(
      tempDir,
      SeforimFixtureVariant.full,
    );
    if (schema != null) {
      final db = sqlite3.sqlite3.open(fixture);
      try {
        db.execute(
          "INSERT OR REPLACE INTO schema_meta VALUES ('db_schema_version', ?)",
          ['$schema'],
        );
      } finally {
        db.close();
      }
    }
    File(fixture).renameSync(dbPath);
  }

  Future<void> openLibraryWithSchema(int? schema) async {
    writeLibraryWithSchema(schema);
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_schema_gate');
    final libraryPath = path.join(tempDir.path, 'library');
    await Directory(libraryPath).create(recursive: true);
    dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);

    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(path.join(tempDir.path, 'data_root'));
    await UserBooksDatabaseHolder.instance.close();
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(null);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('סכמה חדשה מהנתמכת — המסד אינו נפתח והספרייה חסומה', () async {
    await openLibraryWithSchema(readable + 1);

    final provider = SqliteDataProvider.instance;
    expect(provider.isInitialized, isFalse);
    expect(provider.repository, isNull);
    expect(provider.unsupportedDbSchemaVersion, readable + 1);
    expect(await NavigationRepository().checkLibraryIsEmpty(), isTrue);
    // החיבור נסגר: ב-Windows קובץ פתוח אינו ניתן למחיקה.
    await File(dbPath).delete();
  });

  test('הסכמה הנתמכת נפתחת כרגיל', () async {
    await openLibraryWithSchema(readable);

    final provider = SqliteDataProvider.instance;
    expect(provider.isInitialized, isTrue);
    expect(provider.unsupportedDbSchemaVersion, isNull);
    expect(await NavigationRepository().checkLibraryIsEmpty(), isFalse);
  });

  test('מסד ישן בלי db_schema_version נפתח כרגיל', () async {
    await openLibraryWithSchema(null);

    expect(SqliteDataProvider.instance.isInitialized, isTrue);
    expect(SqliteDataProvider.instance.unsupportedDbSchemaVersion, isNull);
  });

  // רענון הספרייה סוגר ובודק מיד, לפני שהקטלוג ברקע פותח את המסד מחדש.
  test('סגירת המסד משחררת את החסימה עד הפתיחה הבאה', () async {
    await openLibraryWithSchema(readable + 1);
    await SqliteDataProvider.instance.dispose();

    expect(SqliteDataProvider.instance.unsupportedDbSchemaVersion, isNull);
  });

  test('ספרייה נתמכת שנבחרה במקום החסומה משחררת את החסימה', () async {
    await openLibraryWithSchema(readable + 1);
    await File(dbPath).delete();
    writeLibraryWithSchema(readable);

    // כך מסך ההגדרה מרענן אחרי בחירת ספרייה: בלי פתיחה מחדש לפני הבדיקה.
    final navigation = NavigationRepository(reopenIndex: () async {});
    await navigation.refreshLibrary();
    expect(await navigation.checkLibraryIsEmpty(), isFalse);

    // הקטלוג נבנה ברקע, ופותח את המסד החדש.
    await DataRepository.instance.library;
    expect(SqliteDataProvider.instance.isInitialized, isTrue);
  });
}
