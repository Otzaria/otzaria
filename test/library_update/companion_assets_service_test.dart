import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/search/magic_dictionary_downloader.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('companion_assets_test');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  const tag = 'v2.0.0';
  const assetUrl = 'https://x/talmud_bavli_latest.tar.zst';

  MockClient releaseClient({List<Uri>? requested}) {
    return MockClient((request) async {
      requested?.add(request.url);
      if (request.url.path.contains('releases/latest')) {
        return http.Response(
          jsonEncode({
            'tag_name': tag,
            'assets': [
              {
                'name': DatabaseConstants.talmudBavliArchiveFileName,
                'browser_download_url': assetUrl,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.toString() == assetUrl) {
        return http.Response.bytes([1, 2, 3], 200);
      }
      return http.Response('not found', 404);
    });
  }

  CompanionAssetsService service({
    http.Client? client,
    _FakeCatalogRepository? catalog,
    _FakeDictionaryDownloader? dictionary,
    List<({String archive, String outputDir})>? extractions,
    List<String>? talmudDirs,
    void Function()? invalidate,
    void Function()? invalidateLibrary,
    bool failExtraction = false,
    Object? extractionError,
  }) {
    return CompanionAssetsService(
      clientFactory: () => client ?? releaseClient(),
      catalogRepository: () => catalog ?? _FakeCatalogRepository(exists: true),
      dictionaryFactory: () => dictionary ?? _FakeDictionaryDownloader(),
      extractTarArchive: (archive, outputDir, onProgress) async {
        if (failExtraction) throw Exception('החילוץ נקטע');
        if (extractionError != null) throw extractionError;
        extractions?.add((archive: archive, outputDir: outputDir));
        onProgress?.call(0.5);
        onProgress?.call(1.0);
        Directory(
          p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
        ).createSync(recursive: true);
      },
      talmudDirsProvider: () =>
          talmudDirs ??
          [p.join(tmp.path, DatabaseConstants.talmudBavliFolderName)],
      invalidateExternalBooksCache: invalidate ?? () {},
      invalidateLibraryCaches: invalidateLibrary ?? () {},
    );
  }

  String talmudDir() =>
      p.join(tmp.path, DatabaseConstants.talmudBavliFolderName);

  void createTalmudDir({String? markerTag}) {
    final dir = Directory(talmudDir())..createSync(recursive: true);
    File(p.join(dir.path, 'ברכות.pdf')).writeAsStringSync('pdf');
    if (markerTag != null) {
      File(
        p.join(dir.path, CompanionAssetsService.talmudVersionFileName),
      ).writeAsStringSync(markerTag);
    }
  }

  String? readMarker() {
    final f = File(
      p.join(talmudDir(), CompanionAssetsService.talmudVersionFileName),
    );
    return f.existsSync() ? f.readAsStringSync().trim() : null;
  }

  void writeResumeState(File file, String identity, {String etag = '"e1"'}) {
    File('${file.path}.resume').writeAsStringSync('$identity\n$etag');
  }

  void cleanupTalmudTemp(File file) {
    if (file.existsSync()) file.deleteSync();
    for (final suffix in const ['.meta', '.resume']) {
      final sidecar = File('${file.path}$suffix');
      if (sidecar.existsSync()) sidecar.deleteSync();
    }
  }

  group('תלמוד בבלי', () {
    test('תיקייה חסרה → מוריד, מחלץ לתיקיית האב, וכותב סימון גרסה', () async {
      final extractions = <({String archive, String outputDir})>[];
      final statuses = <String>[];
      final progress = <int>[];
      var libraryInvalidated = 0;
      final changed =
          await service(
            extractions: extractions,
            invalidateLibrary: () => libraryInvalidated++,
          ).verifyAndUpdate(
            onStatus: statuses.add,
            onDownloadProgress: (done, total) => progress.add(done),
          );

      expect(extractions, hasLength(1));
      expect(extractions.single.outputDir, tmp.path);
      expect(readMarker(), tag);
      expect(
        changed,
        isTrue,
        reason: 'התקנת תלמוד משנה את הספרייה — נדרש ריענון',
      );
      expect(
        libraryInvalidated,
        1,
        reason: 'בלי ניקוי ה-cache הריענון לא יגלה את התיקייה החדשה',
      );
      // מד בזמן החילוץ (שלב ה-zst), ומעבר לספינר בשלב פריסת ה-tar.
      expect(statuses, contains('מחלץ את התלמוד הבבלי'));
      expect(statuses, contains('פורס את קבצי התלמוד'));
      expect(progress, contains(5000));
    });

    test('תיקייה קיימת ללא סימון → מחתים את התג בלי להוריד', () async {
      createTalmudDir();
      final requested = <Uri>[];
      final extractions = <({String archive, String outputDir})>[];
      final changed = await service(
        client: releaseClient(requested: requested),
        extractions: extractions,
      ).verifyAndUpdate();

      expect(readMarker(), tag);
      expect(extractions, isEmpty);
      expect(requested.map((u) => u.toString()), isNot(contains(assetUrl)));
      expect(changed, isFalse, reason: 'החתמה בלבד אינה שינוי בספרייה');
    });

    test('סימון תואם לתג → לא מוריד ולא נוגע', () async {
      createTalmudDir(markerTag: tag);
      final extractions = <({String archive, String outputDir})>[];
      await service(extractions: extractions).verifyAndUpdate();
      expect(extractions, isEmpty);
    });

    test('סימון ישן → מוריד ומעדכן את הסימון', () async {
      createTalmudDir(markerTag: 'v1.0.0');
      final extractions = <({String archive, String outputDir})>[];
      await service(extractions: extractions).verifyAndUpdate();

      expect(extractions, hasLength(1));
      expect(readMarker(), tag);
    });

    test('חילוץ שנקטע משאיר סימון-ביניים, והריצה הבאה מורידה מחדש', () async {
      await service(failExtraction: true).verifyAndUpdate();
      expect(readMarker(), CompanionAssetsService.talmudInstallingMarker);

      final extractions = <({String archive, String outputDir})>[];
      await service(extractions: extractions).verifyAndUpdate();
      expect(extractions, hasLength(1));
      expect(readMarker(), tag);
    });

    test(
      'כשל בחילוץ (קובץ שלם-אך-פגום) מוחק את ה-temp, וההרצה הבאה מורידה מחדש',
      () async {
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        cleanupTalmudTemp(talmudTemp);
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        final assetRanges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.contains('releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': tag,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            assetRanges.add(request.headers['range']);
            return http.Response.bytes(List.filled(100, 5), 200);
          }
          return http.Response('not found', 404);
        });

        // הרצה 1: ההורדה מצליחה אך החילוץ נכשל — ה-temp השלם-אך-פגום חייב להימחק,
        // אחרת ההרצה הבאה תזהה 416 (קובץ שלם) ותיתקע בלולאה בלי להוריד מחדש.
        await service(client: client, failExtraction: true).verifyAndUpdate();
        expect(
          talmudTemp.existsSync(),
          isFalse,
          reason: 'כשל בחילוץ חייב למחוק את ה-temp כדי לכפות הורדה מחדש',
        );

        // הרצה 2: הורדה טרייה מלאה (בלי Range), החילוץ מצליח וה-temp נמחק.
        final extractions = <({String archive, String outputDir})>[];
        await service(
          client: client,
          extractions: extractions,
        ).verifyAndUpdate();
        expect(assetRanges, [
          null,
          null,
        ], reason: 'שתי ההרצות מורידות מ-0 — אין Range על קובץ שנמחק');
        expect(extractions, hasLength(1));
        expect(
          talmudTemp.existsSync(),
          isFalse,
          reason: 'אחרי חילוץ מוצלח הקובץ הזמני נמחק',
        );
      },
    );

    test(
      'FileSystemException בשלב החילוץ משאיר את ה-temp — '
      'בלי הורדת גוף מלאה חוזרת',
      () async {
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        cleanupTalmudTemp(talmudTemp);
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        final ranges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.contains('releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': tag,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                    'size': 100,
                    'id': 1,
                    'updated_at': 't1',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            ranges.add(request.headers['range']);
            if (request.headers['range'] != null) {
              return http.Response(
                '',
                416,
                headers: const {'content-range': 'bytes */100'},
              );
            }
            return http.Response.bytes(
              List.filled(100, 5),
              200,
              headers: const {'etag': '"e1"'},
            );
          }
          return http.Response('not found', 404);
        });

        // הרצה 1: ההורדה מצליחה אך המחלץ זורק FileSystemException (מדמה קובץ
        // יעד נעול) — הארכיון הזמני נשמר כדי שההרצה הבאה לא תוריד שוב ~440MB.
        await service(
          client: client,
          extractionError: const FileSystemException('קובץ נעול'),
        ).verifyAndUpdate();
        expect(readMarker(), CompanionAssetsService.talmudInstallingMarker);
        expect(
          talmudTemp.existsSync(),
          isTrue,
          reason: 'כשל נעילה אינו ארכיון פגום — אין למחוק את ההורדה',
        );

        // הרצה 2: הנעילה שוחררה — החילוץ מצליח מהשריד, בלי הורדת גוף נוספת.
        final extractions = <({String archive, String outputDir})>[];
        await service(
          client: client,
          extractions: extractions,
        ).verifyAndUpdate();
        expect(extractions, hasLength(1));
        expect(readMarker(), tag);
        expect(
          ranges.where((r) => r == null),
          hasLength(1),
          reason: 'הגוף המלא הורד פעם אחת בלבד — ההרצה השנייה השתמשה בשריד',
        );
        expect(
          talmudTemp.existsSync(),
          isFalse,
          reason: 'אחרי חילוץ מוצלח הקובץ הזמני נמחק',
        );
      },
    );

    test(
      'קובץ יעד נעול באמת בזמן ניקוי הקבצים הישנים משאיר את ה-temp',
      skip: Platform.isWindows ? null : 'נעילת קבצים חוסמת מחיקה רק ב-Windows',
      () async {
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        cleanupTalmudTemp(talmudTemp);
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        // handle פתוח על קובץ קיים — deleteSync של ניקוי הישנים ייכשל עליו.
        createTalmudDir(markerTag: 'v1.0.0');
        final lock = File(p.join(talmudDir(), 'ברכות.pdf')).openSync();
        var locked = true;
        addTearDown(() {
          if (locked) lock.closeSync();
        });

        await service().verifyAndUpdate();
        expect(readMarker(), CompanionAssetsService.talmudInstallingMarker);
        expect(
          talmudTemp.existsSync(),
          isTrue,
          reason: 'הנעילה נכשלה אחרי ההורדה — הארכיון חייב להישמר ל-resume',
        );

        lock.closeSync();
        locked = false;
        final extractions = <({String archive, String outputDir})>[];
        await service(extractions: extractions).verifyAndUpdate();
        expect(extractions, hasLength(1));
        expect(readMarker(), tag);
      },
    );

    test(
      'temp חלקי + 206 בלי Content-Range → בקשה שנייה בלי Range, קובץ תקין מ-0',
      () async {
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        // שריד חלקי של 50 בייטים + sidecar תואם לזהות (תג+גודל=0 כי אין size
        // ב-JSON), כדי שקישור-הגרסה לא ימחק את השריד וה-resume ימשיך.
        talmudTemp.writeAsBytesSync(List.filled(50, 9));
        writeResumeState(talmudTemp, '$tag|0||');
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        final ranges = <String?>[];
        final ifRanges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.contains('releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': tag,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            ranges.add(request.headers['range']);
            ifRanges.add(request.headers['if-range']);
            if (request.headers['range'] != null) {
              // 206 ללא Content-Range — offset הגוף לא מאומת; יש לנקז ולהוריד מ-0.
              return http.Response.bytes(List.filled(50, 5), 206);
            }
            return http.Response.bytes(List.filled(100, 7), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? archiveBytes;
        final svc = CompanionAssetsService(
          clientFactory: () => client,
          catalogRepository: () => _FakeCatalogRepository(exists: true),
          dictionaryFactory: () => _FakeDictionaryDownloader(),
          extractTarArchive: (archive, outputDir, onProgress) async {
            archiveBytes = File(archive).readAsBytesSync();
            Directory(
              p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
            ).createSync(recursive: true);
          },
          talmudDirsProvider: () => [
            p.join(tmp.path, DatabaseConstants.talmudBavliFolderName),
          ],
          invalidateExternalBooksCache: () {},
          invalidateLibraryCaches: () {},
        );
        await svc.verifyAndUpdate();

        expect(ranges, [
          'bytes=50-',
          null,
        ], reason: 'ניסיון resume ואז בקשה שנייה בלי Range');
        expect(ifRanges, ['"e1"', null]);
        expect(archiveBytes, hasLength(100));
        expect(
          archiveBytes!.every((b) => b == 7),
          isTrue,
          reason: 'הקובץ נכתב מ-0 מהגוף השלם, בלי צירוף לשריד הישן',
        );
      },
    );

    test(
      'temp שלם מגרסה ישנה + תג חדש → לא מחלץ ישן; מוריד מחדש ומחתים תג חדש',
      () async {
        createTalmudDir(markerTag: 'v1.0.0');
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        // שריד שלם מגרסה קודמת + sidecar עם זהות ישנה — חייב להימחק כדי שלא
        // יזוהה כשלם (416) ויוחתם בתג החדש בלי להוריד את התוכן העדכני.
        talmudTemp.writeAsBytesSync(List.filled(100, 9));
        writeResumeState(talmudTemp, 'v1.0.0|3');
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        final ranges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.contains('releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': tag,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                    'size': 3,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            ranges.add(request.headers['range']);
            // התנהגות שרת לקובץ-שלם: Range → 416. הקוד הישן היה מדלג ומחלץ ישן.
            if (request.headers['range'] != null) {
              return http.Response('', 416);
            }
            return http.Response.bytes(List.filled(3, 5), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? archiveBytes;
        final svc = CompanionAssetsService(
          clientFactory: () => client,
          catalogRepository: () => _FakeCatalogRepository(exists: true),
          dictionaryFactory: () => _FakeDictionaryDownloader(),
          extractTarArchive: (archive, outputDir, onProgress) async {
            archiveBytes = File(archive).readAsBytesSync();
            Directory(
              p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
            ).createSync(recursive: true);
          },
          talmudDirsProvider: () => [
            p.join(tmp.path, DatabaseConstants.talmudBavliFolderName),
          ],
          invalidateExternalBooksCache: () {},
          invalidateLibraryCaches: () {},
        );
        await svc.verifyAndUpdate();

        expect(
          ranges,
          [null],
          reason: 'זהות שונה → השריד נמחק, בקשה טרייה בלי Range (לא 416/דילוג)',
        );
        expect(archiveBytes, [
          5,
          5,
          5,
        ], reason: 'חולץ התוכן החדש, לא שריד הגרסה הישנה');
        expect(readMarker(), tag);
      },
    );

    test(
      '206 מ-offset לא צפוי → בקשה שנייה בלי Range, קובץ תקין מ-0',
      () async {
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        // שריד חלקי 50 בייט + sidecar תואם → resume מנוסה, אך השרת מחזיר 206
        // מ-offset 30 (לא 50 ולא 0) — append היה פוגם, ולכן נדרשת הורדה מ-0.
        talmudTemp.writeAsBytesSync(List.filled(50, 9));
        writeResumeState(talmudTemp, '$tag|0||');
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        final ranges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.contains('releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': tag,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            ranges.add(request.headers['range']);
            if (request.headers['range'] != null) {
              return http.Response.bytes(
                List.filled(70, 1),
                206,
                headers: const {'content-range': 'bytes 30-99/100'},
              );
            }
            return http.Response.bytes(List.filled(100, 7), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? archiveBytes;
        final svc = CompanionAssetsService(
          clientFactory: () => client,
          catalogRepository: () => _FakeCatalogRepository(exists: true),
          dictionaryFactory: () => _FakeDictionaryDownloader(),
          extractTarArchive: (archive, outputDir, onProgress) async {
            archiveBytes = File(archive).readAsBytesSync();
            Directory(
              p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
            ).createSync(recursive: true);
          },
          talmudDirsProvider: () => [
            p.join(tmp.path, DatabaseConstants.talmudBavliFolderName),
          ],
          invalidateExternalBooksCache: () {},
          invalidateLibraryCaches: () {},
        );
        await svc.verifyAndUpdate();

        expect(ranges, [
          'bytes=50-',
          null,
        ], reason: 'ניסיון resume ואז בקשה שנייה בלי Range');
        expect(archiveBytes, hasLength(100));
        expect(
          archiveBytes!.every((b) => b == 7),
          isTrue,
          reason: 'הקובץ נכתב מ-0 מהגוף השלם, בלי צירוף לשריד הישן',
        );
      },
    );

    test('416 שסותר את אורך החלקי גורם להורדה מלאה מחדש', () async {
      createTalmudDir(markerTag: 'v1.0.0');
      final talmudTemp = File(
        p.join(
          Directory.systemTemp.path,
          'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
        ),
      );
      cleanupTalmudTemp(talmudTemp);
      talmudTemp.writeAsBytesSync(List.filled(5, 9));
      writeResumeState(talmudTemp, '$tag|10|1|t1');
      addTearDown(() => cleanupTalmudTemp(talmudTemp));

      final ranges = <String?>[];
      final client = MockClient((request) async {
        if (request.url.path.contains('releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': tag,
              'assets': [
                {
                  'name': DatabaseConstants.talmudBavliArchiveFileName,
                  'browser_download_url': assetUrl,
                  'size': 10,
                  'id': 1,
                  'updated_at': 't1',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.toString() == assetUrl) {
          ranges.add(request.headers['range']);
          if (request.headers['range'] != null) {
            return http.Response(
              '',
              416,
              headers: const {'content-range': 'bytes */10'},
            );
          }
          return http.Response.bytes(
            List.filled(10, 5),
            200,
            headers: const {'etag': '"e1"'},
          );
        }
        return http.Response('not found', 404);
      });

      List<int>? archiveBytes;
      final svc = CompanionAssetsService(
        clientFactory: () => client,
        catalogRepository: () => _FakeCatalogRepository(exists: true),
        dictionaryFactory: () => _FakeDictionaryDownloader(),
        extractTarArchive: (archive, outputDir, onProgress) async {
          archiveBytes = File(archive).readAsBytesSync();
          Directory(
            p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
          ).createSync(recursive: true);
        },
        talmudDirsProvider: () => [
          p.join(tmp.path, DatabaseConstants.talmudBavliFolderName),
        ],
        invalidateExternalBooksCache: () {},
        invalidateLibraryCaches: () {},
      );
      await svc.verifyAndUpdate();

      expect(ranges, ['bytes=5-', null]);
      expect(archiveBytes, hasLength(10));
      expect(readMarker(), tag);
    });

    test(
      'אותו תג+גודל אך asset id שונה (העלאה-מחדש) → מוחק את ה-temp ומוריד מחדש',
      () async {
        final talmudTemp = File(
          p.join(
            Directory.systemTemp.path,
            'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
          ),
        );
        // שריד שלם התואם תג+גודל, אך sidecar עם id ישן — העלאה-מחדש תחת אותו תג
        // וגודל שינתה את ה-id, ולכן יש למחוק את השריד ולהוריד את התוכן העדכני.
        talmudTemp.writeAsBytesSync(List.filled(3, 9));
        writeResumeState(talmudTemp, '$tag|3|111|old-ts');
        addTearDown(() => cleanupTalmudTemp(talmudTemp));

        final ranges = <String?>[];
        final client = MockClient((request) async {
          if (request.url.path.contains('releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': tag,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                    'size': 3,
                    'id': 222,
                    'updated_at': 'new-ts',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            ranges.add(request.headers['range']);
            // שריד שלם יחזיר 416 ב-Range — אם הזהות לא נבדקה יחולץ תוכן ישן.
            if (request.headers['range'] != null) {
              return http.Response('', 416);
            }
            return http.Response.bytes(List.filled(3, 5), 200);
          }
          return http.Response('not found', 404);
        });

        List<int>? archiveBytes;
        final svc = CompanionAssetsService(
          clientFactory: () => client,
          catalogRepository: () => _FakeCatalogRepository(exists: true),
          dictionaryFactory: () => _FakeDictionaryDownloader(),
          extractTarArchive: (archive, outputDir, onProgress) async {
            archiveBytes = File(archive).readAsBytesSync();
            Directory(
              p.join(outputDir, DatabaseConstants.talmudBavliFolderName),
            ).createSync(recursive: true);
          },
          talmudDirsProvider: () => [
            p.join(tmp.path, DatabaseConstants.talmudBavliFolderName),
          ],
          invalidateExternalBooksCache: () {},
          invalidateLibraryCaches: () {},
        );
        await svc.verifyAndUpdate();

        expect(
          ranges,
          [null],
          reason: 'id שונה → השריד נמחק, בקשה טרייה בלי Range (לא 416/דילוג)',
        );
        expect(archiveBytes, [
          5,
          5,
          5,
        ], reason: 'חולץ התוכן החדש שהועלה-מחדש, לא שריד הזהות הישנה');
      },
    );

    test('עדכון מנקה קובץ ישן שהוסר ב-release החדש', () async {
      createTalmudDir(markerTag: 'v1.0.0');
      final stale = File(p.join(talmudDir(), 'מסכת_שהוסרה.pdf'))
        ..writeAsStringSync('old');

      await service().verifyAndUpdate();

      expect(
        stale.existsSync(),
        isFalse,
        reason: 'קבצים ישנים לא אמורים לשרוד עדכון',
      );
      expect(readMarker(), tag);
    });

    test(
      'הנכס חסר ב-release האחרון → נלקח מה-release הקודם שמכיל אותו',
      () async {
        final requested = <Uri>[];
        final client = MockClient((request) async {
          requested.add(request.url);
          // release אחרון בסגנון fordb — בלי נכס תלמוד.
          if (request.url.path.endsWith('/releases/latest')) {
            return http.Response(
              jsonEncode({
                'tag_name': 'fordb-latest',
                'assets': [
                  {
                    'name': 'fordb_latest.zip',
                    'browser_download_url': 'https://x/fordb_latest.zip',
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              jsonEncode([
                {
                  'tag_name': 'fordb-latest',
                  'prerelease': false,
                  'assets': [
                    {
                      'name': 'fordb_latest.zip',
                      'browser_download_url': 'https://x/fordb_latest.zip',
                    },
                  ],
                },
                {
                  'tag_name': tag,
                  'prerelease': false,
                  'assets': [
                    {
                      'name': DatabaseConstants.talmudBavliArchiveFileName,
                      'browser_download_url': assetUrl,
                    },
                  ],
                },
              ]),
              200,
            );
          }
          if (request.url.toString() == assetUrl) {
            return http.Response.bytes([1, 2, 3], 200);
          }
          return http.Response('not found', 404);
        });

        final extractions = <({String archive, String outputDir})>[];
        await service(
          client: client,
          extractions: extractions,
        ).verifyAndUpdate();

        expect(extractions, hasLength(1));
        expect(readMarker(), tag);
        expect(
          requested.any((u) => u.path.endsWith('/releases')),
          isTrue,
          reason: 'הנכס חסר ב-latest — נדרשת סריקת רשימת ה-releases',
        );
      },
    );

    test('הנכס נמצא רק בעמוד השני של רשימת ה-releases', () async {
      Map<String, dynamic> fordbRelease(String tagName) => {
        'tag_name': tagName,
        'prerelease': false,
        'assets': [
          {
            'name': 'fordb_latest.zip',
            'browser_download_url': 'https://x/fordb_latest.zip',
          },
        ],
      };
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(jsonEncode(fordbRelease('fordb-latest')), 200);
        }
        if (request.url.path.endsWith('/releases')) {
          if (request.url.queryParameters['page'] == '1') {
            return http.Response(
              jsonEncode([fordbRelease('fordb-1'), fordbRelease('fordb-2')]),
              200,
            );
          }
          return http.Response(
            jsonEncode([
              {
                'tag_name': tag,
                'prerelease': false,
                'assets': [
                  {
                    'name': DatabaseConstants.talmudBavliArchiveFileName,
                    'browser_download_url': assetUrl,
                  },
                ],
              },
            ]),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final release = await CompanionAssetsService.findLatestTalmudRelease(
        client,
      );
      expect(release.tag, tag);
      expect(release.assetUrl, assetUrl);
    });

    test('הנכס לא קיים באף release → TalmudAssetNotFoundException', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            jsonEncode({'tag_name': 'fordb-latest', 'assets': []}),
            200,
          );
        }
        if (request.url.path.endsWith('/releases')) {
          // עמוד ראשון בלי הנכס, עמוד שני ריק — הסריקה הסתיימה.
          final body = request.url.queryParameters['page'] == '1'
              ? [
                  {'tag_name': 'fordb-1', 'prerelease': false, 'assets': []},
                ]
              : <Object>[];
          return http.Response(jsonEncode(body), 200);
        }
        return http.Response('not found', 404);
      });

      await expectLater(
        CompanionAssetsService.findLatestTalmudRelease(client),
        throwsA(isA<TalmudAssetNotFoundException>()),
      );
    });

    test('כשל ב-API של התלמוד לא עוצר את הקטלוג והמילון', () async {
      final catalog = _FakeCatalogRepository(exists: true);
      final dictionary = _FakeDictionaryDownloader();
      final failing = MockClient((_) async => http.Response('boom', 500));
      await service(
        client: failing,
        catalog: catalog,
        dictionary: dictionary,
      ).verifyAndUpdate();

      expect(catalog.updateCalled, isTrue);
      expect(dictionary.ensureCalled, isTrue);
    });

    test('ביטול אחרי התלמוד מדלג על השאר', () async {
      createTalmudDir(markerTag: tag);
      final catalog = _FakeCatalogRepository(exists: true);
      await service(catalog: catalog).verifyAndUpdate(isCancelled: () => true);
      expect(catalog.updateCalled, isFalse);
    });
  });

  group('תלמוד בבלי — השוואת digest', () {
    // תגי otzaria-library מתחלפים כמעט יומית עם אותו קובץ תלמוד — הזיהוי חייב
    // להשוות תוכן (digest) ולא תג, אחרת כל release גורר הורדת ~440MB מיותרת.
    final bodyDigest = sha256.convert([1, 2, 3]).toString();
    const otherDigest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    MockClient digestClient({
      required String latestDigest,
      String? installedTagDigest,
      List<Uri>? requested,
    }) {
      return MockClient((request) async {
        requested?.add(request.url);
        if (request.url.path.contains('/releases/tags/')) {
          if (installedTagDigest == null) {
            return http.Response('not found', 404);
          }
          return http.Response(
            jsonEncode({
              'tag_name': request.url.pathSegments.last,
              'assets': [
                {
                  'name': DatabaseConstants.talmudBavliArchiveFileName,
                  'browser_download_url': assetUrl,
                  'digest': 'sha256:$installedTagDigest',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.contains('releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': tag,
              'assets': [
                {
                  'name': DatabaseConstants.talmudBavliArchiveFileName,
                  'browser_download_url': assetUrl,
                  'digest': 'sha256:$latestDigest',
                  'size': 3,
                },
              ],
            }),
            200,
          );
        }
        if (request.url.toString() == assetUrl) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response('not found', 404);
      });
    }

    File talmudTempFile() => File(
      p.join(
        Directory.systemTemp.path,
        'otzaria_${DatabaseConstants.talmudBavliArchiveFileName}',
      ),
    );

    test('תג התחלף אך ה-digest זהה → מחתים digest בלי להוריד', () async {
      createTalmudDir(markerTag: 'v1.0.0');
      final requested = <Uri>[];
      final extractions = <({String archive, String outputDir})>[];
      final changed = await service(
        client: digestClient(
          latestDigest: bodyDigest,
          installedTagDigest: bodyDigest,
          requested: requested,
        ),
        extractions: extractions,
      ).verifyAndUpdate();

      expect(extractions, isEmpty);
      expect(requested.map((u) => u.toString()), isNot(contains(assetUrl)));
      expect(readMarker(), bodyDigest);
      expect(changed, isFalse, reason: 'החתמת digest בלבד אינה שינוי בספרייה');
    });

    test('תג התחלף וה-digest שונה → מוריד ומחתים את ה-digest החדש', () async {
      createTalmudDir(markerTag: 'v1.0.0');
      cleanupTalmudTemp(talmudTempFile());
      addTearDown(() => cleanupTalmudTemp(talmudTempFile()));
      final extractions = <({String archive, String outputDir})>[];
      await service(
        client: digestClient(
          latestDigest: bodyDigest,
          installedTagDigest: otherDigest,
        ),
        extractions: extractions,
      ).verifyAndUpdate();

      expect(extractions, hasLength(1));
      expect(readMarker(), bodyDigest);
    });

    test('סימון digest תואם → לא מוריד ולא פונה ל-API של התג', () async {
      createTalmudDir(markerTag: bodyDigest);
      final requested = <Uri>[];
      final extractions = <({String archive, String outputDir})>[];
      await service(
        client: digestClient(latestDigest: bodyDigest, requested: requested),
        extractions: extractions,
      ).verifyAndUpdate();

      expect(extractions, isEmpty);
      expect(
        requested.where((u) => u.path.contains('/releases/tags/')),
        isEmpty,
      );
      expect(readMarker(), bodyDigest);
    });

    test('התג המותקן כבר לא קיים ב-GitHub (404) → מוריד', () async {
      createTalmudDir(markerTag: 'v1.0.0');
      cleanupTalmudTemp(talmudTempFile());
      addTearDown(() => cleanupTalmudTemp(talmudTempFile()));
      final extractions = <({String archive, String outputDir})>[];
      await service(
        client: digestClient(latestDigest: bodyDigest),
        extractions: extractions,
      ).verifyAndUpdate();

      expect(extractions, hasLength(1));
      expect(readMarker(), bodyDigest);
    });

    test('תיקייה קיימת ללא סימון → מחתים digest ולא תג', () async {
      createTalmudDir();
      await service(
        client: digestClient(latestDigest: bodyDigest),
      ).verifyAndUpdate();
      expect(readMarker(), bodyDigest);
    });
  });

  group('קטלוג otzar-HB', () {
    test('קיים → בודק עדכון; עדכון בפועל מרענן את הקאש', () async {
      final catalog = _FakeCatalogRepository(exists: true, updateResult: true);
      var invalidated = 0;
      createTalmudDir(markerTag: tag);
      final changed = await service(
        catalog: catalog,
        invalidate: () => invalidated++,
      ).verifyAndUpdate();

      expect(catalog.updateCalled, isTrue);
      expect(catalog.downloadCalled, isFalse);
      expect(invalidated, 1);
      expect(changed, isTrue);
    });

    test('קיים ומעודכן → לא מדווח שינוי', () async {
      final catalog = _FakeCatalogRepository(exists: true);
      createTalmudDir(markerTag: tag);
      final changed = await service(catalog: catalog).verifyAndUpdate();
      expect(changed, isFalse);
    });

    test('חסר → מוריד', () async {
      final catalog = _FakeCatalogRepository(exists: false);
      createTalmudDir(markerTag: tag);
      final changed = await service(catalog: catalog).verifyAndUpdate();
      expect(catalog.downloadCalled, isTrue);
      expect(changed, isTrue);
    });
  });

  test('המילון: ensureLatest נקרא ו-dispose משוחרר', () async {
    final dictionary = _FakeDictionaryDownloader();
    createTalmudDir(markerTag: tag);
    await service(dictionary: dictionary).verifyAndUpdate();
    expect(dictionary.ensureCalled, isTrue);
    expect(dictionary.disposed, isTrue);
  });
}

class _FakeCatalogRepository extends ExternalCatalogRepository {
  _FakeCatalogRepository({required this.exists, this.updateResult = false})
    : super(httpClient: MockClient((_) async => http.Response('', 404)));

  final bool exists;
  final bool updateResult;
  bool updateCalled = false;
  bool downloadCalled = false;

  @override
  Future<bool> databaseExists() async => exists;

  @override
  Future<bool> updateDatabaseIfNeeded() async {
    updateCalled = true;
    return updateResult;
  }

  @override
  Future<void> downloadLatestDatabase() async {
    downloadCalled = true;
  }
}

class _FakeDictionaryDownloader extends MagicDictionaryDownloader {
  _FakeDictionaryDownloader()
    : super(client: MockClient((_) async => http.Response('', 404)));

  bool ensureCalled = false;
  bool disposed = false;

  @override
  Future<bool> ensureLatest({
    void Function(double progress)? onProgress,
    bool force = false,
  }) async {
    ensureCalled = true;
    return true;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
