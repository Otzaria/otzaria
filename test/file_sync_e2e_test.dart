import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/dao/daos/database.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

const _runE2ETest = bool.fromEnvironment(
  'OTZARIA_RUN_E2E_SYNC_TEST',
  defaultValue: false,
);
const _sourceDbPath = String.fromEnvironment(
  'OTZARIA_TEST_SOURCE_DB',
  defaultValue: '/Users/david/Documents/seforim.db',
);
const _expectedDbPath = String.fromEnvironment(
  'OTZARIA_TEST_EXPECTED_DB',
  defaultValue: '/Users/david/Documents/seforim_V3.db',
);
const _targetVersion = int.fromEnvironment(
  'OTZARIA_TEST_TARGET_VERSION',
  defaultValue: 3,
);
const _keepSandbox = bool.fromEnvironment(
  'OTZARIA_KEEP_E2E_SANDBOX',
  defaultValue: false,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('File sync E2E', () {
    test(
      'updates V2 database from GitHub DIFF and matches expected V3 database',
      () async {
        final sourceDbFile = File(_sourceDbPath);
        final expectedDbFile = File(_expectedDbPath);

        expect(
          await sourceDbFile.exists(),
          isTrue,
          reason: 'DB המקור לא נמצא בנתיב $_sourceDbPath',
        );
        expect(
          await expectedDbFile.exists(),
          isTrue,
          reason: 'DB היעד לא נמצא בנתיב $_expectedDbPath',
        );

        final sandbox = await Directory.systemTemp.createTemp(
          'otzaria-file-sync-e2e-',
        );
        // Useful for post-mortem investigation when the test is run manually.
        // ignore: avoid_print
        print('E2E sandbox: ${sandbox.path}');
        addTearDown(() async {
          await SqliteDataProvider.instance.dispose();
          if (!_keepSandbox && await sandbox.exists()) {
            await sandbox.delete(recursive: true);
          }
        });

        final libraryRoot = Directory(
          p.join(sandbox.path, DatabaseConstants.otzariaFolderName),
        );
        await libraryRoot.create(recursive: true);

        final workingDbPath =
            p.join(libraryRoot.path, DatabaseConstants.databaseFileName);
        final expectedCopyPath = p.join(sandbox.path, 'expected_v3.db');

        await sourceDbFile.copy(workingDbPath);
        await expectedDbFile.copy(expectedCopyPath);

        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          sandbox.path,
        );
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          DatabaseConstants.otzariaFolderName,
        );
        await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
        await Settings.setValue<bool>(SettingsRepository.keyAutoSync, false);

        MyDatabase();
        await SqliteDataProvider.instance.dispose();

        expect(await _readDbVersion(workingDbPath), 2);
        expect(await _readDbVersion(expectedCopyPath), _targetVersion);

        final repository = FileSyncRepository(
          githubOwner: 'Otzaria',
          repositoryName: 'SeforimLibrary',
          decompressDiff: _decompressWithSystemZstd,
        );

        final updates = await repository.checkForUpdates(
          targetVersion: _targetVersion,
        );
        expect(updates, isNotEmpty);
        expect(
          updates.last,
          '${_targetVersion - 1}-$_targetVersion.DIFF.zst',
        );

        final appliedCount = await repository.syncFiles(
          targetVersion: _targetVersion,
        );
        expect(appliedCount, greaterThan(0));

        await SqliteDataProvider.instance.dispose();

        expect(await _readDbVersion(workingDbPath), _targetVersion);
        expect(await _runSqliteScalar(workingDbPath, 'PRAGMA integrity_check;'),
            'ok');

        final updatedHash =
            await _runSqliteScalar(workingDbPath, '.sha3sum --schema');
        final expectedHash =
            await _runSqliteScalar(expectedCopyPath, '.sha3sum --schema');

        expect(updatedHash, expectedHash);
      },
      skip: _runE2ETest
          ? false
          : 'מבחן E2E חיצוני. להפעלה: flutter test test/file_sync_e2e_test.dart '
              '--dart-define=OTZARIA_RUN_E2E_SYNC_TEST=true',
      timeout: const Timeout(Duration(minutes: 5)),
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

Future<Uint8List> _decompressWithSystemZstd(Uint8List compressedBytes) async {
  final tempDir = await Directory.systemTemp.createTemp('otzaria-zstd-');
  try {
    final compressedFile = File(p.join(tempDir.path, 'update.diff.zst'));
    await compressedFile.writeAsBytes(compressedBytes, flush: true);

    final result = await Process.run(
      'zstd',
      ['-dc', compressedFile.path],
      stdoutEncoding: null,
    );

    if (result.exitCode != 0) {
      throw Exception('zstd נכשל: ${(result.stderr as String?)?.trim()}');
    }

    return Uint8List.fromList(result.stdout as List<int>);
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

Future<int> _readDbVersion(String dbPath) async {
  final version = await _runSqliteScalar(
    dbPath,
    "SELECT value FROM db_meta WHERE key='content_version_int';",
  );
  final parsed = int.tryParse(version);
  if (parsed == null) {
    throw Exception('לא ניתן לקרוא את גרסת ה-DB מתוך $dbPath');
  }
  return parsed;
}

Future<String> _runSqliteScalar(String dbPath, String command) async {
  final result = await Process.run('sqlite3', [dbPath, command]);
  if (result.exitCode != 0) {
    throw Exception(
      'sqlite3 נכשל עבור $dbPath: ${result.stderr}'.trim(),
    );
  }

  return (result.stdout as String).trim();
}
