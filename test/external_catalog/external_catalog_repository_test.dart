import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExternalCatalogRepository', () {
    late Directory tempDir;
    late Directory libraryDir;
    late ExternalCatalogRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-external-catalog-test-',
      );
      libraryDir = Directory(
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

      repository = ExternalCatalogRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('parseLatestDatabaseAsset מעדיף את הקובץ הדחוס', () {
      final asset = ExternalCatalogRepository.parseLatestDatabaseAsset({
        'assets': [
          {
            'name': DatabaseConstants.externalCatalogDatabaseFileName,
            'browser_download_url': 'https://example.com/catalog.db',
          },
          {
            'name': DatabaseConstants.externalCatalogArchiveFileName,
            'browser_download_url': 'https://example.com/catalog.db.zst',
          },
        ],
      });

      expect(asset, isNotNull);
      expect(asset!.fileName, DatabaseConstants.externalCatalogArchiveFileName);
      expect(asset.isCompressed, isTrue);
    });

    test('parseLatestVersionAsset מזהה את version.txt', () {
      final asset = ExternalCatalogRepository.parseLatestVersionAsset({
        'assets': [
          {
            'name': DatabaseConstants.externalCatalogArchiveFileName,
            'browser_download_url': 'https://example.com/catalog.db.zst',
          },
          {
            'name': DatabaseConstants.externalCatalogVersionFileName,
            'browser_download_url': 'https://example.com/version.txt',
          },
        ],
      });

      expect(asset, isNotNull);
      expect(asset!.fileName, DatabaseConstants.externalCatalogVersionFileName);
      expect(asset.downloadUrl, 'https://example.com/version.txt');
    });

    test('getCurrentDatabaseVersion קורא את db_meta.version', () async {
      await _createCatalogDatabase(
        repository.databasePath,
        version: 3,
      );

      expect(await repository.getCurrentDatabaseVersion(), 3);
    });

    test('updateDatabaseIfNeeded מוריד DB חדש רק כשיש גרסה חדשה', () async {
      await _createCatalogDatabase(
        repository.databasePath,
        version: 3,
      );

      final remoteDbPath = path.join(tempDir.path, 'remote_catalog.db');
      await _createCatalogDatabase(
        remoteDbPath,
        version: 4,
      );
      final remoteDbBytes = await File(remoteDbPath).readAsBytes();

      repository = ExternalCatalogRepository(
        httpClient: MockClient((request) async {
          final url = request.url.toString();
          if (url == ExternalCatalogRepository.releaseApiUrl) {
            return http.Response(
              jsonEncode({
                'tag_name': 'db-v4',
                'assets': [
                  {
                    'name': DatabaseConstants.externalCatalogDatabaseFileName,
                    'browser_download_url': 'https://example.com/catalog.db',
                  },
                  {
                    'name': DatabaseConstants.externalCatalogVersionFileName,
                    'browser_download_url': 'https://example.com/version.txt',
                  },
                ],
              }),
              200,
            );
          }
          if (url == 'https://example.com/version.txt') {
            return http.Response('4\n', 200);
          }
          if (url == 'https://example.com/catalog.db') {
            return http.Response.bytes(remoteDbBytes, 200);
          }
          return http.Response('Not found', 404);
        }),
      );

      expect(await repository.updateDatabaseIfNeeded(), isTrue);
      expect(await repository.getCurrentDatabaseVersion(), 4);
    });

    test('getOtzarBooks ו-getHebrewBooks מחזירים ספרים מה-DB החיצוני',
        () async {
      final db = sqlite3.open(repository.databasePath);
      db.execute('''
            CREATE TABLE otzar_hahochma (
              book_id INTEGER PRIMARY KEY,
              title TEXT,
              authors TEXT,
              volume TEXT,
              from_year TEXT,
              to_year TEXT,
              places TEXT,
              subjects TEXT,
              pages INTEGER
            )
          ''');
      db.execute('''
            CREATE TABLE hebrew_books (
              id_book INTEGER PRIMARY KEY,
              title TEXT,
              author TEXT,
              printing_place TEXT,
              printing_year TEXT,
              pub_date INTEGER,
              pages INTEGER,
              tags TEXT
            )
          ''');
      db.execute(
        'INSERT INTO otzar_hahochma (book_id, title, authors, from_year, to_year, places, subjects, pages) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          42,
          'ספר אוצר',
          '["מחבר א","מחבר ב"]',
          'תש"ס',
          'תשס"א',
          'ירושלים',
          'הלכה, מוסר',
          200
        ],
      );
      db.execute(
        'INSERT INTO hebrew_books (id_book, title, author, printing_place, printing_year, pub_date, pages, tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          77,
          'ספר היברו',
          'מחבר ג',
          'ורשה',
          'תרצ"ד',
          1934,
          120,
          '["שו\\"ת","הלכה"]'
        ],
      );
      db.close();

      final otzarBooks = await repository.getOtzarBooks();
      final hebrewBooks = await repository.getHebrewBooks();

      expect(otzarBooks, hasLength(1));
      expect(otzarBooks.first.title, 'ספר אוצר');
      expect(otzarBooks.first.author, 'מחבר א, מחבר ב');
      expect(otzarBooks.first.pubDate, 'תש"ס-תשס"א');
      expect(otzarBooks.first.pubPlace, 'ירושלים');
      expect(otzarBooks.first.topics, 'הלכה, מוסר');
      expect(
        otzarBooks.first.link,
        'https://tablet.otzar.org/book/book.php?book=42',
      );
      expect(otzarBooks.first.externalLibraryId, 'oh:42');

      expect(hebrewBooks, hasLength(1));
      final hebrewBook = hebrewBooks.first;
      expect(hebrewBook.title, 'ספר היברו');
      expect(hebrewBook.author, 'מחבר ג');
      expect(hebrewBook.pubDate, 'תרצ"ד');
      expect(hebrewBook.pubPlace, 'ורשה');
      expect(hebrewBook.topics, 'שו"ת, הלכה');
      expect(
        (hebrewBook as dynamic).link,
        'https://hebrewbooks.org/77',
      );
      expect(hebrewBook.externalLibraryId, 'hb:77');
    });

    test('getOtzarBooks מחזיר רשימה ריקה כשה-DB לא קיים', () async {
      expect(await repository.databaseExists(), isFalse);
      expect(await repository.getOtzarBooks(), isEmpty);
      expect(await repository.getHebrewBooks(), isEmpty);
    });
  });
}

Future<void> _createCatalogDatabase(
  String dbPath, {
  required int version,
}) async {
  final db = sqlite3.open(dbPath);
  db.execute('''
        CREATE TABLE db_meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
  db.execute('''
        CREATE TABLE otzar_hahochma (
          book_id INTEGER PRIMARY KEY,
          title TEXT
        )
      ''');
  db.execute('''
        CREATE TABLE hebrew_books (
          id_book INTEGER PRIMARY KEY,
          title TEXT
        )
      ''');
  db.execute(
    'INSERT INTO db_meta (key, value) VALUES (?, ?)',
    ['version', version.toString()],
  );
  db.close();
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
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }
}
