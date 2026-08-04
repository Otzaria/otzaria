import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/sync/file_sync_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/custom_folders/custom_folder.dart';
import 'package:path/path.dart' as path;

/// בדיקת קצה-לקצה לתלונה "user_books.db לא מתכווץ": כיבוי "הוסף למסד
/// הנתונים" מוחק את תוכן הספרים, וצריך גם להקטין את הקובץ בפועל.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late String customFolderPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'otzaria-file-sync-compaction-',
    );
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    FileSyncService.resetSingletonForTesting();
    database = MyDatabase.withPath(path.join(tempDir.path, 'user_books.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();

    final libraryPath = path.join(tempDir.path, 'library');
    customFolderPath = path.join(tempDir.path, 'ספרים אישיים');
    await Directory(path.join(libraryPath, 'אוצריא')).create(recursive: true);
    await Directory(customFolderPath).create(recursive: true);

    // ספר גדול דיו כדי לחצות את סף הכיווץ (1MB פנוי ולפחות רבע מהקובץ).
    final line = '${'א' * 200}\n';
    await File(
      path.join(customFolderPath, 'ספר גדול.txt'),
    ).writeAsString(line * 12000);

    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
  });

  tearDown(() async {
    database.close();
    FileSyncService.resetSingletonForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> setFolderStorage({required bool addToDatabase}) =>
      Settings.setValue<String>(
        SettingsRepository.keyCustomFolders,
        CustomFoldersManager.saveFolders([
          CustomFolder(
            path: customFolderPath,
            addToDatabase: addToDatabase,
            addedAt: DateTime(2026, 4, 13),
          ),
        ]),
      );

  Future<void> sync() async {
    FileSyncService.resetSingletonForTesting();
    final service = await FileSyncService.getInstance(
      repository,
      userBooksRepository: repository,
    );
    final result = await service!.syncFiles();
    expect(result.errors, isEmpty);
  }

  /// גודל הקובץ על הדיסק. ב-WAL הכתיבות יושבות ביומן עד checkpoint, ולכן
  /// בלי זה המדידה משקפת מצב ישן.
  Future<int> dbFileSize() async {
    (await database.database).execute('PRAGMA wal_checkpoint(TRUNCATE)');
    return File(path.join(tempDir.path, 'user_books.db')).lengthSync();
  }

  test('כיבוי "הוסף למסד הנתונים" מקטין את user_books.db בפועל', () async {
    await setFolderStorage(addToDatabase: true);
    await sync();
    final sizeWithContent = await dbFileSize();
    expect(
      sizeWithContent,
      greaterThan(2 * 1024 * 1024),
      reason: 'תוכן הספר אמור להיות ב-DB',
    );

    await setFolderStorage(addToDatabase: false);
    await sync();

    final db = await database.database;
    expect(
      db.select('SELECT count(*) FROM line').first.values.first,
      0,
      reason: 'התוכן נמחק — הספר נקרא מהקובץ',
    );
    expect(
      await dbFileSize(),
      lessThan(sizeWithContent ~/ 2),
      reason: 'הקובץ חייב להתכווץ, לא רק להשתחרר ל-freelist',
    );
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
