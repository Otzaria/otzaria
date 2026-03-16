import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiffReleaseAsset', () {
    test('parses DIFF asset names from GitHub release assets', () {
      final asset = DiffReleaseAsset.tryParse(
        {
          'name': '1-2.DIFF.zst',
          'browser_download_url':
              'https://github.com/Otzaria/SeforimLibrary/releases/download/v2/1-2.DIFF.zst',
        },
        releaseTag: 'v2',
        releaseName: 'Version 2',
      );

      expect(asset, isNotNull);
      expect(asset!.fromVersion, 1);
      expect(asset.toVersion, 2);
      expect(asset.assetName, '1-2.DIFF.zst');
    });

    test('ignores non diff assets', () {
      final asset = DiffReleaseAsset.tryParse(
        {
          'name': 'seforim.db.zip',
          'browser_download_url':
              'https://github.com/Otzaria/SeforimLibrary/releases/download/v2/seforim.db.zip',
        },
        releaseTag: 'v2',
        releaseName: 'Version 2',
      );

      expect(asset, isNull);
    });
  });

  group('FileSyncRepository.buildUpdateChain', () {
    test('builds contiguous update chain only', () {
      final chain = FileSyncRepository.buildUpdateChain(
        currentVersion: 1,
        availableAssets: const [
          DiffReleaseAsset(
            fromVersion: 1,
            toVersion: 2,
            assetName: '1-2.DIFF.zst',
            downloadUrl: 'https://example.com/1-2.DIFF.zst',
            releaseTag: 'v2',
            releaseName: 'Version 2',
          ),
          DiffReleaseAsset(
            fromVersion: 2,
            toVersion: 3,
            assetName: '2-3.DIFF.zst',
            downloadUrl: 'https://example.com/2-3.DIFF.zst',
            releaseTag: 'v3',
            releaseName: 'Version 3',
          ),
          DiffReleaseAsset(
            fromVersion: 4,
            toVersion: 5,
            assetName: '4-5.DIFF.zst',
            downloadUrl: 'https://example.com/4-5.DIFF.zst',
            releaseTag: 'v5',
            releaseName: 'Version 5',
          ),
        ],
      );

      expect(chain.map((asset) => asset.assetName), [
        '1-2.DIFF.zst',
        '2-3.DIFF.zst',
      ]);
    });

    test('stops at requested target version', () {
      final chain = FileSyncRepository.buildUpdateChain(
        currentVersion: 1,
        targetVersion: 3,
        availableAssets: const [
          DiffReleaseAsset(
            fromVersion: 1,
            toVersion: 2,
            assetName: '1-2.DIFF.zst',
            downloadUrl: 'https://example.com/1-2.DIFF.zst',
            releaseTag: 'v2',
            releaseName: 'Version 2',
          ),
          DiffReleaseAsset(
            fromVersion: 2,
            toVersion: 3,
            assetName: '2-3.DIFF.zst',
            downloadUrl: 'https://example.com/2-3.DIFF.zst',
            releaseTag: 'v3',
            releaseName: 'Version 3',
          ),
          DiffReleaseAsset(
            fromVersion: 3,
            toVersion: 4,
            assetName: '3-4.DIFF.zst',
            downloadUrl: 'https://example.com/3-4.DIFF.zst',
            releaseTag: 'v4',
            releaseName: 'Version 4',
          ),
        ],
      );

      expect(chain.map((asset) => asset.assetName), [
        '1-2.DIFF.zst',
        '2-3.DIFF.zst',
      ]);
    });

    test('does not allow skipping versions', () {
      final chain = FileSyncRepository.buildUpdateChain(
        currentVersion: 1,
        availableAssets: const [
          DiffReleaseAsset(
            fromVersion: 1,
            toVersion: 3,
            assetName: '1-3.DIFF.zst',
            downloadUrl: 'https://example.com/1-3.DIFF.zst',
            releaseTag: 'v3',
            releaseName: 'Version 3',
          ),
        ],
      );

      expect(chain, isEmpty);
    });
  });

  group('FileSyncRepository.splitSqlStatements', () {
    test('splits simple diff transaction into statements', () {
      const sql = '''
BEGIN TRANSACTION;
UPDATE db_meta SET value='2' WHERE "key"='content_version_int';
COMMIT;
''';

      expect(
        FileSyncRepository.splitSqlStatements(sql),
        [
          'BEGIN TRANSACTION',
          'UPDATE db_meta SET value=\'2\' WHERE "key"=\'content_version_int\'',
          'COMMIT',
        ],
      );
    });

    test('does not split semicolons inside strings', () {
      const sql = '''
UPDATE db_meta SET value='value;still-value' WHERE key='note';
''';

      expect(
        FileSyncRepository.splitSqlStatements(sql),
        [
          'UPDATE db_meta SET value=\'value;still-value\' WHERE key=\'note\'',
        ],
      );
    });
  });

  group('FileSyncRepository external catalog sync', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('otzaria-file-sync-test-');
      final libraryDir = Directory(
        path.join(tempDir.path, DatabaseConstants.otzariaFolderName),
      );
      await libraryDir.create(recursive: true);

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        tempDir.path,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        DatabaseConstants.otzariaFolderName,
      );

      final db = sqlite3.open(DatabaseConstants.getDatabasePath());
      db.execute('''
            CREATE TABLE db_meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
      db.execute(
        'INSERT INTO db_meta (key, value) VALUES (?, ?)',
        ['content_version_int', '3'],
      );
      db.close();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
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
