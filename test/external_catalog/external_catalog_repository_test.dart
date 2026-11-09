import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../test_helpers/memory_cache_provider.dart';

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
      libraryDir = Directory(path.join(tempDir.path, 'Otzaria'));
      await libraryDir.create(recursive: true);

      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        tempDir.path,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        'Otzaria',
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
      await _createCatalogDatabase(repository.databasePath, version: 3);

      expect(await repository.getCurrentDatabaseVersion(), 3);
    });

    test('updateDatabaseIfNeeded מוריד DB חדש רק כשיש גרסה חדשה', () async {
      await _createCatalogDatabase(repository.databasePath, version: 3);

      final remoteDbPath = path.join(tempDir.path, 'remote_catalog.db');
      await _createCatalogDatabase(remoteDbPath, version: 4);
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

    test('updateDatabaseIfNeeded מחתים גרסה כשה-DB שהורד חסר אותה, '
        'ולא מוריד שוב בקריאה הבאה', () async {
      // רגרסיה: DB שהורד בלי מפתח version ב-db_meta השאיר את הגרסה
      // המקומית null, מה שגרם להורדה מחדש של הקטלוג בכל עליית אפליקציה.
      await _createCatalogDatabase(repository.databasePath, version: 3);

      // DB "מרוחק" בלי טבלת db_meta בכלל.
      final remoteDbPath = path.join(tempDir.path, 'remote_no_version.db');
      final remoteDb = sqlite3.open(remoteDbPath);
      remoteDb.execute('CREATE TABLE hebrew_books (id_book INTEGER)');
      remoteDb.close();
      final remoteDbBytes = await File(remoteDbPath).readAsBytes();

      var dbDownloadCount = 0;
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
            dbDownloadCount++;
            return http.Response.bytes(remoteDbBytes, 200);
          }
          return http.Response('Not found', 404);
        }),
      );

      expect(await repository.updateDatabaseIfNeeded(), isTrue);
      expect(dbDownloadCount, 1);
      expect(await repository.getCurrentDatabaseVersion(), 4);

      // קריאה שנייה — הגרסה המקומית כבר עדכנית, אסור להוריד שוב.
      expect(await repository.updateDatabaseIfNeeded(), isFalse);
      expect(dbDownloadCount, 1);
    });

    test('downloadLatestDatabase מחתים גרסה בהורדה ראשונית כשה-DB שהורד '
        'חסר אותה', () async {
      // רגרסיה: ההורדה הראשונית (בלי DB מקומי קודם) לא החתימה גרסה, כך
      // ש-DB בלי db_meta.version נשאר עם גרסה null והסנכרון האוטומטי הוריד
      // אותו שוב בעלייה הבאה.
      final remoteDbPath = path.join(tempDir.path, 'remote_initial.db');
      final remoteDb = sqlite3.open(remoteDbPath);
      remoteDb.execute('CREATE TABLE hebrew_books (id_book INTEGER)');
      remoteDb.close();
      final remoteDbBytes = await File(remoteDbPath).readAsBytes();

      var dbDownloadCount = 0;
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
            dbDownloadCount++;
            return http.Response.bytes(remoteDbBytes, 200);
          }
          return http.Response('Not found', 404);
        }),
      );

      expect(await repository.databaseExists(), isFalse);
      await repository.downloadLatestDatabase();

      expect(dbDownloadCount, 1);
      expect(await repository.getCurrentDatabaseVersion(), 4);

      // הסנכרון האוטומטי בעלייה הבאה — הגרסה כבר מוחתמת, אסור להוריד שוב.
      expect(await repository.updateDatabaseIfNeeded(), isFalse);
      expect(dbDownloadCount, 1);
    });

    group('DB דחוס', () {
      late List<int> remoteDbBytes;

      setUp(() async {
        final remoteDbPath = path.join(tempDir.path, 'remote_zst.db');
        await _createCatalogDatabase(remoteDbPath, version: 5);
        remoteDbBytes = await File(remoteDbPath).readAsBytes();
      });

      http.Client client() => MockClient((request) async {
        final url = request.url.toString();
        if (url == ExternalCatalogRepository.releaseApiUrl) {
          return http.Response(
            jsonEncode({
              'tag_name': 'db-v5',
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
            }),
            200,
          );
        }
        if (url == 'https://example.com/version.txt') {
          return http.Response('5\n', 200);
        }
        if (url == 'https://example.com/catalog.db.zst') {
          return http.Response.bytes(remoteDbBytes, 200);
        }
        return http.Response('Not found', 404);
      });

      test('נפרס מקובץ בדיסק אל ה-DB, והארכיון נמחק', () async {
        String? extractedFrom;
        repository = ExternalCatalogRepository(
          httpClient: client(),
          extractZst:
              (
                archivePath,
                outputPath, {
                required maxOutputBytes,
                isCancelled,
                onProgress,
              }) async {
                extractedFrom = archivePath;
                expect(await File(archivePath).readAsBytes(), remoteDbBytes);
                await File(archivePath).copy(outputPath);
              },
        );

        await repository.downloadLatestDatabase();

        expect(await repository.getCurrentDatabaseVersion(), 5);
        expect(extractedFrom, isNotNull);
        expect(File(extractedFrom!).existsSync(), isFalse);
        expect(
          File('${repository.databasePath}.download').existsSync(),
          isFalse,
        );
      });

      test('כשל בפריסה משאיר את ה-DB הקיים', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        repository = ExternalCatalogRepository(
          httpClient: client(),
          extractZst:
              (
                _,
                _, {
                required maxOutputBytes,
                isCancelled,
                onProgress,
              }) async => throw const FormatException('corrupt'),
        );

        await expectLater(repository.downloadLatestDatabase(), throwsException);

        expect(await repository.getCurrentDatabaseVersion(), 3);
        expect(
          File('${repository.databasePath}.download.zst').existsSync(),
          isFalse,
        );
      });

      test('ביטול בדיווח האחרון משמר DB והורדה ומנקה staging', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        var cancelled = false;
        repository = ExternalCatalogRepository(
          httpClient: client(),
          extractZst:
              (
                archive,
                output, {
                required maxOutputBytes,
                isCancelled,
                onProgress,
              }) async {
                expect(maxOutputBytes, kDefaultMaxExtractedBytes);
                expect(isCancelled, isNotNull);
                await File(archive).copy(output);
                onProgress?.call(1);
              },
        );

        await expectLater(
          repository.downloadLatestDatabase(
            isCancelled: () => cancelled,
            onExtractionProgress: (_) => cancelled = true,
          ),
          throwsA(isA<PatchDownloadCancelled>()),
        );

        expect(await repository.getCurrentDatabaseVersion(), 3);
        expect(
          File('${repository.databasePath}.download').existsSync(),
          isFalse,
        );
        expect(
          File('${repository.databasePath}.download.zst').existsSync(),
          isTrue,
        );
      });

      test('מגבלת הפלט מועברת למחלץ לפני החלפת הקטלוג', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        repository = ExternalCatalogRepository(
          httpClient: client(),
          maxOutputBytes: 128,
          extractZst:
              (_, _, {required maxOutputBytes, isCancelled, onProgress}) async {
                expect(maxOutputBytes, 128);
                throw ZstdOutputLimitExceeded(maxOutputBytes);
              },
        );

        await expectLater(
          repository.downloadLatestDatabase(),
          throwsA(isA<ZstdOutputLimitExceeded>()),
        );
        expect(await repository.getCurrentDatabaseVersion(), 3);
        expect(
          File('${repository.databasePath}.download').existsSync(),
          isFalse,
        );
      });

      test('פלט שאינו SQLite נדחה לפני החלפת מסד תקין', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        repository = ExternalCatalogRepository(
          httpClient: client(),
          extractZst:
              (
                _,
                output, {
                required maxOutputBytes,
                isCancelled,
                onProgress,
              }) async {
                await File(output).writeAsString('invalid database');
              },
        );

        await expectLater(
          repository.downloadLatestDatabase(),
          throwsA(isA<FormatException>()),
        );
        expect(await repository.getCurrentDatabaseVersion(), 3);
        expect(
          File('${repository.databasePath}.download').existsSync(),
          isFalse,
        );
        expect(
          File('${repository.databasePath}.download.zst').existsSync(),
          isFalse,
        );
      });

      test('פלט ריק אינו הופך לקטלוג חדש בהחתמת גרסה', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        repository = ExternalCatalogRepository(
          httpClient: client(),
          extractZst:
              (
                _,
                output, {
                required maxOutputBytes,
                isCancelled,
                onProgress,
              }) async {
                await File(output).writeAsBytes(const []);
              },
        );

        await expectLater(
          repository.downloadLatestDatabase(),
          throwsA(isA<FormatException>()),
        );
        expect(await repository.getCurrentDatabaseVersion(), 3);
        expect(
          File('${repository.databasePath}.download').existsSync(),
          isFalse,
        );
      });

      test('מגבלת הורדה עוצרת את הזרם לפני חילוץ ושומרת DB קיים', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        var extractionStarted = false;
        repository = ExternalCatalogRepository(
          httpClient: client(),
          maxDownloadBytes: 128,
          extractZst:
              (_, _, {required maxOutputBytes, isCancelled, onProgress}) async {
                extractionStarted = true;
              },
        );

        await expectLater(
          repository.downloadLatestDatabase(),
          throwsA(isA<PatchDownloadException>()),
        );
        expect(extractionStarted, isFalse);
        expect(await repository.getCurrentDatabaseVersion(), 3);
        expect(
          File('${repository.databasePath}.download.zst').existsSync(),
          isFalse,
        );
      });
    });

    group('החלפת משפחת SQLite', () {
      late List<int> remoteDbBytes;

      setUp(() async {
        final remote = path.join(tempDir.path, 'remote_family.db');
        await _createCatalogDatabase(remote, version: 5);
        remoteDbBytes = File(remote).readAsBytesSync();
      });

      http.Client client() => MockClient((request) async {
        final url = request.url.toString();
        if (url == ExternalCatalogRepository.releaseApiUrl) {
          return http.Response(
            jsonEncode({
              'tag_name': 'db-v5',
              'assets': [
                {
                  'name': DatabaseConstants.externalCatalogDatabaseFileName,
                  'browser_download_url': 'https://example.com/family.db',
                  'size': remoteDbBytes.length,
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
          return http.Response('5', 200);
        }
        if (url == 'https://example.com/family.db') {
          return http.Response.bytes(remoteDbBytes, 200);
        }
        return http.Response('Not found', 404);
      });

      test('WAL ישן אינו מוחל על המסד החדש', () async {
        await _createOrphanWalCatalog(repository.databasePath);
        expect(File('${repository.databasePath}-wal').existsSync(), isTrue);
        repository = ExternalCatalogRepository(httpClient: client());

        await repository.downloadLatestDatabase();

        expect(await repository.getCurrentDatabaseVersion(), 5);
        _expectCatalogIntegrity(repository.databasePath);
        expect(File('${repository.databasePath}-wal').existsSync(), isFalse);
        expect(
          Directory(
            '${repository.databasePath}.catalog-update-backup',
          ).existsSync(),
          isFalse,
        );
      });

      test('קורא WAL פעיל מעכב החלפה ושומר את התוכן הישן', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        final reader = sqlite3.open(repository.databasePath);
        reader.execute('PRAGMA journal_mode=WAL');
        reader.execute('PRAGMA wal_autocheckpoint=0');
        reader.execute("UPDATE db_meta SET value='4' WHERE key='version'");
        reader.execute('BEGIN');
        expect(reader.select('SELECT value FROM db_meta').single['value'], '4');
        repository = ExternalCatalogRepository(httpClient: client());
        try {
          await expectLater(
            repository.downloadLatestDatabase(),
            throwsA(isA<ExternalCatalogDatabaseBusyException>()),
          );
          expect(
            reader.select('SELECT value FROM db_meta').single['value'],
            '4',
          );
          expect(
            Directory(
              '${repository.databasePath}.catalog-update-backup',
            ).existsSync(),
            isFalse,
          );
          expect(
            File('${repository.databasePath}.download.zst').existsSync(),
            isTrue,
          );
        } finally {
          reader.execute('ROLLBACK');
          reader.close();
        }
        await repository.downloadLatestDatabase();
        expect(await repository.getCurrentDatabaseVersion(), 5);
        _expectCatalogIntegrity(repository.databasePath);
      });

      test('cursor פעיל מאפשר קוראים נוספים ודוחה החלפה עד סגירתו', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        final writer = sqlite3.open(repository.databasePath);
        writer.execute(
          "INSERT INTO otzar_hahochma VALUES (1, 'Alpha'), (2, 'beta')",
        );
        writer.close();
        final reader = sqlite3.open(
          repository.databasePath,
          mode: OpenMode.readOnly,
        );
        final statement = reader.prepare(
          'SELECT * FROM otzar_hahochma ORDER BY title COLLATE NOCASE',
        );
        repository = ExternalCatalogRepository(httpClient: client());
        try {
          final cursor = statement.selectCursor();
          expect(cursor.moveNext(), isTrue);
          expect(cursor.current['title'], 'Alpha');
          final concurrent = await Future.wait([
            repository.getOtzarBooks(),
            repository.getOtzarBooks(),
            repository.getHebrewBooks(),
          ]);
          expect(concurrent[0].map((book) => book.title), ['Alpha', 'beta']);
          expect(concurrent[1].map((book) => book.title), ['Alpha', 'beta']);
          expect(concurrent[2], isEmpty);
          await expectLater(
            repository.downloadLatestDatabase(),
            throwsA(isA<ExternalCatalogDatabaseBusyException>()),
          );
          expect(await repository.getCurrentDatabaseVersion(), 3);
          expect(
            File('${repository.databasePath}.download.zst').existsSync(),
            isTrue,
          );
          expect(cursor.moveNext(), isTrue);
          expect(cursor.current['title'], 'beta');
        } finally {
          statement.close();
          reader.close();
        }
        await repository.downloadLatestDatabase();
        expect(await repository.getCurrentDatabaseVersion(), 5);
        _expectCatalogIntegrity(repository.databasePath);
      });

      test('כשל אחרי העברת המסד החדש משחזר את הקטלוג הקודם', () async {
        await _createOrphanWalCatalog(repository.databasePath);
        var reachedCommit = false;
        repository = ExternalCatalogRepository(
          httpClient: client(),
          beforeFileRename: (source, destination) {
            if (path.basename(source) == 'committed.tmp') {
              reachedCommit = true;
              throw StateError('injected commit decision failure');
            }
          },
        );

        await expectLater(
          repository.downloadLatestDatabase(),
          throwsStateError,
        );

        expect(reachedCommit, isTrue);
        expect(await repository.getCurrentDatabaseVersion(), 4);
        _expectCatalogIntegrity(repository.databasePath);
        expect(
          Directory(
            '${repository.databasePath}.catalog-update-backup',
          ).existsSync(),
          isFalse,
        );
      });

      test('כשל בשחזור נשמר ביומן ומתאושש לפני פנייה לרשת', () async {
        await _createCatalogDatabase(repository.databasePath, version: 3);
        final target = repository.databasePath;
        final backup = '$target.catalog-update-backup';
        var failedCommit = false;
        repository = ExternalCatalogRepository(
          httpClient: client(),
          beforeFileRename: (source, destination) {
            if (path.basename(source) == 'committed.tmp') {
              failedCommit = true;
              throw StateError('injected commit failure');
            }
            if (failedCommit && source == path.join(backup, '0')) {
              throw StateError('injected rollback failure');
            }
          },
        );

        await expectLater(
          repository.downloadLatestDatabase(),
          throwsStateError,
        );
        expect(File(path.join(backup, '0')).existsSync(), isTrue);
        expect(File(path.join(backup, 'state.json')).existsSync(), isTrue);
        expect(File(target).existsSync(), isFalse);
        var restoredBeforeNetwork = false;
        repository = ExternalCatalogRepository(
          httpClient: MockClient((_) async {
            restoredBeforeNetwork =
                File(target).existsSync() && !Directory(backup).existsSync();
            return http.Response('unavailable', 404);
          }),
        );

        await expectLater(repository.downloadLatestDatabase(), throwsException);

        expect(restoredBeforeNetwork, isTrue);
        expect(await repository.getCurrentDatabaseVersion(), 3);
        _expectCatalogIntegrity(target);
      });

      test('יומן שנקטע משחזר גם WAL שטרם נכתב לקובץ הראשי', () async {
        final target = repository.databasePath;
        await _createOrphanWalCatalog(target);
        final backup = Directory('$target.catalog-update-backup')..createSync();
        const suffixes = ['', '-wal', '-shm', '-journal'];
        final existed = [
          for (final suffix in suffixes) File('$target$suffix').existsSync(),
        ];
        expect(existed[1], isTrue);
        File(
          path.join(backup.path, 'state.json'),
        ).writeAsStringSync(jsonEncode(existed), flush: true);
        for (var i = 0; i < suffixes.length; i++) {
          if (existed[i]) {
            File(
              '$target${suffixes[i]}',
            ).renameSync(path.join(backup.path, '$i'));
          }
        }
        await _createCatalogDatabase(target, version: 9);
        File('$target-journal').writeAsBytesSync([1, 2, 3]);
        repository = ExternalCatalogRepository(
          httpClient: MockClient(
            (_) async => http.Response('unavailable', 404),
          ),
        );

        await expectLater(repository.downloadLatestDatabase(), throwsException);

        expect(await repository.getCurrentDatabaseVersion(), 4);
        _expectCatalogIntegrity(target);
        expect(File('$target-journal').existsSync(), isFalse);
        expect(backup.existsSync(), isFalse);
      });

      test('החלטת commit נשמרת גם כאשר ניקוי הגיבוי נקטע', () async {
        final target = repository.databasePath;
        await _createCatalogDatabase(target, version: 5);
        final backup = Directory('$target.catalog-update-backup')..createSync();
        await _createCatalogDatabase(path.join(backup.path, '0'), version: 3);
        File(
          path.join(backup.path, 'state.json'),
        ).writeAsStringSync('[true,false,false,false]', flush: true);
        File(
          path.join(backup.path, 'committed'),
        ).writeAsStringSync('1', flush: true);
        repository = ExternalCatalogRepository(
          httpClient: MockClient(
            (_) async => http.Response('unavailable', 404),
          ),
        );

        await expectLater(repository.downloadLatestDatabase(), throwsException);

        expect(await repository.getCurrentDatabaseVersion(), 5);
        _expectCatalogIntegrity(target);
        expect(backup.existsSync(), isFalse);
      });
    });

    test('גיבוי מ-swap שנקטע משוחזר גם כשהרשת אינה זמינה', () async {
      await _createCatalogDatabase(repository.databasePath, version: 3);
      await File(
        repository.databasePath,
      ).rename('${repository.databasePath}.bak');
      repository = ExternalCatalogRepository(
        httpClient: MockClient((_) async => http.Response('unavailable', 404)),
      );

      await expectLater(repository.downloadLatestDatabase(), throwsException);
      expect(await repository.getCurrentDatabaseVersion(), 3);
      expect(File(repository.databasePath).existsSync(), isTrue);
    });

    test(
      'updateDatabaseIfNeeded זורק שגיאה ידידותית כשה-DB נעול ב-Windows',
      () async {
        if (!Platform.isWindows) {
          return;
        }

        await _createCatalogDatabase(repository.databasePath, version: 4);

        final remoteDbPath = path.join(tempDir.path, 'remote_catalog_busy.db');
        await _createCatalogDatabase(remoteDbPath, version: 5);
        final remoteDbBytes = await File(remoteDbPath).readAsBytes();

        repository = ExternalCatalogRepository(
          httpClient: MockClient((request) async {
            final url = request.url.toString();
            if (url == ExternalCatalogRepository.releaseApiUrl) {
              return http.Response(
                jsonEncode({
                  'tag_name': 'db-v5',
                  'assets': [
                    {
                      'name': DatabaseConstants.externalCatalogDatabaseFileName,
                      'browser_download_url':
                          'https://example.com/catalog_busy.db',
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
              return http.Response('5\n', 200);
            }
            if (url == 'https://example.com/catalog_busy.db') {
              return http.Response.bytes(remoteDbBytes, 200);
            }
            return http.Response('Not found', 404);
          }),
        );

        final lock = File(
          repository.databasePath,
        ).openSync(mode: FileMode.read);
        addTearDown(() async {
          await lock.close();
        });

        await expectLater(
          repository.updateDatabaseIfNeeded(),
          throwsA(isA<ExternalCatalogDatabaseBusyException>()),
        );
        expect(await repository.getCurrentDatabaseVersion(), 4);
      },
    );

    test('getOtzarBooks ו-getHebrewBooks מחזירים ספרים מה-DB החיצוני', () async {
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
          200,
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
          '["שו\\"ת","הלכה"]',
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
      expect((hebrewBook as dynamic).link, 'https://hebrewbooks.org/77');
      expect(hebrewBook.externalLibraryId, 'hb:77');
    });

    test('getHebrewBooksByIds מחזיר רק את המזהים המבוקשים', () async {
      final db = sqlite3.open(repository.databasePath);
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
      for (final id in [1, 2, 3, 4]) {
        db.execute(
          'INSERT INTO hebrew_books (id_book, title, author, printing_place, printing_year, pub_date, pages, tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [id, 'ספר $id', 'מחבר', 'מקום', 'שנה', 1900, 10, '[]'],
        );
      }
      db.close();

      final books = await repository.getHebrewBooksByIds([1, 3]);

      expect(books, hasLength(2));
      expect(books.map((b) => b.id).toSet(), {1, 3});
      expect(books.map((b) => b.externalLibraryId).toSet(), {'hb:1', 'hb:3'});
    });

    test('getHebrewBooksByIds מחזיר רשימה ריקה לקבוצת מזהים ריקה', () async {
      final db = sqlite3.open(repository.databasePath);
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
      db.close();

      expect(await repository.getHebrewBooksByIds(const []), isEmpty);
    });

    test('טעינת קטלוג גדול לא חוסמת את ה-isolate הראשי (perf)', () async {
      const rowCount = 80000;
      final db = sqlite3.open(repository.databasePath);
      db.execute(
        'CREATE TABLE otzar_hahochma (book_id INTEGER PRIMARY KEY, title TEXT, '
        'authors TEXT, from_year TEXT, to_year TEXT, places TEXT, subjects TEXT)',
      );
      db.execute('BEGIN');
      final insert = db.prepare(
        'INSERT INTO otzar_hahochma VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      for (var i = 0; i < rowCount; i++) {
        insert.execute([
          i,
          'ספר $i',
          '["מחבר $i","מחבר ב"]',
          'תש"ס',
          'תשס"א',
          'ירושלים',
          'הלכה, מוסר',
        ]);
      }
      insert.close();
      db.execute('COMMIT');
      db.close();

      var maxGap = Duration.zero;
      final gapWatch = Stopwatch()..start();
      final ticker = Timer.periodic(const Duration(milliseconds: 2), (_) {
        if (gapWatch.elapsed > maxGap) maxGap = gapWatch.elapsed;
        gapWatch.reset();
      });
      final total = Stopwatch()..start();
      final books = await repository.getOtzarBooks();
      total.stop();
      ticker.cancel();
      if (gapWatch.elapsed > maxGap) maxGap = gapWatch.elapsed;

      expect(books, hasLength(rowCount));
      expect(
        maxGap.inMicroseconds,
        lessThan(total.elapsedMicroseconds ~/ 2),
        reason: 'max gap $maxGap of total ${total.elapsed}',
      );
    });

    test('טעינת הקטלוג שומרת על מיפוי, סדר ומקור זהים', () async {
      final db = sqlite3.open(repository.databasePath);
      db.execute(
        'CREATE TABLE otzar_hahochma (book_id INTEGER PRIMARY KEY, title TEXT, '
        'authors TEXT, from_year TEXT, to_year TEXT, places TEXT, subjects TEXT)',
      );
      db.execute(
        'CREATE TABLE hebrew_books (id_book INTEGER PRIMARY KEY, title TEXT, '
        'author TEXT, printing_place TEXT, printing_year TEXT, '
        'pub_date INTEGER, tags TEXT)',
      );
      final otzarRows = [
        [4, null, null, null, null, null, null],
        [3, 'beta', 'א, ב', 'תש"ס', 'תש"ס', ' ', null],
        [1, 'Alpha', null, null, 'תר"ן', 'ורשה', '["x"," ","y"]'],
        [2, 'גמרא', '["ג"]', 'תק"ע', 'תק"פ', null, 'z'],
      ];
      for (final row in otzarRows) {
        db.execute(
          'INSERT INTO otzar_hahochma VALUES (?, ?, ?, ?, ?, ?, ?)',
          row,
        );
      }
      final hebrewRows = [
        [10, null, null, null, null, null, null],
        [9, 'b', ' מחבר ', null, null, 1900, 'שו"ת, הלכה'],
        [8, 'A', null, 'וילנא', 'תרל"ה', 1875, '[bad json'],
      ];
      for (final row in hebrewRows) {
        db.execute(
          'INSERT INTO hebrew_books VALUES (?, ?, ?, ?, ?, ?, ?)',
          row,
        );
      }
      db.close();

      List<Map<String, dynamic>> dump(List<Book> books) => [
        for (final book in books) (book as ExternalLibraryBook).toJson(),
      ];
      Map<String, dynamic> expected(
        int id,
        String title,
        String? author,
        String? place,
        String? date,
        String topics,
        String link,
        String externalId,
      ) => {
        'title': title,
        'type': 'ExternalLibraryBook',
        'otzarId': id,
        'author': author,
        'pubPlace': place,
        'pubDate': date,
        'topics': topics,
        'link': link,
        'filePath': null,
        'categoryPath': null,
        'fileType': 'link',
        'heCategories': null,
        'source': 'o',
        'isUserBook': false,
        'externalLibraryId': externalId,
      };
      const otzarLink = 'https://tablet.otzar.org/book/book.php?book=';

      final otzar = await repository.getOtzarBooks();
      final hebrew = await repository.getHebrewBooks();
      final byIds = await repository.getHebrewBooksByIds([9, 8]);

      expect(
        otzar.every((b) => identical(b.source, BookSource.official)),
        isTrue,
      );
      expect(dump(otzar), [
        expected(4, '', null, null, null, '', '${otzarLink}4', 'oh:4'),
        expected(
          1,
          'Alpha',
          null,
          'ורשה',
          'תר"ן',
          'x, y',
          '${otzarLink}1',
          'oh:1',
        ),
        expected(3, 'beta', 'א, ב', null, 'תש"ס', '', '${otzarLink}3', 'oh:3'),
        expected(
          2,
          'גמרא',
          'ג',
          null,
          'תק"ע-תק"פ',
          'z',
          '${otzarLink}2',
          'oh:2',
        ),
      ]);
      final hebrewA = expected(
        8,
        'A',
        null,
        'וילנא',
        'תרל"ה',
        '[bad json',
        'https://hebrewbooks.org/8',
        'hb:8',
      );
      final hebrewB = expected(
        9,
        'b',
        'מחבר',
        null,
        '1900',
        'שו"ת, הלכה',
        'https://hebrewbooks.org/9',
        'hb:9',
      );
      expect(dump(hebrew), [
        expected(
          10,
          '',
          null,
          null,
          null,
          '',
          'https://hebrewbooks.org/10',
          'hb:10',
        ),
        hebrewA,
        hebrewB,
      ]);
      expect(
        dump(
          byIds,
        )..sort((a, b) => (a['otzarId'] as int).compareTo(b['otzarId'] as int)),
        [hebrewA, hebrewB],
      );
    });

    for (final (tableName, idColumn, load)
        in <(String, String, Future<List<Book>> Function())>[
          ('otzar_hahochma', 'book_id', () => repository.getOtzarBooks()),
          ('hebrew_books', 'id_book', () => repository.getHebrewBooks()),
        ]) {
      test('$tableName שומר ברירות מחדל, סדר ורשימה באורך קבוע', () async {
        final db = sqlite3.open(repository.databasePath);
        db.execute('CREATE TABLE $tableName ($idColumn INTEGER, title TEXT)');
        db.close();
        expect(await load(), isEmpty);
        final writer = sqlite3.open(repository.databasePath);
        writer.execute(
          "INSERT INTO $tableName VALUES (3, 'beta'), (1, NULL), "
          "(2, 'Alpha'), (4, 'alpha')",
        );
        final expectedIds = writer
            .select('SELECT * FROM $tableName ORDER BY title COLLATE NOCASE')
            .map((row) => row[idColumn])
            .toList();
        writer.close();
        final books = await load();
        expect(
          books.map((book) => (book as ExternalLibraryBook).id),
          expectedIds,
        );
        expect(books.map((book) => book.title), ['', 'Alpha', 'alpha', 'beta']);
        for (final book in books.cast<ExternalLibraryBook>()) {
          expect(book.author, isNull);
          expect(book.pubPlace, isNull);
          expect(book.pubDate, isNull);
          expect(book.topics, '');
        }
        expect(() => books.clear(), throwsUnsupportedError);
        _expectExclusiveCatalogAccess(repository.databasePath);
      });

      test(
        '$tableName כשל מיפוי מבטל גם תוצאות קודמות ומשחרר נעילות',
        () async {
          final db = sqlite3.open(repository.databasePath);
          db.execute('CREATE TABLE $tableName ($idColumn, title TEXT)');
          db.execute(
            "INSERT INTO $tableName VALUES (1, 'a'), ('invalid', 'b')",
          );
          db.close();
          expect(await load(), isEmpty);
          _expectExclusiveCatalogAccess(repository.databasePath);
          final repair = sqlite3.open(repository.databasePath);
          repair.execute(
            "UPDATE $tableName SET $idColumn = 2 WHERE title = 'b'",
          );
          repair.close();
          expect((await load()).map((book) => book.title), ['a', 'b']);
        },
      );

      test(
        '$tableName שגיאת SQLite באמצע הקריאה אינה משאירה תוצאות או נעילה',
        () async {
          final db = sqlite3.open(repository.databasePath);
          db.execute('CREATE TABLE source_catalog (id INTEGER, title TEXT)');
          db.execute("INSERT INTO source_catalog VALUES (1, 'a'), (2, 'b')");
          db.execute(
            'CREATE INDEX titles ON source_catalog(title COLLATE NOCASE)',
          );
          db.execute(
            'CREATE VIEW $tableName AS SELECT title, '
            'CASE WHEN id = 2 THEN abs(-9223372036854775808) '
            'ELSE id END AS $idColumn FROM source_catalog',
          );
          final probe = db.prepare(
            'SELECT * FROM $tableName ORDER BY title COLLATE NOCASE',
          );
          try {
            final cursor = probe.selectCursor();
            expect(cursor.moveNext(), isTrue);
            expect(cursor.current[idColumn], 1);
            expect(() => cursor.moveNext(), throwsA(isA<SqliteException>()));
          } finally {
            probe.close();
            db.close();
          }
          expect(await load(), isEmpty);
          _expectExclusiveCatalogAccess(repository.databasePath);
        },
      );

      test('$tableName כשל בהכנת השאילתה משחרר את המסד', () async {
        final db = sqlite3.open(repository.databasePath);
        db.execute('CREATE TABLE unrelated (id INTEGER)');
        db.close();
        expect(await load(), isEmpty);
        _expectExclusiveCatalogAccess(repository.databasePath);
      });
    }

    test('getOtzarBooks מחזיר רשימה ריקה כשה-DB לא קיים', () async {
      expect(await repository.databaseExists(), isFalse);
      expect(await repository.getOtzarBooks(), isEmpty);
      expect(await repository.getHebrewBooks(), isEmpty);
    });
  });
}

void _expectExclusiveCatalogAccess(String dbPath) {
  final db = sqlite3.open(dbPath);
  try {
    db.execute('PRAGMA busy_timeout=0');
    db.execute('BEGIN EXCLUSIVE');
    db.execute('ROLLBACK');
  } finally {
    db.close();
  }
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
  db.execute('INSERT INTO db_meta (key, value) VALUES (?, ?)', [
    'version',
    version.toString(),
  ]);
  db.close();
}

Future<void> _createOrphanWalCatalog(String target) async {
  await _createCatalogDatabase(target, version: 3);
  final db = sqlite3.open(target);
  final files = <String, List<int>>{};
  try {
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA wal_autocheckpoint=0');
    db.execute("UPDATE db_meta SET value='4' WHERE key='version'");
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('$target$suffix');
      if (file.existsSync()) files[suffix] = file.readAsBytesSync();
    }
  } finally {
    db.close();
  }
  // משחזר snapshot עקבי של קריסה לפני checkpoint, ללא handle חי.
  for (final entry in files.entries) {
    File('$target${entry.key}').writeAsBytesSync(entry.value, flush: true);
  }
}

void _expectCatalogIntegrity(String target) {
  final db = sqlite3.open(target, mode: OpenMode.readOnly);
  try {
    expect(db.select('PRAGMA quick_check').single.values.single, 'ok');
  } finally {
    db.close();
  }
}
