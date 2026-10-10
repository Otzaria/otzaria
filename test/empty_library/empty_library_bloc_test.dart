import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:path/path.dart' as path;

import 'library_release_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ההורדות והגיבוי נכתבים לשמות קבועים ב-temp, והניקוי מוחק כל
  // otzaria_db_backup שם: בלי בידוד, ריצה מקבילה דורסת או מוחקת אותם.
  final realTemp = Directory.systemTemp;
  late Directory isolatedTemp;
  setUp(() {
    isolatedTemp = realTemp.createTempSync('otzaria-elb-test-');
    IOOverrides.global = _IsolatedTempOverrides(isolatedTemp);
    EmptyLibraryBloc.tempRootOverride = isolatedTemp.path;
  });
  tearDown(() async {
    EmptyLibraryBloc.tempRootOverride = null;
    IOOverrides.global = null;
    try {
      await isolatedTemp.delete(recursive: true);
    } catch (_) {}
  });

  group('EmptyLibraryBloc', () {
    test('UseLibraryInPlaceRequested שומר את הנתיב בלי להעתיק דבר', () async {
      final libDir = await Directory.systemTemp.createTemp('otzaria-inplace-');
      addTearDown(() async {
        if (await libDir.exists()) await libDir.delete(recursive: true);
      });

      final dbName = DatabaseConstants.databaseFileName;
      await File(path.join(libDir.path, dbName)).writeAsString('existing-db');

      await Settings.init(cacheProvider: _MemoryCacheProvider());

      final bloc = EmptyLibraryBloc();
      addTearDown(bloc.close);

      final selectedFuture = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .cast<EmptyLibraryDirectorySelected>()
          .first;

      bloc.add(UseLibraryInPlaceRequested(libDir.path));

      final selected = await selectedFuture.timeout(const Duration(seconds: 5));

      expect(selected.selectedPath, libDir.path);
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        libDir.path,
      );
      // התיקייה נשארה כפי שהייתה — אין תת-תיקיית "books" ואין עותק נוסף.
      expect(libDir.listSync().map((e) => path.basename(e.path)), [dbName]);
    });

    test('UseLibraryInPlaceRequested נכשל כשאין seforim.db בתיקייה', () async {
      final emptyDir = await Directory.systemTemp.createTemp(
        'otzaria-inplace-empty-',
      );
      addTearDown(() async {
        if (await emptyDir.exists()) await emptyDir.delete(recursive: true);
      });

      await Settings.init(cacheProvider: _MemoryCacheProvider());

      final bloc = EmptyLibraryBloc();
      addTearDown(bloc.close);

      final errorFuture = bloc.stream
          .where((s) => s is EmptyLibraryError && s.errorMessage != null)
          .cast<EmptyLibraryError>()
          .first;

      bloc.add(UseLibraryInPlaceRequested(emptyDir.path));

      final error = await errorFuture.timeout(const Duration(seconds: 5));
      expect(error.errorMessage, contains(DatabaseConstants.databaseFileName));
    });

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

    test(
      'parseLatestDatabaseAsset מזהה DB מפוצל; קובץ יחיד גובר באותה סכמה',
      () {
        final split = EmptyLibraryBloc.parseLatestDatabaseAsset({
          'assets': [
            {
              'name': 'seforim-schema6.db.zst.manifest.json',
              'browser_download_url': 'https://example.com/s6.manifest',
            },
            {
              'name': 'seforim-schema6.db.zst.part-000',
              'browser_download_url': 'https://example.com/s6.part-000',
            },
            {
              'name': 'seforim.db.zst',
              'browser_download_url': 'https://example.com/legacy',
            },
          ],
        });
        expect(split!.assetName, 'seforim-schema6.db.zst');
        expect(split.isSplitManifest, isTrue);
        expect(split.downloadUrl, 'https://example.com/s6.manifest');

        final single = EmptyLibraryBloc.parseLatestDatabaseAsset({
          'assets': [
            {
              'name': 'seforim-schema6.db.zst.manifest.json',
              'browser_download_url': 'https://example.com/s6.manifest',
            },
            {
              'name': 'seforim-schema6.db.zst',
              'browser_download_url': 'https://example.com/s6',
            },
          ],
        });
        expect(single!.isSplitManifest, isFalse);
        expect(single.downloadUrl, 'https://example.com/s6');
      },
    );

    test(
      'parseLatestDatabaseAsset מעדיף ארכיון בסכמה נתמכת ומדלג על חדשה ממנה',
      () {
        final asset = EmptyLibraryBloc.parseLatestDatabaseAsset({
          'assets': [
            {
              'name': 'seforim-schema99.db.zst',
              'browser_download_url': 'https://example.com/s99',
            },
            {
              'name': 'seforim.db.zst',
              'browser_download_url': 'https://example.com/legacy',
            },
            {
              'name': 'seforim-schema6.db.zst',
              'browser_download_url': 'https://example.com/s6',
            },
          ],
        });

        expect(asset!.assetName, 'seforim-schema6.db.zst');
        expect(asset.downloadUrl, 'https://example.com/s6');
        expect(
          EmptyLibraryBloc.parseLatestDatabaseAsset({
            'assets': [
              {
                'name': 'seforim-schema99.db.zst',
                'browser_download_url': 'https://example.com/s99',
              },
            ],
          }),
          isNull,
        );
      },
    );

    test('קריאת release API נקטעת ב-connect timeout', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-release-timeout-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return http.Response('late', 200);
      });
      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        downloadConnectTimeout: const Duration(milliseconds: 20),
        extractCompressedDatabase: (a, o, p) async {},
        extractTarArchive: (a, o, p) async {},
      );
      addTearDown(bloc.close);

      final error = bloc.stream
          .where((state) => state is EmptyLibraryError)
          .cast<EmptyLibraryError>()
          .first;
      bloc.add(DownloadLibraryRequested());
      final state = await error.timeout(const Duration(seconds: 1));

      expect(state.errorMessage, contains('TimeoutException'));
    });

    test('releaseTagFromUrl מחלץ תג מנתיב redirect של GitHub', () {
      expect(
        EmptyLibraryBloc.releaseTagFromUrl(
          '/Otzaria/SeforimMagicIndexer/releases/download/v0.3.0/lexical.db',
        ),
        'v0.3.0',
      );
      // הנתיב לפני ה-redirect (latest) והנתיב הסופי ב-CDN — ללא תג.
      expect(
        EmptyLibraryBloc.releaseTagFromUrl(
          '/Otzaria/SeforimMagicIndexer/releases/latest/download/lexical.db',
        ),
        isNull,
      );
      expect(
        EmptyLibraryBloc.releaseTagFromUrl(
          '/github-production-release-asset/123/456',
        ),
        isNull,
      );
    });

    test('DownloadLibraryRequested מוריד DB מהרליס האחרון ומחלץ אותו', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-empty-library-test-',
      );
      final lexicalPath = path.join(tempDir.path, 'lexical.db');
      await File('$lexicalPath.next').writeAsString('staged-old');
      await File('$lexicalPath.next.version').writeAsString('old-digest');
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
      final talmudDigest = sha256.convert(talmudBytes).toString();
      final catalogBytes = utf8.encode('compressed-catalog');
      final lexicalBytes = utf8.encode('lexical-dictionary');
      final lexicalDigest = sha256.convert(lexicalBytes).toString();
      final client = MockClient((request) async {
        // ה-API של המילון: הנכס המועדף lexical-v2.db עם ה-digest שלו.
        if (request.url.path.contains(
          '/repos/Otzaria/SeforimMagicIndexer/releases/latest',
        )) {
          const base =
              'https://github.com/Otzaria/SeforimMagicIndexer/releases/download/v0.3.1';
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.3.1',
              'assets': [
                {
                  'browser_download_url': '$base/lexical.db',
                  'digest': 'sha256:${'0' * 64}',
                },
                {
                  'browser_download_url': '$base/lexical-v2.db',
                  'digest': 'sha256:$lexicalDigest',
                  'size': lexicalBytes.length,
                },
              ],
            }),
            200,
          );
        }

        // ה-API של otzaria-library — איתור release התלמוד (כולל digest).
        if (request.url.path.contains(
          '/repos/Otzaria/otzaria-library/releases/latest',
        )) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v5.0.0',
              'assets': [
                {
                  'name': DatabaseConstants.talmudBavliArchiveFileName,
                  'browser_download_url':
                      'https://github.com/Otzaria/otzaria-library/releases/download/v5.0.0/talmud_bavli_latest.tar.zst',
                  'digest': 'sha256:$talmudDigest',
                  'size': talmudBytes.length,
                },
              ],
            }),
            200,
          );
        }

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

        // כמו GitHub: releases/latest/download מפנה לנתיב עם תג ה-release.
        if (request.url.host == 'github.com' &&
            request.url.path.contains('/releases/latest/download/') &&
            request.url.path.endsWith('/lexical-v2.db')) {
          return http.Response(
            '',
            302,
            headers: const {
              'location':
                  'https://github.com/Otzaria/SeforimMagicIndexer/releases/download/v0.3.0/lexical-v2.db',
            },
          );
        }

        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('/lexical-v2.db')) {
          return http.Response.bytes(lexicalBytes, 200);
        }

        return http.Response('not found', 404);
      });

      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          // הקובץ הזמני חייב להיות בתיקיית temp של המערכת
          expect(archivePath, startsWith(Directory.systemTemp.path));
          // יכול להיות גם seforim.db.zst וגם otzar-HB_catalog.db.zst
          final basename = path.basename(archivePath);
          if (basename == 'otzaria_seforim.db.zst') {
            expect(await File(archivePath).readAsBytes(), downloadedBytes);
            // הכתיבה אטומית: לשם הסופי מגיעים רק ב-rename שבסיום.
            expect(
              outputPath,
              path.join(
                tempDir.path,
                '${DatabaseConstants.databaseFileName}.new',
              ),
            );
            await File(outputPath).writeAsBytes(const [1, 2, 3], flush: true);
          } else if (basename == 'otzaria_otzar-HB_catalog.db.zst') {
            expect(await File(archivePath).readAsBytes(), catalogBytes);
            await File(outputPath).writeAsBytes(const [4, 5, 6], flush: true);
          } else {
            fail('Unexpected archive: $archivePath');
          }
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {
          expect(archivePath, startsWith(Directory.systemTemp.path));
          expect(path.basename(archivePath), 'otzaria_talmud_bavli.tar.zst');
          expect(await File(archivePath).readAsBytes(), talmudBytes);
          // מדמים חילוץ: הארכיון האמיתי יוצר את תיקיית התלמוד ביעד.
          Directory(
            path.join(outputDir, DatabaseConstants.talmudBavliFolderName),
          ).createSync(recursive: true);
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
        File(
          path.join(tempDir.path, DatabaseConstants.databaseFileName),
        ).readAsBytesSync(),
        const [1, 2, 3],
      );
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
        File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        ).existsSync(),
        isFalse,
      );
      await MagicDictionaryDownloader.installStagedBeforeAttach(lexicalPath);
      expect(File('$lexicalPath.next').existsSync(), isFalse);
      expect(File('$lexicalPath.next.version').existsSync(), isFalse);
      // מילון החיפוש המקורב (לא דחוס) הועתק לתיקיית הספרייה ליד seforim.db.
      expect(File(path.join(tempDir.path, 'lexical.db')).existsSync(), isTrue);
      // סימון הגרסה הוא ה-digest של lexical-v2.db — בלעדיו בדיקת העדכון
      // הבאה תוריד את המילון מחדש.
      expect(
        File(path.join(tempDir.path, 'lexical.db')).readAsBytesSync(),
        lexicalBytes,
      );
      expect(
        File(path.join(tempDir.path, 'lexical.db.version')).readAsStringSync(),
        lexicalDigest,
      );
      // גם לתלמוד נכתב סימון גרסה — digest של הנכס מה-API, כדי שבדיקות עדכון
      // ישוו תוכן ולא תג (תגי otzaria-library מתחלפים כמעט יומית).
      expect(
        File(
          path.join(
            tempDir.path,
            DatabaseConstants.talmudBavliFolderName,
            DatabaseConstants.talmudBavliVersionFileName,
          ),
        ).readAsStringSync(),
        talmudDigest,
      );
    });

    test(
      'DownloadLibraryRequested מוריד DB מפוצל, מחבר ומחלץ את השלם',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-empty-library-split-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const name = 'seforim-schema6.db.zst';
        final whole = utf8.encode('compressed-library-in-two-parts');
        final parts = [whole.sublist(0, 12), whole.sublist(12)];
        String partName(int i) => '$name.part-00$i';
        final manifest = jsonEncode({
          'schemaVersion': 1,
          'archive': name,
          'size': whole.length,
          'sha256': sha256.convert(whole).toString(),
          'parts': [
            for (var i = 0; i < parts.length; i++)
              {
                'name': partName(i),
                'size': parts[i].length,
                'sha256': sha256.convert(parts[i]).toString(),
              },
          ],
        });
        final checkedSizes = <int>[];
        final requested = <String>[];
        final client = MockClient((request) async {
          final url = request.url.toString();
          requested.add(url);
          if (request.url.path.endsWith('/SeforimLibrary/releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': 'v31',
                'assets': [
                  {
                    'name': '$name.manifest.json',
                    'browser_download_url': 'https://example.com/v31/manifest',
                    'size': manifest.length,
                  },
                  for (var i = 0; i < parts.length; i++)
                    {
                      'name': partName(i),
                      'browser_download_url': 'https://example.com/v31/part$i',
                      'size': parts[i].length,
                    },
                ],
              }),
              200,
            );
          }
          if (url == 'https://example.com/v31/manifest') {
            return http.Response(manifest, 200);
          }
          for (var i = 0; i < parts.length; i++) {
            if (url == 'https://example.com/v31/part$i') {
              return http.Response.bytes(parts[i], 200);
            }
          }
          // התלמוד, הקטלוגים והמילון — תוכן כלשהו, אינם עניין הבדיקה.
          if (request.url.host == 'github.com') {
            return http.Response.bytes(utf8.encode('other'), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? extractedDb;
        final bloc = EmptyLibraryBloc(
          httpClient: client,
          downloadSpaceChecker: (size) async {
            if (size != null) checkedSizes.add(size);
            return null;
          },
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                if (path.basename(archivePath) == 'otzaria_$name') {
                  extractedDb = await File(archivePath).readAsBytes();
                }
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final selected = bloc.stream
            .where((state) => state is EmptyLibraryDirectorySelected)
            .first;
        bloc.add(DownloadLibraryRequested());
        await selected.timeout(const Duration(seconds: 5));

        expect(checkedSizes.single, whole.length + parts.last.length + 15);
        expect(extractedDb, whole);
        expect(requested, contains('https://example.com/v31/part1'));
        // שום שריד של החלקים או של הארכיון המחובר אינו נשאר ב-temp.
        expect(
          Directory.systemTemp
              .listSync()
              .map((e) => path.basename(e.path))
              .where((n) => n.startsWith('otzaria_$name')),
          isEmpty,
        );
      },
    );

    test(
      'נכס התלמוד לא קיים באף release → מדלגים בלי לפנות לכתובת ה-latest',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-talmud-missing-',
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
        final catalogBytes = utf8.encode('compressed-catalog');
        final requested = <Uri>[];
        final client = MockClient((request) async {
          requested.add(request.url);
          // otzaria-library: אין נכס תלמוד ב-latest וגם לא ברשימת ה-releases.
          if (request.url.path.contains(
            '/repos/Otzaria/otzaria-library/releases/latest',
          )) {
            return http.Response(
              jsonEncode({'tag_name': 'fordb-latest', 'assets': []}),
              200,
            );
          }
          if (request.url.path.endsWith(
            '/repos/Otzaria/otzaria-library/releases',
          )) {
            return http.Response(jsonEncode([]), 200);
          }
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
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
              request.url.path.endsWith('otzar-HB_catalog.db.zst')) {
            return http.Response.bytes(catalogBytes, 200);
          }
          // המילון (אופציונלי) — 404 מדלג עליו.
          return http.Response('not found', 404);
        });

        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                await File(
                  outputPath,
                ).writeAsBytes(const [1, 2, 3], flush: true);
              },
          extractTarArchive: (a, o, p) async =>
              fail('אסור לחלץ תלמוד כשהנכס לא קיים באף release'),
        );
        addTearDown(bloc.close);

        final selected = bloc.stream
            .where((state) => state is EmptyLibraryDirectorySelected)
            .cast<EmptyLibraryDirectorySelected>()
            .first;
        bloc.add(DownloadLibraryRequested());
        await selected.timeout(const Duration(seconds: 5));

        expect(
          requested.where(
            (u) => u.path.endsWith('talmud_bavli_latest.tar.zst'),
          ),
          isEmpty,
          reason: 'הנכס לא קיים — אין לפנות לכתובת latest/download שתחזיר 404',
        );
      },
    );

    test('פס ההתקדמות מאוחד על פני כל הקבצים — רק הכותרת מתחלפת', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-combined-progress-',
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

      // גדלים שונים בכוונה, כדי לוודא שכולם נספרים יחד.
      final seforimBytes = utf8.encode('A' * 100);
      final talmudBytes = utf8.encode('B' * 200);
      final catalogBytes = utf8.encode('C' * 700);
      final lexicalBytes = utf8.encode('D' * 300);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
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
          return http.Response.bytes(seforimBytes, 200);
        }
        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('talmud_bavli_latest.tar.zst')) {
          return http.Response.bytes(talmudBytes, 200);
        }
        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('otzar-HB_catalog.db.zst')) {
          return http.Response.bytes(catalogBytes, 200);
        }
        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('/lexical-v2.db')) {
          return http.Response.bytes(lexicalBytes, 200);
        }
        return http.Response('not found', 404);
      });

      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);

      final downloading = <EmptyLibraryDownloading>[];
      final sub = bloc.stream.listen((state) {
        if (state is EmptyLibraryDownloading) downloading.add(state);
      });
      addTearDown(sub.cancel);

      final done = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;
      bloc.add(DownloadLibraryRequested());
      await done.timeout(const Duration(seconds: 5));

      // כל הכותרות הופיעו (רק הכותרת מתחלפת בין הקבצים).
      final titles = downloading
          .map((s) => s.message.split('\n').first)
          .toSet();
      expect(
        titles,
        containsAll(<String>[
          'מוריד את ספריית אוצריא',
          'מוריד את התלמוד הבבלי',
          'מוריד את הקטלוגים',
          'מוריד מילון לחיפוש המקורב',
        ]),
      );

      // הפס מאוחד: בזמן הצגת הכותרת של הקובץ הראשון הוא לא מגיע ל-100%
      // (סימן שהוא מתייחס לסכום שלושת הקבצים ולא לקובץ בודד).
      final seforimStates = downloading.where(
        (s) => s.message.startsWith('מוריד את ספריית אוצריא'),
      );
      expect(seforimStates, isNotEmpty);
      expect(
        seforimStates.map((s) => s.progress).reduce((a, b) => a > b ? a : b),
        lessThan(0.5),
      );

      // ההתקדמות לא יורדת ומגיעה ל-100% בסוף — כולל מילון החיפוש המקורב,
      // שהוא כעת חלק מהפס המאוחד ולא שלב נפרד.
      final progresses = downloading.map((s) => s.progress).toList();
      for (var i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
      expect(progresses.last, closeTo(1.0, 1e-9));
    });

    test(
      'מילון קצר מהגודל שדווח נדחה (best-effort) והפס עדיין מגיע ל-100%',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-lexical-fail-',
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

        final seforimBytes = utf8.encode('A' * 100);
        final talmudBytes = utf8.encode('B' * 200);
        final catalogBytes = utf8.encode('C' * 700);
        // HEAD מדווח 10 בייט, אך גוף ה-GET קטוע אחרי 5 — אסור להתקין DB חלקי.
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
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
            return http.Response.bytes(seforimBytes, 200);
          }
          if (request.url.host == 'github.com' &&
              request.url.path.endsWith('talmud_bavli_latest.tar.zst')) {
            return http.Response.bytes(talmudBytes, 200);
          }
          if (request.url.host == 'github.com' &&
              request.url.path.endsWith('otzar-HB_catalog.db.zst')) {
            return http.Response.bytes(catalogBytes, 200);
          }
          if (request.url.host == 'github.com' &&
              request.url.path.endsWith('/lexical-v2.db')) {
            return request.method == 'HEAD'
                ? http.Response.bytes(List.filled(10, 0), 200)
                : http.Response.bytes(List.filled(5, 1), 200);
          }
          return http.Response('not found', 404);
        });

        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final downloading = <EmptyLibraryDownloading>[];
        final sub = bloc.stream.listen((state) {
          if (state is EmptyLibraryDownloading) downloading.add(state);
        });
        addTearDown(sub.cancel);

        final done = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        bloc.add(DownloadLibraryRequested());
        await done.timeout(const Duration(seconds: 5));

        // כשל המילון לא חסם — הספרייה נבחרה.
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryPath),
          tempDir.path,
        );
        // המילון לא הותקן (הורדתו נכשלה), אך פס ההורדה עדיין הגיע ל-100%.
        expect(
          File(path.join(tempDir.path, 'lexical.db')).existsSync(),
          isFalse,
        );
        expect(downloading.last.progress, closeTo(1.0, 1e-9));
      },
    );

    test(
      'קובץ temp חלקי → GET נשלח עם Range, ותגובת 206 מצרפת להמשך הקובץ',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-resume-206-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await _cleanDownloadTemps();
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const seforimUrl = 'https://example.com/releases/seforim.db.zst';
        // שריד חלקי של 50 בייטים + sidecar תואם לזהות הנוכחית (etag+גודל),
        // כדי שקישור-הגרסה לא ימחק את השריד וה-resume ימשיך.
        final seforimTemp = File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        );
        await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
        await File(
          '${seforimTemp.path}.resume',
        ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

        String? seforimGetRange;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
                  {
                    'name': 'seforim.db.zst',
                    'browser_download_url': seforimUrl,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.toString() == seforimUrl) {
            if (request.method == 'HEAD') {
              return http.Response.bytes(
                List.filled(100, 0),
                200,
                headers: const {'etag': 'seforim-v1'},
              );
            }
            seforimGetRange = request.headers['range'];
            return http.Response.bytes(
              List.filled(50, 2),
              206,
              headers: const {'content-range': 'bytes 50-99/100'},
            );
          }
          if (request.url.host == 'github.com') {
            return http.Response.bytes(List.filled(10, 7), 200);
          }
          return http.Response('not found', 404);
        });

        int? seforimArchiveLen;
        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
                  seforimArchiveLen = await File(archivePath).length();
                }
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final done = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        bloc.add(DownloadLibraryRequested());
        await done.timeout(const Duration(seconds: 5));

        // (a) ה-GET נשא Range מהנקודה שנעצרה.
        expect(seforimGetRange, 'bytes=50-');
        // (b) 50 הבייטים הקיימים + 50 מהתגובה = 100 בייט.
        expect(seforimArchiveLen, 100);
      },
    );

    test('416 שאינו מוכיח שלמות גורר הורדה מלאה נקייה', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-resume-416-mismatch-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await _cleanDownloadTemps();
      addTearDown(_cleanDownloadTemps);
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );

      const seforimUrl = 'https://example.com/releases/seforim.db.zst';
      final seforimTemp = File(
        path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
      );
      await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
      await File(
        '${seforimTemp.path}.resume',
      ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

      final ranges = <String?>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'seforim.db.zst', 'browser_download_url': seforimUrl},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == seforimUrl) {
          if (request.method == 'HEAD') {
            return http.Response.bytes(
              List.filled(100, 0),
              200,
              headers: const {'etag': 'seforim-v1'},
            );
          }
          final range = request.headers['range'];
          ranges.add(range);
          if (range != null) {
            return http.Response.bytes(
              const [],
              416,
              headers: const {'content-range': 'bytes */100'},
            );
          }
          return http.Response.bytes(List.filled(100, 4), 200);
        }
        if (request.url.host == 'github.com') {
          return http.Response.bytes(List.filled(10, 7), 200);
        }
        return http.Response('not found', 404);
      });

      List<int>? archiveBytes;
      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
            archiveBytes = await File(archivePath).readAsBytes();
          }
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);

      final done = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;
      bloc.add(DownloadLibraryRequested());
      await done.timeout(const Duration(seconds: 5));

      expect(ranges, ['bytes=50-', null]);
      expect(archiveBytes, hasLength(100));
      expect(archiveBytes!.every((byte) => byte == 4), isTrue);
    });

    test('קובץ temp חלקי אך השרת מחזיר 200 → מוחקים ומתחילים מ-0', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-resume-200-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await _cleanDownloadTemps();
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );

      const seforimUrl = 'https://example.com/releases/seforim.db.zst';
      final seforimTemp = File(
        path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
      );
      await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
      await File(
        '${seforimTemp.path}.resume',
      ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'seforim.db.zst', 'browser_download_url': seforimUrl},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == seforimUrl) {
          if (request.method == 'HEAD') {
            return http.Response.bytes(
              List.filled(100, 0),
              200,
              headers: const {'etag': 'seforim-v1'},
            );
          }
          // השרת מתעלם מ-Range ומחזיר את הקובץ המלא מ-0.
          return http.Response.bytes(List.filled(100, 3), 200);
        }
        if (request.url.host == 'github.com') {
          return http.Response.bytes(List.filled(10, 7), 200);
        }
        return http.Response('not found', 404);
      });

      int? seforimArchiveLen;
      int? seforimFirstByte;
      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
            final bytes = await File(archivePath).readAsBytes();
            seforimArchiveLen = bytes.length;
            seforimFirstByte = bytes.first;
          }
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);

      final done = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;
      bloc.add(DownloadLibraryRequested());
      await done.timeout(const Duration(seconds: 5));

      // (c) הקובץ אותחל מ-0: 100 בייט בלבד, כולם מהתגובה החדשה (לא צירוף).
      expect(seforimArchiveLen, 100);
      expect(seforimFirstByte, 3);
    });

    test(
      'temp שלם-אך-פגום שחילוצו נכשל נמחק, וההרצה הבאה מורידה מחדש (בלי Range)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-extract-fail-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await _cleanDownloadTemps();
        addTearDown(_cleanDownloadTemps);
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const seforimUrl = 'https://example.com/releases/seforim.db.zst';
        final seforimTemp = File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        );
        // שריד שלם משריד קודם — 100 בייט, בדיוק כמו שה-HEAD מדווח, עם sidecar
        // תואם כדי שקישור-הגרסה לא ימחק אותו וייווצר מסלול "כבר שלם".
        await seforimTemp.writeAsBytes(List.filled(100, 9), flush: true);
        await File(
          '${seforimTemp.path}.resume',
        ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

        final seforimGetRanges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
                  {
                    'name': 'seforim.db.zst',
                    'browser_download_url': seforimUrl,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.toString() == seforimUrl) {
            if (request.method == 'HEAD') {
              return http.Response.bytes(
                List.filled(100, 0),
                200,
                headers: const {'etag': 'seforim-v1'},
              );
            }
            seforimGetRanges.add(request.headers['range']);
            return http.Response.bytes(List.filled(100, 4), 200);
          }
          if (request.url.host == 'github.com') {
            return http.Response.bytes(List.filled(10, 7), 200);
          }
          return http.Response('not found', 404);
        });

        EmptyLibraryBloc makeBloc({required bool failSeforim}) =>
            EmptyLibraryBloc(
              httpClient: client,
              defaultLibraryPathOverride: tempDir.path,
              extractCompressedDatabase:
                  (archivePath, outputPath, onProgress) async {
                    if (failSeforim &&
                        path.basename(archivePath) ==
                            'otzaria_seforim.db.zst') {
                      throw Exception('החילוץ נכשל — הקובץ פגום');
                    }
                    await File(outputPath).writeAsBytes(const [1], flush: true);
                  },
              extractTarArchive: (archivePath, outputDir, onProgress) async {},
            );

        // הרצה 1: ההורדה מדולגת (temp שלם), החילוץ נכשל → ה-temp חייב להימחק,
        // אחרת ההרצה הבאה תדלג שוב על ההורדה ותיתקע בלולאה.
        final bloc1 = makeBloc(failSeforim: true);
        addTearDown(bloc1.close);
        final failed = bloc1.stream.where((s) => s is EmptyLibraryError).first;
        bloc1.add(DownloadLibraryRequested());
        await failed.timeout(const Duration(seconds: 5));
        expect(
          seforimGetRanges,
          isEmpty,
          reason: 'temp שלם → אין הורדה בהרצה הראשונה',
        );
        expect(
          seforimTemp.existsSync(),
          isFalse,
          reason: 'כשל בחילוץ חייב למחוק את ה-temp השלם-אך-פגום',
        );

        // הרצה 2: ה-temp נמחק → הורדה טרייה מלאה (בלי Range) והחילוץ מצליח.
        final bloc2 = makeBloc(failSeforim: false);
        addTearDown(bloc2.close);
        final done = bloc2.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        bloc2.add(DownloadLibraryRequested());
        await done.timeout(const Duration(seconds: 5));
        expect(seforimGetRanges, [
          null,
        ], reason: 'הורדה מחדש מ-0 — בלי Range כי ה-temp נמחק');
      },
    );

    test('כשל הרשאה בכתיבה ליעד אינו מוחק את ה-temp שהורד (#2097)', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-target-denied-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await _cleanDownloadTemps();
      addTearDown(_cleanDownloadTemps);
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');

      const seforimUrl = 'https://example.com/releases/seforim.db.zst';
      final seforimTemp = File(
        path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
      );
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'seforim.db.zst', 'browser_download_url': seforimUrl},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == seforimUrl) {
          return http.Response.bytes(
            List.filled(100, 4),
            200,
            headers: const {'etag': 'seforim-v1'},
          );
        }
        if (request.url.host == 'github.com') {
          return http.Response.bytes(List.filled(10, 7), 200);
        }
        return http.Response('not found', 404);
      });

      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
            throw PathAccessException(
              outputPath,
              const OSError('Operation not permitted', 1),
              'Cannot open file',
            );
          }
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);
      final failed = bloc.stream.where((s) => s is EmptyLibraryError).first;
      bloc.add(DownloadLibraryRequested());
      await failed.timeout(const Duration(seconds: 5));
      expect(
        seforimTemp.existsSync(),
        isTrue,
        reason:
            'היעד אינו כתיב, הארכיון תקין — ניסיון חוזר לא צריך להוריד מחדש',
      );
    });

    test(
      '206 עם Content-Range מ-offset לא צפוי → בקשה שנייה בלי Range, קובץ תקין מ-0',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-206-bogus-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await _cleanDownloadTemps();
        addTearDown(_cleanDownloadTemps);
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const seforimUrl = 'https://example.com/releases/seforim.db.zst';
        // שריד חלקי 50 בייט + sidecar תואם → resume מנוסה, אך השרת מחזיר 206
        // מ-offset 30 (לא 50 ולא 0) — append היה פוגם, ולכן נדרשת הורדה מ-0.
        final seforimTemp = File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        );
        await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
        await File(
          '${seforimTemp.path}.resume',
        ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

        final seforimGetRanges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
                  {
                    'name': 'seforim.db.zst',
                    'browser_download_url': seforimUrl,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.toString() == seforimUrl) {
            if (request.method == 'HEAD') {
              return http.Response.bytes(
                List.filled(100, 0),
                200,
                headers: const {'etag': 'seforim-v1'},
              );
            }
            seforimGetRanges.add(request.headers['range']);
            if (request.headers['range'] != null) {
              // 206 מ-offset שגוי — הקוד חייב לנקז, למחוק ולנסות מ-0.
              return http.Response.bytes(
                List.filled(70, 1),
                206,
                headers: const {'content-range': 'bytes 30-99/100'},
              );
            }
            return http.Response.bytes(List.filled(100, 7), 200);
          }
          if (request.url.host == 'github.com') {
            return http.Response.bytes(List.filled(10, 7), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? seforimArchiveBytes;
        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
                  seforimArchiveBytes = await File(archivePath).readAsBytes();
                }
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final done = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        bloc.add(DownloadLibraryRequested());
        await done.timeout(const Duration(seconds: 5));

        expect(seforimGetRanges, [
          'bytes=50-',
          null,
        ], reason: 'ניסיון resume ואז בקשה שנייה בלי Range');
        expect(seforimArchiveBytes, hasLength(100));
        expect(
          seforimArchiveBytes!.every((b) => b == 7),
          isTrue,
          reason: 'הקובץ נכתב מ-0 מהגוף השלם, בלי צירוף לשריד הישן',
        );
      },
    );

    test(
      'temp חלקי + זהות שהשתנתה → מוחקים ומורידים מחדש מ-0 (בלי Range)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-identity-change-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await _cleanDownloadTemps();
        addTearDown(_cleanDownloadTemps);
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const seforimUrl = 'https://example.com/releases/seforim.db.zst';
        // שריד חלקי מגרסה ישנה (sidecar עם etag ישן) → השרת מפרסם etag חדש,
        // ולכן יש למחוק את השריד ולהוריד את הגרסה החדשה מ-0.
        final seforimTemp = File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        );
        await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
        await File(
          '${seforimTemp.path}.resume',
        ).writeAsString('seforim-OLD|100\nseforim-OLD', flush: true);

        final seforimGetRanges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
                  {
                    'name': 'seforim.db.zst',
                    'browser_download_url': seforimUrl,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.toString() == seforimUrl) {
            if (request.method == 'HEAD') {
              return http.Response.bytes(
                List.filled(100, 0),
                200,
                headers: const {'etag': 'seforim-NEW'},
              );
            }
            seforimGetRanges.add(request.headers['range']);
            return http.Response.bytes(List.filled(100, 5), 200);
          }
          if (request.url.host == 'github.com') {
            return http.Response.bytes(List.filled(10, 7), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? seforimArchiveBytes;
        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
                  seforimArchiveBytes = await File(archivePath).readAsBytes();
                }
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final done = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        bloc.add(DownloadLibraryRequested());
        await done.timeout(const Duration(seconds: 5));

        expect(seforimGetRanges, [
          null,
        ], reason: 'זהות שונה → השריד נמחק והורדה מ-0 בלי Range');
        expect(seforimArchiveBytes, hasLength(100));
        expect(
          seforimArchiveBytes!.every((b) => b == 5),
          isTrue,
          reason: 'התקבל התוכן החדש, לא שריד הגרסה הישנה',
        );
      },
    );

    test(
      '206 בלי Content-Range → בקשה שנייה בלי Range, קובץ תקין מ-0',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-206-nocr-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await _cleanDownloadTemps();
        addTearDown(_cleanDownloadTemps);
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const seforimUrl = 'https://example.com/releases/seforim.db.zst';
        // שריד חלקי 50 בייט + sidecar תואם → resume מנוסה, אך השרת מחזיר 206 ללא
        // Content-Range — offset הגוף לא מאומת, ולכן נדרשת הורדה מ-0.
        final seforimTemp = File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        );
        await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
        await File(
          '${seforimTemp.path}.resume',
        ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

        final seforimGetRanges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
                  {
                    'name': 'seforim.db.zst',
                    'browser_download_url': seforimUrl,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.toString() == seforimUrl) {
            if (request.method == 'HEAD') {
              return http.Response.bytes(
                List.filled(100, 0),
                200,
                headers: const {'etag': 'seforim-v1'},
              );
            }
            seforimGetRanges.add(request.headers['range']);
            if (request.headers['range'] != null) {
              // 206 ללא Content-Range — הקוד חייב לנקז, למחוק ולנסות מ-0.
              return http.Response.bytes(List.filled(50, 1), 206);
            }
            return http.Response.bytes(List.filled(100, 7), 200);
          }
          if (request.url.host == 'github.com') {
            return http.Response.bytes(List.filled(10, 7), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? seforimArchiveBytes;
        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
                  seforimArchiveBytes = await File(archivePath).readAsBytes();
                }
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final done = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        bloc.add(DownloadLibraryRequested());
        await done.timeout(const Duration(seconds: 5));

        expect(seforimGetRanges, [
          'bytes=50-',
          null,
        ], reason: 'ניסיון resume ואז בקשה שנייה בלי Range');
        expect(seforimArchiveBytes, hasLength(100));
        expect(
          seforimArchiveBytes!.every((b) => b == 7),
          isTrue,
          reason: 'הקובץ נכתב מ-0 מהגוף השלם, בלי צירוף לשריד הישן',
        );
      },
    );

    test('בקשת resume נושאת If-Range כשה-etag חזק', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-ifrange-strong-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await _cleanDownloadTemps();
      addTearDown(_cleanDownloadTemps);
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );

      const seforimUrl = 'https://example.com/releases/seforim.db.zst';
      final seforimTemp = File(
        path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
      );
      await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
      await File(
        '${seforimTemp.path}.resume',
      ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

      String? seforimIfRange;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'seforim.db.zst', 'browser_download_url': seforimUrl},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == seforimUrl) {
          if (request.method == 'HEAD') {
            return http.Response.bytes(
              List.filled(100, 0),
              200,
              headers: const {'etag': 'seforim-v1'},
            );
          }
          seforimIfRange = request.headers['if-range'];
          return http.Response.bytes(
            List.filled(50, 2),
            206,
            headers: const {'content-range': 'bytes 50-99/100'},
          );
        }
        if (request.url.host == 'github.com') {
          return http.Response.bytes(List.filled(10, 7), 200);
        }
        return http.Response('not found', 404);
      });

      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);

      final done = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;
      bloc.add(DownloadLibraryRequested());
      await done.timeout(const Duration(seconds: 5));

      expect(
        seforimIfRange,
        'seforim-v1',
        reason: 'etag חזק → If-Range נשלח יחד עם Range',
      );
    });

    test('שריד עם etag חלש נמחק ומורד מחדש בלי Range/If-Range', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-ifrange-weak-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await _cleanDownloadTemps();
      addTearDown(_cleanDownloadTemps);
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );

      const seforimUrl = 'https://example.com/releases/seforim.db.zst';
      const weakEtag = 'W/"seforim-v1"';
      final seforimTemp = File(
        path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
      );
      await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
      await File(
        '${seforimTemp.path}.resume',
      ).writeAsString('$weakEtag|100\n$weakEtag', flush: true);

      String? seforimRange;
      String? seforimIfRange;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'seforim.db.zst', 'browser_download_url': seforimUrl},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == seforimUrl) {
          if (request.method == 'HEAD') {
            return http.Response.bytes(
              List.filled(100, 0),
              200,
              headers: const {'etag': weakEtag},
            );
          }
          seforimRange = request.headers['range'];
          seforimIfRange = request.headers['if-range'];
          return http.Response.bytes(List.filled(100, 2), 200);
        }
        if (request.url.host == 'github.com') {
          return http.Response.bytes(List.filled(10, 7), 200);
        }
        return http.Response('not found', 404);
      });

      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);

      final done = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;
      bloc.add(DownloadLibraryRequested());
      await done.timeout(const Duration(seconds: 5));

      expect(seforimRange, isNull, reason: 'אין resume ללא validator חזק');
      expect(seforimIfRange, isNull, reason: 'etag חלש אינו חוקי ב-If-Range');
    });
    test('שרת מחזיר 200 ל-If-Range (הקובץ השתנה) → התחלה נקייה מ-0', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria-ifrange-200-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      await _cleanDownloadTemps();
      addTearDown(_cleanDownloadTemps);
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );

      const seforimUrl = 'https://example.com/releases/seforim.db.zst';
      final seforimTemp = File(
        path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
      );
      await seforimTemp.writeAsBytes(List.filled(50, 9), flush: true);
      await File(
        '${seforimTemp.path}.resume',
      ).writeAsString('seforim-v1|100\nseforim-v1', flush: true);

      String? seforimIfRange;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'assets': [
                {'name': 'seforim.db.zst', 'browser_download_url': seforimUrl},
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        if (request.url.toString() == seforimUrl) {
          if (request.method == 'HEAD') {
            return http.Response.bytes(
              List.filled(100, 0),
              200,
              headers: const {'etag': 'seforim-v1'},
            );
          }
          seforimIfRange = request.headers['if-range'];
          // הקובץ המרוחק השתנה — If-Range גורם ל-200 עם הגוף המלא מ-0.
          return http.Response.bytes(List.filled(100, 3), 200);
        }
        if (request.url.host == 'github.com') {
          return http.Response.bytes(List.filled(10, 7), 200);
        }
        return http.Response('not found', 404);
      });

      int? seforimArchiveLen;
      int? seforimFirstByte;
      final bloc = EmptyLibraryBloc(
        httpClient: client,
        defaultLibraryPathOverride: tempDir.path,
        extractCompressedDatabase: (archivePath, outputPath, onProgress) async {
          if (path.basename(archivePath) == 'otzaria_seforim.db.zst') {
            final bytes = await File(archivePath).readAsBytes();
            seforimArchiveLen = bytes.length;
            seforimFirstByte = bytes.first;
          }
          await File(outputPath).writeAsBytes(const [1], flush: true);
        },
        extractTarArchive: (archivePath, outputDir, onProgress) async {},
      );
      addTearDown(bloc.close);

      final done = bloc.stream
          .where((s) => s is EmptyLibraryDirectorySelected)
          .first;
      bloc.add(DownloadLibraryRequested());
      await done.timeout(const Duration(seconds: 5));

      expect(seforimIfRange, 'seforim-v1');
      // התחלה נקייה: 100 בייט מהגוף החדש בלבד (לא צירוף לשריד).
      expect(seforimArchiveLen, 100);
      expect(seforimFirstByte, 3);
    });

    test(
      'DownloadLibraryRequested עם targetPath מוריד אל היעד ולא לברירת המחדל',
      () async {
        final defaultDir = await Directory.systemTemp.createTemp(
          'otzaria-dl-default-',
        );
        final targetDir = await Directory.systemTemp.createTemp(
          'otzaria-dl-target-',
        );
        addTearDown(() async {
          for (final d in [defaultDir, targetDir]) {
            if (await d.exists()) await d.delete(recursive: true);
          }
        });

        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');

        final client = MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
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
            return http.Response.bytes(utf8.encode('db'), 200);
          }
          if (request.url.host == 'github.com' &&
              request.url.path.endsWith('talmud_bavli_latest.tar.zst')) {
            return http.Response.bytes(utf8.encode('talmud'), 200);
          }
          if (request.url.host == 'github.com' &&
              request.url.path.endsWith('otzar-HB_catalog.db.zst')) {
            return http.Response.bytes(utf8.encode('catalog'), 200);
          }
          return http.Response('not found', 404);
        });

        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: defaultDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final selectedFuture = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .cast<EmptyLibraryDirectorySelected>()
            .first;

        bloc.add(DownloadLibraryRequested(targetPath: targetDir.path));

        final selected = await selectedFuture.timeout(
          const Duration(seconds: 5),
        );

        expect(selected.selectedPath, targetDir.path);
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryPath),
          targetDir.path,
        );
      },
    );

    test(
      'UpdateLibraryRequested מוריד DB חדש ומוחק את הגיבוי בהצלחה',
      () async {
        final libDir = await Directory.systemTemp.createTemp(
          'otzaria-update-lib-',
        );
        addTearDown(() async {
          if (await libDir.exists()) await libDir.delete(recursive: true);
        });

        final dbName = DatabaseConstants.databaseFileName;
        await File(path.join(libDir.path, dbName)).writeAsString('old-db');

        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          libDir.path,
        );

        final bloc = _updateBloc(() => 'new-db');
        addTearDown(bloc.close);

        final selectedFuture = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .cast<EmptyLibraryDirectorySelected>()
            .first;

        bloc.add(
          UpdateLibraryRequested(
            targetPath: libDir.path,
            existingLibraryPath: libDir.path,
          ),
        );

        await selectedFuture.timeout(const Duration(seconds: 5));

        // הקובץ החדש הוחלף במקום הישן, והגיבוי הזמני נמחק.
        expect(
          await File(path.join(libDir.path, dbName)).readAsString(),
          'new-db',
        );
        await _eventually(
          () => !Directory(EmptyLibraryBloc.dbBackupDirPath).existsSync(),
        );
      },
    );

    group('promoteStagedImport', () {
      final dbName = DatabaseConstants.databaseFileName;
      late Directory staging;
      late Directory target;

      setUp(() async {
        staging = await Directory.systemTemp.createTemp('otzaria-staging-');
        target = await Directory.systemTemp.createTemp('otzaria-target-');
      });
      tearDown(() async {
        for (final d in [staging, target]) {
          if (await d.exists()) await d.delete(recursive: true);
        }
      });

      test(
        'דורס התנגשות שם, ממזג תיקיות מקוננות ומשמר קבצים שרק ביעד',
        () async {
          await File(
            path.join(staging.path, 'lexical.db'),
          ).writeAsString('new');
          await Directory(
            path.join(staging.path, 'talmud', 'shas'),
          ).create(recursive: true);
          await File(
            path.join(staging.path, 'talmud', 'shas', 'brachot.txt'),
          ).writeAsString('new-brachot');
          await File(path.join(staging.path, dbName)).writeAsString('new-db');

          await File(path.join(target.path, 'lexical.db')).writeAsString('old');
          await Directory(
            path.join(target.path, 'talmud', 'shas'),
          ).create(recursive: true);
          await File(
            path.join(target.path, 'talmud', 'shas', 'brachot.txt'),
          ).writeAsString('old-brachot');
          await File(
            path.join(target.path, 'talmud', 'keep.txt'),
          ).writeAsString('mine');
          await File(path.join(target.path, dbName)).writeAsString('old-db');
          await File(
            path.join(target.path, '$dbName-wal'),
          ).writeAsString('wal');

          await EmptyLibraryBloc.promoteStagedImport(staging.path, target.path);

          String read(List<String> parts) => File(
            path.join(target.path, path.joinAll(parts)),
          ).readAsStringSync();
          expect(read(['lexical.db']), 'new');
          expect(read(['talmud', 'shas', 'brachot.txt']), 'new-brachot');
          expect(read(['talmud', 'keep.txt']), 'mine');
          expect(read([dbName]), 'new-db');
          // לוואי ישן של ה-DB שהוחלף היה מבלבל את SQLite — נמחק.
          expect(
            File(path.join(target.path, '$dbName-wal')).existsSync(),
            isFalse,
          );
          expect(staging.listSync(), isEmpty);
        },
      );

      test('מילון חדש ב-ZIP מבטל עותק ממתין ישן לפני פתיחה ללא רשת', () async {
        final dest = path.join(target.path, 'lexical.db');
        await File(path.join(staging.path, 'lexical.db')).writeAsString('new');
        await File(dest).writeAsString('old');
        await File('$dest.next').writeAsString('staged-old');
        await File('$dest.next.version').writeAsString('old-digest');

        await EmptyLibraryBloc.promoteStagedImport(staging.path, target.path);
        await MagicDictionaryDownloader.installStagedBeforeAttach(dest);

        expect(await File(dest).readAsString(), 'new');
        expect(
          await File('$dest.version').readAsString(),
          sha256.convert(utf8.encode('new')).toString(),
        );
        expect(File('$dest.next').existsSync(), isFalse);
        expect(File('$dest.next.version').existsSync(), isFalse);
      });

      test('ZIP בלי מילון אינו מבטל עותק ממתין תקין', () async {
        final dest = path.join(target.path, 'lexical.db');
        await File(path.join(staging.path, dbName)).writeAsString('new-db');
        await File(dest).writeAsString('old');
        await File('$dest.next').writeAsString('staged-new');
        await File('$dest.next.version').writeAsString('new-digest');

        await EmptyLibraryBloc.promoteStagedImport(staging.path, target.path);

        expect(await File('$dest.next').readAsString(), 'staged-new');
        expect(await File('$dest.next.version').readAsString(), 'new-digest');
        await MagicDictionaryDownloader.installStagedBeforeAttach(dest);
        expect(await File(dest).readAsString(), 'staged-new');
      });

      test('כשל בייבוא ZIP לפני העברת קבצים אינו מבטל עותק ממתין', () async {
        final dest = path.join(target.path, 'lexical.db');
        await File(dest).writeAsString('old');
        await File('$dest.next').writeAsString('staged-new');
        await File('$dest.next.version').writeAsString('new-digest');
        await staging.delete();

        await expectLater(
          EmptyLibraryBloc.promoteStagedImport(staging.path, target.path),
          throwsA(isA<FileSystemException>()),
        );

        expect(await File(dest).readAsString(), 'old');
        expect(await File('$dest.next').readAsString(), 'staged-new');
        expect(await File('$dest.next.version').readAsString(), 'new-digest');
      });

      test('בלי seforim.db בביניים — שאר הפריטים עוברים והיעד נשמר', () async {
        await File(path.join(staging.path, 'lexical.db')).writeAsString('new');
        await File(path.join(target.path, dbName)).writeAsString('old-db');

        await EmptyLibraryBloc.promoteStagedImport(staging.path, target.path);

        expect(
          File(path.join(target.path, 'lexical.db')).readAsStringSync(),
          'new',
        );
        expect(
          File(path.join(target.path, dbName)).readAsStringSync(),
          'old-db',
        );
      });

      test('כשל בהעברת התוכן — ה-DB שביעד שלם, כי הוא עובר אחרון', () async {
        if (Platform.isWindows) return;
        await File(path.join(staging.path, dbName)).writeAsString('new-db');
        await Directory(path.join(staging.path, 'talmud')).create();
        await File(
          path.join(staging.path, 'talmud', 'a.txt'),
        ).writeAsString('new');
        final blocked = await Directory(
          path.join(target.path, 'talmud'),
        ).create();
        await File(path.join(target.path, dbName)).writeAsString('old-db');
        await Process.run('chmod', ['555', blocked.path]);
        addTearDown(() => Process.run('chmod', ['755', blocked.path]));
        try {
          File(path.join(blocked.path, 'probe')).writeAsStringSync('x');
          return; // ההרשאות אינן נאכפות (root) — אין מה לבדוק
        } catch (_) {}

        await expectLater(
          EmptyLibraryBloc.promoteStagedImport(staging.path, target.path),
          throwsA(isA<FileSystemException>()),
        );

        expect(
          File(path.join(target.path, dbName)).readAsStringSync(),
          'old-db',
        );
        expect(File(path.join(staging.path, dbName)).existsSync(), isTrue);
      });
    });

    group('גיבוי DB יתום מריצה שנהרגה', () {
      final dbName = DatabaseConstants.databaseFileName;

      // תיקיית temp פרטית לכל טסט: הגיבוי הוא שם קבוע אחד, וריצה שנהרגה
      // הייתה מותירה אותו לריצה הבאה.
      late Directory tempRoot;

      /// תיקיות גיבוי בכל שם שהוא (גם עם timestamp) — כדי לתפוס הצטברות.
      Iterable<Directory> backupDirs() => tempRoot
          .listSync()
          .whereType<Directory>()
          .where((d) => path.basename(d.path).startsWith('otzaria_db_backup'));

      Future<void> createOrphan(
        String content, {
        String? dirPath,
        DateTime? modified,
      }) async {
        final orphan = Directory(dirPath ?? EmptyLibraryBloc.dbBackupDirPath);
        await orphan.create(recursive: true);
        final db = File(path.join(orphan.path, dbName));
        await db.writeAsString(content);
        if (modified != null) await db.setLastModified(modified);
        await File(path.join(orphan.path, '$dbName-wal')).writeAsString('wal');
      }

      setUp(() async {
        tempRoot = await Directory.systemTemp.createTemp('otzaria-temp-root-');
        EmptyLibraryBloc.tempRootOverride = tempRoot.path;
      });
      tearDown(() async {
        EmptyLibraryBloc.tempRootOverride = null;
        if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
      });

      test(
        'בעלייה: ספרייה בלי DB + יתום עם DB → ה-DB חוזר והיתום נעלם',
        () async {
          final libDir = await Directory.systemTemp.createTemp(
            'otzaria-orphan-',
          );
          addTearDown(() => libDir.delete(recursive: true));
          await createOrphan('orphaned-db');

          await EmptyLibraryBloc.recoverOrphanedDbBackup(libDir.path);

          expect(
            await File(path.join(libDir.path, dbName)).readAsString(),
            'orphaned-db',
          );
          expect(
            File(path.join(libDir.path, '$dbName-wal')).existsSync(),
            isTrue,
          );
          expect(backupDirs(), isEmpty);
        },
      );

      test(
        'בעלייה: גם תיקיות ישנות עם timestamp — ה-DB חוזר מהחדשה לפי mtime, '
        'הכול נמחק',
        () async {
          final libDir = await Directory.systemTemp.createTemp(
            'otzaria-orphan-',
          );
          addTearDown(() => libDir.delete(recursive: true));
          final tmp = tempRoot.path;
          final now = DateTime.now();
          // השם הנמוך ביותר מחזיק את הקובץ החדש ביותר — כדי לוודא שהבחירה
          // היא לפי mtime ולא לפי סדר השמות.
          await createOrphan(
            'newest-db',
            dirPath: path.join(tmp, 'otzaria_db_backup_100'),
            modified: now,
          );
          await createOrphan(
            'older-db',
            dirPath: path.join(tmp, 'otzaria_db_backup_900'),
            modified: now.subtract(const Duration(hours: 1)),
          );
          await createOrphan(
            'oldest-db',
            modified: now.subtract(const Duration(days: 1)),
          );

          await EmptyLibraryBloc.recoverOrphanedDbBackup(libDir.path);

          expect(
            await File(path.join(libDir.path, dbName)).readAsString(),
            'newest-db',
          );
          expect(backupDirs(), isEmpty);
        },
      );

      test(
        'בעלייה: ההחזרה נכשלת (יעד לא קיים) → אף גיבוי לא נמחק',
        () async {
          final tmp = tempRoot.path;
          final now = DateTime.now();
          await createOrphan(
            'newest-db',
            modified: now,
          );
          await createOrphan(
            'older-db',
            dirPath: path.join(tmp, 'otzaria_db_backup_1'),
            modified: now.subtract(const Duration(hours: 1)),
          );
          // תיקייה שאינה קיימת (כונן שהוסר) — ההזזה תזרוק.
          final missing = path.join(tmp, 'otzaria-missing-lib', 'books');

          await expectLater(
            EmptyLibraryBloc.recoverOrphanedDbBackup(missing),
            throwsA(isA<FileSystemException>()),
          );

          expect(backupDirs().length, 2);
        },
      );

      test(
        'בעלייה: `.new` חלקי אינו נחשב DB — היתום שורד וההחזרה מתבצעת',
        () async {
          final libDir = await Directory.systemTemp.createTemp(
            'otzaria-orphan-',
          );
          addTearDown(() => libDir.delete(recursive: true));
          await File(
            path.join(libDir.path, '$dbName.new'),
          ).writeAsString('partial');
          await createOrphan('orphaned-db');

          await EmptyLibraryBloc.recoverOrphanedDbBackup(libDir.path);

          expect(
            await File(path.join(libDir.path, dbName)).readAsString(),
            'orphaned-db',
          );
          expect(
            File(path.join(libDir.path, '$dbName.new')).existsSync(),
            isFalse,
          );
          expect(backupDirs(), isEmpty);
        },
      );

      test('בעלייה: תיקיית `.import` יתומה מייבוא שנקטע נמחקת', () async {
        final libDir = await Directory.systemTemp.createTemp('otzaria-orphan-');
        addTearDown(() => libDir.delete(recursive: true));
        await File(path.join(libDir.path, dbName)).writeAsString('good-db');
        final staging = Directory(EmptyLibraryBloc.stagingDirFor(libDir.path));
        addTearDown(() async {
          if (await staging.exists()) await staging.delete(recursive: true);
        });
        await staging.create(recursive: true);
        await File(path.join(staging.path, dbName)).writeAsString('partial');

        await EmptyLibraryBloc.recoverOrphanedDbBackup(libDir.path);

        expect(staging.existsSync(), isFalse);
        expect(
          await File(path.join(libDir.path, dbName)).readAsString(),
          'good-db',
        );
      });

      test(
        'בעלייה: יתום כשיש DB תקין בספרייה → היתום נמחק וה-DB לא נדרס',
        () async {
          final libDir = await Directory.systemTemp.createTemp(
            'otzaria-orphan-',
          );
          addTearDown(() => libDir.delete(recursive: true));
          await File(path.join(libDir.path, dbName)).writeAsString('good-db');
          await createOrphan('stale-db');

          await EmptyLibraryBloc.recoverOrphanedDbBackup(libDir.path);

          expect(
            await File(path.join(libDir.path, dbName)).readAsString(),
            'good-db',
          );
          expect(backupDirs(), isEmpty);
        },
      );

      test(
        'עדכון אחרי ריצה שנהרגה: ה-DB היתום משוחזר, מגובה שוב, ולא מצטבר',
        () async {
          final libDir = await Directory.systemTemp.createTemp(
            'otzaria-orphan-',
          );
          addTearDown(() async {
            if (await libDir.exists()) await libDir.delete(recursive: true);
          });
          // הריצה הקודמת נהרגה אחרי ההזזה: הספרייה ריקה, ה-DB בגיבוי.
          await createOrphan('old-db');
          // ההורדה תיכשל, והגיבוי (שהוא ה-DB היתום) חייב לחזור.
          String? served;
          await Settings.init(cacheProvider: _MemoryCacheProvider());
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            libDir.path,
          );
          final bloc = _updateBloc(() => served);
          addTearDown(bloc.close);
          final errorFuture = bloc.stream
              .where((s) => s is EmptyLibraryError)
              .first;

          bloc.add(
            UpdateLibraryRequested(
              targetPath: libDir.path,
              existingLibraryPath: libDir.path,
            ),
          );
          await errorFuture.timeout(const Duration(seconds: 5));

          expect(
            await File(path.join(libDir.path, dbName)).readAsString(),
            'old-db',
          );
          expect(backupDirs(), isEmpty);

          // ריצה שנייה שנהרגה שוב (יתום לצד DB תקין) ואחריה עדכון מוצלח —
          // לא נשארת אף תיקיית גיבוי, לא ישנה ולא חדשה.
          await createOrphan('stale-db');
          served = 'new-db';
          final selectedFuture = bloc.stream
              .where((s) => s is EmptyLibraryDirectorySelected)
              .first;
          bloc.add(
            UpdateLibraryRequested(
              targetPath: libDir.path,
              existingLibraryPath: libDir.path,
            ),
          );
          await selectedFuture.timeout(const Duration(seconds: 5));

          expect(
            await File(path.join(libDir.path, dbName)).readAsString(),
            'new-db',
          );
          await _eventually(() => backupDirs().isEmpty);
        },
      );
    });

    test(
      'UpdateLibraryRequested משחזר את הגיבוי כשההורדה נכשלת',
      () async {
        final libDir = await Directory.systemTemp.createTemp(
          'otzaria-update-lib2-',
        );
        addTearDown(() async {
          if (await libDir.exists()) await libDir.delete(recursive: true);
        });

        final dbName = DatabaseConstants.databaseFileName;
        await File(path.join(libDir.path, dbName)).writeAsString('old-db');

        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          libDir.path,
        );

        final bloc = _updateBloc(() => null);
        addTearDown(bloc.close);

        final errorFuture = bloc.stream
            .where((s) => s is EmptyLibraryError)
            .cast<EmptyLibraryError>()
            .first;

        bloc.add(
          UpdateLibraryRequested(
            targetPath: libDir.path,
            existingLibraryPath: libDir.path,
          ),
        );

        await errorFuture.timeout(const Duration(seconds: 5));

        // הקובץ הישן שוחזר, והגיבוי נוקה.
        expect(
          await File(path.join(libDir.path, dbName)).readAsString(),
          'old-db',
        );
        expect(
          Directory(EmptyLibraryBloc.dbBackupDirPath).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'StorageLocationSelected שומר את שורש הספרייה ומרענן מצב התחלה',
      () async {
        await Settings.init(cacheProvider: _MemoryCacheProvider());

        final bloc = EmptyLibraryBloc();
        addTearDown(bloc.close);

        const sdRoot = '/storage/ABCD-1234/Android/data/pkg/files';
        final done = bloc.stream
            .where(
              (s) =>
                  s is EmptyLibraryInitial &&
                  Settings.getValue<String>(
                        SettingsRepository.keyAndroidLibraryRoot,
                      ) ==
                      sdRoot,
            )
            .first;
        bloc.add(StorageLocationSelected(sdRoot));
        await done.timeout(const Duration(seconds: 5));

        expect(
          Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
          sdRoot,
        );
      },
    );

    test(
      'משתמש בכתובות ההורדה המדויקות של התלמוד, הקטלוג והמילון',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'otzaria-exact-urls-',
        );
        final lexicalPath = path.join(tempDir.path, 'lexical.db');
        await File('$lexicalPath.next').writeAsString('staged-old');
        await File('$lexicalPath.next.version').writeAsString('old-digest');
        addTearDown(() async {
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
        await _cleanDownloadTemps();
        addTearDown(_cleanDownloadTemps);
        await Settings.init(cacheProvider: _MemoryCacheProvider());
        await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryFolderName,
          '',
        );

        const seforimUrl = 'https://example.com/releases/seforim.db.zst';
        const talmudUrl =
            'https://github.com/Otzaria/otzaria-library/releases/latest/download/talmud_bavli_latest.tar.zst';
        const catalogUrl =
            'https://github.com/Otzaria/otzar-HB_catalog/releases/latest/download/otzar-HB_catalog.db.zst';
        const lexicalUrl =
            'https://github.com/Otzaria/SeforimMagicIndexer/releases/latest/download/lexical-v2.db';
        final requestedUrls = <String>[];

        final client = MockClient((request) async {
          requestedUrls.add(request.url.toString());
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'assets': [
                  {
                    'name': 'seforim.db.zst',
                    'browser_download_url': seforimUrl,
                  },
                ],
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (request.url.toString() == talmudUrl ||
              request.url.toString() == catalogUrl ||
              request.url.toString() == lexicalUrl) {
            return http.Response.bytes(utf8.encode('ok'), 200);
          }
          if (request.url.toString() == seforimUrl) {
            return http.Response.bytes(utf8.encode('ok'), 200);
          }
          return http.Response('not found', 404);
        });

        final bloc = EmptyLibraryBloc(
          httpClient: client,
          defaultLibraryPathOverride: tempDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                await File(outputPath).writeAsBytes(const [1], flush: true);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {},
        );
        addTearDown(bloc.close);

        final done = bloc.stream
            .where((s) => s is EmptyLibraryDirectorySelected)
            .first;
        final error = bloc.stream
            .where((s) => s is EmptyLibraryError)
            .cast<EmptyLibraryError>();
        bloc.add(DownloadLibraryRequested());

        final result = await Future.any([
          done.then((_) => 'success'),
          error.first.then((e) => 'error: ${e.errorMessage}'),
        ]).timeout(const Duration(seconds: 5));

        expect(result, 'success');
        await MagicDictionaryDownloader.installStagedBeforeAttach(lexicalPath);
        expect(await File(lexicalPath).readAsString(), 'ok');
        expect(
          await File('$lexicalPath.version').readAsString(),
          sha256.convert(utf8.encode('ok')).toString(),
        );
        expect(File('$lexicalPath.next').existsSync(), isFalse);
        expect(File('$lexicalPath.next.version').existsSync(), isFalse);
        expect(
          requestedUrls,
          containsAll([seforimUrl, talmudUrl, catalogUrl, lexicalUrl]),
        );
      },
    );
  });
}

/// מוחק שרידי קבצי temp של הורדות קודמות כדי שבדיקות resume לא יושפעו מהם.
Future<void> _cleanDownloadTemps() async {
  const names = [
    'otzaria_seforim.db.zst',
    'otzaria_talmud_bavli.tar.zst',
    'otzaria_otzar-HB_catalog.db.zst',
    'otzaria_lexical.db',
  ];
  for (final name in names) {
    final f = File(path.join(Directory.systemTemp.path, name));
    if (await f.exists()) await f.delete();
    final meta = File(path.join(Directory.systemTemp.path, '$name.meta'));
    if (await meta.exists()) await meta.delete();
    final resume = File(path.join(Directory.systemTemp.path, '$name.resume'));
    if (await resume.exists()) await resume.delete();
  }
}

/// DirectorySelected נפלט לפני שהמטפל מוחק את הגיבוי; ממתינים לסיום המחיקה.
Future<void> _eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('התנאי לא התקיים תוך 5 שניות');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// bloc לעדכון ספרייה בהורדה; [db] null — ההורדה נכשלת.
EmptyLibraryBloc _updateBloc(String? Function() db) => EmptyLibraryBloc(
  httpClient: fakeLibraryReleaseClient(db),
  extractCompressedDatabase: copyAsExtracted,
  extractTarArchive: ignoreTarArchive,
);

final class _IsolatedTempOverrides extends IOOverrides {
  _IsolatedTempOverrides(this.root);

  final Directory root;

  @override
  Directory getSystemTempDirectory() => root;
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
