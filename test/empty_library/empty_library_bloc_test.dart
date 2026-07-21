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

    test(
      'בחירת seforim.db.zst מחבילת FULL מחלצת גם קטלוג ותלמוד בבלי למיקום הספרייה המוגדר',
      () async {
        final sourceDir = await Directory.systemTemp.createTemp(
          'otzaria-bundle-extract-src-',
        );
        final libraryDir = await Directory.systemTemp.createTemp(
          'otzaria-bundle-extract-lib-',
        );
        addTearDown(() async {
          for (final dir in [sourceDir, libraryDir]) {
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          }
        });

        // יצירת 3 קבצי zst דמה כפי שמוצאים אחרי חילוץ otzaria-android-full.zip:
        final seforimZst = File(
          path.join(sourceDir.path, DatabaseConstants.databaseArchiveFileName),
        );
        await seforimZst.writeAsString('fake-seforim-zst');

        final catalogZst = File(
          path.join(
            sourceDir.path,
            DatabaseConstants.externalCatalogArchiveFileName,
          ),
        );
        await catalogZst.writeAsString('fake-catalog-zst');

        final talmudZst = File(
          path.join(
            sourceDir.path,
            DatabaseConstants.talmudBavliArchiveFileName,
          ),
        );
        await talmudZst.writeAsString('fake-talmud-tar-zst');

        await Settings.init(cacheProvider: _MemoryCacheProvider());

        final compressedExtractions = <String>[];
        final tarExtractions = <String>[];

        final bloc = EmptyLibraryBloc(
          defaultLibraryPathOverride: libraryDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                // המקור נשאר בתיקיית הקובץ שנבחר, היעד הוא מיקום הספרייה
                expect(path.dirname(archivePath), sourceDir.path);
                expect(path.dirname(outputPath), libraryDir.path);
                compressedExtractions.add(
                  '${path.basename(archivePath)}→${path.basename(outputPath)}',
                );
                await File(outputPath).writeAsBytes(const [1, 2, 3]);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {
            expect(path.dirname(archivePath), sourceDir.path);
            expect(outputDir, libraryDir.path);
            tarExtractions.add(path.basename(archivePath));
          },
        );
        addTearDown(bloc.close);

        final askDeleteFuture = bloc.stream
            .where((state) => state is EmptyLibraryAskingDeleteZip)
            .cast<EmptyLibraryAskingDeleteZip>()
            .first;

        bloc.add(PickArchiveFileRequested(overrideFilePath: seforimZst.path));

        final askState = await askDeleteFuture.timeout(
          const Duration(seconds: 5),
        );

        expect(askState.zipPath, seforimZst.path);
        expect(askState.extractedPath, libraryDir.path);

        // כל 3 הקבצים חולצו ב-tap אחד:
        expect(compressedExtractions, [
          '${DatabaseConstants.databaseArchiveFileName}→${DatabaseConstants.databaseFileName}',
          '${DatabaseConstants.externalCatalogArchiveFileName}→${DatabaseConstants.externalCatalogDatabaseFileName}',
        ]);
        expect(tarExtractions, [DatabaseConstants.talmudBavliArchiveFileName]);
      },
    );

    test(
      'בחירת seforim.db.zst לבד (בלי קבצים נלווים) מחלצת רק את ה-DB',
      () async {
        final sourceDir = await Directory.systemTemp.createTemp(
          'otzaria-single-zst-src-',
        );
        final libraryDir = await Directory.systemTemp.createTemp(
          'otzaria-single-zst-lib-',
        );
        addTearDown(() async {
          for (final dir in [sourceDir, libraryDir]) {
            if (await dir.exists()) {
              await dir.delete(recursive: true);
            }
          }
        });

        final seforimZst = File(
          path.join(sourceDir.path, DatabaseConstants.databaseArchiveFileName),
        );
        await seforimZst.writeAsString('fake-seforim-zst');

        await Settings.init(cacheProvider: _MemoryCacheProvider());

        final compressedExtractions = <String>[];
        final tarExtractions = <String>[];

        final bloc = EmptyLibraryBloc(
          defaultLibraryPathOverride: libraryDir.path,
          extractCompressedDatabase:
              (archivePath, outputPath, onProgress) async {
                expect(path.dirname(outputPath), libraryDir.path);
                compressedExtractions.add(path.basename(archivePath));
                await File(outputPath).writeAsBytes(const [1, 2, 3]);
              },
          extractTarArchive: (archivePath, outputDir, onProgress) async {
            tarExtractions.add(path.basename(archivePath));
          },
        );
        addTearDown(bloc.close);

        final askDeleteFuture = bloc.stream
            .where((state) => state is EmptyLibraryAskingDeleteZip)
            .cast<EmptyLibraryAskingDeleteZip>()
            .first;

        bloc.add(PickArchiveFileRequested(overrideFilePath: seforimZst.path));

        await askDeleteFuture.timeout(const Duration(seconds: 5));

        // רק ה-DB הראשי חולץ; אין ניסיון לחלץ קבצים שאינם נמצאים.
        expect(compressedExtractions, [
          DatabaseConstants.databaseArchiveFileName,
        ]);
        expect(tarExtractions, isEmpty);
      },
    );

    test('DownloadLibraryRequested מוריד DB מהרליס האחרון ומחלץ אותו', () async {
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
      final lexicalBytes = utf8.encode('lexical-dictionary');
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

        // כמו GitHub: releases/latest/download מפנה לנתיב עם תג ה-release.
        if (request.url.host == 'github.com' &&
            request.url.path.contains('/releases/latest/download/') &&
            request.url.path.endsWith('/lexical.db')) {
          return http.Response(
            '',
            302,
            headers: const {
              'location':
                  'https://github.com/Otzaria/SeforimMagicIndexer/releases/download/v0.3.0/lexical.db',
            },
          );
        }

        if (request.url.host == 'github.com' &&
            request.url.path.endsWith('/lexical.db')) {
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
        extractTarArchive: (archivePath, outputDir, onProgress) async {
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
        File(
          path.join(Directory.systemTemp.path, 'otzaria_seforim.db.zst'),
        ).existsSync(),
        isFalse,
      );
      // מילון החיפוש המקורב (לא דחוס) הועתק לתיקיית הספרייה ליד seforim.db.
      expect(File(path.join(tempDir.path, 'lexical.db')).existsSync(), isTrue);
      // סימון הגרסה נכתב מהתג שבשרשרת ה-redirect — בלעדיו בדיקת העדכון
      // הבאה תוריד את המילון מחדש בכל הפעלה.
      expect(
        File(path.join(tempDir.path, 'lexical.db.version')).readAsStringSync(),
        'v0.3.0',
      );
    });

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
            request.url.path.endsWith('/lexical.db')) {
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
              request.url.path.endsWith('/lexical.db')) {
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
