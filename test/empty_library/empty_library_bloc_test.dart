import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmptyLibraryBloc', () {
    test('parseLatestDatabaseAsset מחזיר את asset של seforim.db.zst', () {
      final asset = EmptyLibraryBloc.parseLatestDatabaseAsset({
        'assets': [
          {
            'name': '1-2.DIFF.zst',
            'browser_download_url': 'https://example.com/1-2.DIFF.zst',
          },
          {
            'name': 'seforim.db.zst',
            'browser_download_url': 'https://example.com/seforim.db.zst',
          },
        ],
      });

      expect(asset, isNotNull);
      expect(asset!.assetName, 'seforim.db.zst');
      expect(asset.downloadUrl, 'https://example.com/seforim.db.zst');
    });

    test('DownloadLibraryRequested מוריד DB מהרליס האחרון ומחלץ אותו',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-empty-library-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );

      final downloadedBytes = utf8.encode('compressed-db');
      final talmudBytes = utf8.encode('compressed-talmud');
      final catalogBytes = utf8.encode('compressed-catalog');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {
                  'name': '2-3.DIFF.zst',
                  'browser_download_url':
                      'https://example.com/releases/2-3.DIFF.zst',
                },
                {
                  'name': 'seforim.db.zst',
                  'browser_download_url':
                      'https://example.com/releases/seforim.db.zst',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }

        if (request.url.toString() ==
            'https://example.com/releases/seforim.db.zst') {
          return http.Response.bytes(downloadedBytes, 200);
        }

        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('talmud_bavli_latest.tar.zst')) {
          return http.Response.bytes(talmudBytes, 200);
        }

        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('otzar-HB_catalog.db.zst')) {
          return http.Response.bytes(catalogBytes, 200);
        }

        return http.Response('not found', 404);
      });

      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath) async {
          // הקובץ הזמני חייב להיות בתיקיית temp של המערכת
          expect(archivePath, startsWith(Directory.systemTemp.path));
          // יכול להיות גם seforim.db.zst וגם otzar-HB_catalog.db.zst
          final basename = path.basename(archivePath);
          if (basename == 'otzaria_seforim.db.zst') {
            expect(await File(archivePath).readAsBytes(), downloadedBytes);
            expect(
              outputPath,
              path.join(tempDir.path, DatabaseConstants.databaseFileName),
            );
            await File(outputPath).writeAsBytes(const [1, 2, 3], flush: true);
          } else if (basename == 'otzaria_otzar-HB_catalog.db.zst') {
            expect(await File(archivePath).readAsBytes(), catalogBytes);
            await File(outputPath).writeAsBytes(const [4, 5, 6], flush: true);
          } else {
            fail('Unexpected archive: $archivePath');
          }
        },
        extractTarArchive: (archivePath, outputDir) async {
          expect(archivePath, startsWith(Directory.systemTemp.path));
          expect(path.basename(archivePath), 'otzaria_talmud_bavli.tar.zst');
          expect(await File(archivePath).readAsBytes(), talmudBytes);
          // לא יוצרים קבצי tar אמיתיים בטסט — מדמים חילוץ
        },
      );
      addTearDown(bloc.close);

      final directorySelectedFuture = bloc.stream
          .where((state) => state is EmptyLibraryDirectorySelected)
          .cast<EmptyLibraryDirectorySelected>()
          .first;

      bloc.add(DownloadLibraryRequested());

      final selectedState = await directorySelectedFuture.timeout(
        const Duration(seconds: 5),
      );

      expect(selectedState.selectedPath, tempDir.path);
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        tempDir.path,
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryFolderName),
        '',
      );
      // הקובץ הזמני נמחק אוטומטית
      expect(
        File(path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'))
            .existsSync(),
        isFalse,
      );
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
