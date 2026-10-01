import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';
import 'package:otzaria/library_update/services/streaming_patch_downloader.dart';
import 'package:otzaria/library_update/services/update_sqlite_setup.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('library_update_repository_test');
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      tmp.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('ה-planner של האפליקציה מצהיר על הסכמה שהיא קוראת', () {
    final repository = LibraryUpdateRepository(
      discovery: _unusedDiscovery(),
      downloader: StreamingPatchDownloader(),
    );
    expect(DatabaseConstants.readableDbSchemaVersion, 6);
    expect(
      DatabaseConstants.readableDbSchemaVersion,
      lessThanOrEqualTo(kSupportedDbSchemaVersion),
    );
    expect(
      repository.planner.supportedDbSchemaVersion,
      DatabaseConstants.readableDbSchemaVersion,
    );
    // ברירת המחדל של ה-updater נשארת 5, כדי ש-build ישן לא יוריד סכמה 6.
    expect(const LibraryUpdatePlanner().supportedDbSchemaVersion, 5);
  });

  test(
    'applyFullDownload מוריד, מחלץ, מאמת ומחליף DB קטן מקומית',
    () async {
      final lib = _tryOpenSystemLibzstd();
      if (lib == null) {
        markTestSkipped('libzstd אינו זמין במערכת');
        return;
      }

      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final archive = _fixtureFullDbArchive();
      final refresh = _NoopRefreshService();
      final downloader = PatchDownloader(
        httpClient: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(archive),
            200,
            contentLength: archive.length,
          );
        }),
        decompress: (bytes) async => bytes,
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: downloader,
        refreshService: refresh,
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-06-28T00:00:00Z',
        diskSpaceProvider: (_) async => DiskSpaceInfo.unknown,
        fullDbExtractor: (archivePath, outputPath) async {
          decompressSyncForTest(
            archivePath,
            outputPath,
            lib,
          );
        },
      );
      final plan = LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 2,
        asset: ReleaseAsset(
          name: DatabaseConstants.databaseArchiveFileName,
          downloadUrl: 'https://x/seforim.db.zst',
          size: archive.length,
        ),
        releaseTag: 'v2',
      );

      await repository.applyFullDownload(plan);

      expect(const LocalDbVersionReader().read(dbPath).dbVersion, 2);
      expect(_readMarker(dbPath), 'full-download');
      expect(refresh.called, isTrue);
      expect(File('$dbPath.applying').existsSync(), isFalse);
      expect(File('$dbPath.backup').existsSync(), isFalse);
      expect(File('$dbPath.new').existsSync(), isFalse);
      expect(
        File(
          p.join(tmp.path, 'library_update_cache', 'seforim.db.zst'),
        ).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'applyFullDownload: ביטול באמצע ההורדה משאיר ארכיון חלקי ו-sidecar ל-resume',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final bytes = Uint8List.fromList(
        List<int>.generate(4096, (i) => i % 251),
      );
      var cancelled = false;
      final downloader = PatchDownloader(
        httpClient: MockClient.streaming((request, bodyStream) async {
          // ETag חזק — בלעדיו חלקי אינו בר-חידוש ונמחק בכשל (כמו בייצור מול GitHub).
          return http.StreamedResponse(
            Stream.fromIterable([bytes.sublist(0, 1024), bytes.sublist(1024)]),
            200,
            contentLength: bytes.length,
            headers: {'etag': '"e-1"'},
          );
        }),
        decompress: (b) async => b,
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: downloader,
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-07-19T00:00:00Z',
        diskSpaceProvider: (_) async => DiskSpaceInfo.unknown,
        fullDbExtractor: (a, o) async =>
            fail('ביטול בהורדה — אסור להגיע לחילוץ'),
      );
      final plan = LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 2,
        asset: ReleaseAsset(
          name: DatabaseConstants.databaseArchiveFileName,
          downloadUrl: 'https://x/seforim.db.zst',
          size: bytes.length,
          id: 7,
          updatedAt: '2026-07-01T00:00:00Z',
        ),
        releaseTag: 'v2',
      );

      await expectLater(
        repository.applyFullDownload(
          plan,
          isCancelled: () => cancelled,
          onProgress: (progress) {
            if ((progress.bytesDownloaded ?? 0) > 0) cancelled = true;
          },
        ),
        throwsA(isA<PatchDownloadCancelled>()),
      );

      final archive = File(
        p.join(tmp.path, 'library_update_cache', 'seforim.db.zst'),
      );
      final sidecar = File(PatchDownloader.resumeSidecarPath(archive.path));
      expect(archive.existsSync(), isTrue);
      expect(archive.lengthSync(), lessThan(bytes.length));
      expect(
        sidecar.readAsStringSync(),
        startsWith('https://x/seforim.db.zst|4096|7|2026-07-01T00:00:00Z'),
      );
      expect(File('$dbPath.new').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'applyFullDownload: ביטול בזמן המתנה ל-operationQueue עוצר לפני החלפת DB',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final repository = _localFullDownloadRepository(
        tmp: tmp,
        dbPath: dbPath,
      );
      final plan = _localFullDownloadPlan();
      final blockerStarted = Completer<void>();
      final releaseBlocker = Completer<void>();
      final blocker = DatabaseLibraryProvider.operationQueue.enqueue(() async {
        blockerStarted.complete();
        await releaseBlocker.future;
      });
      await blockerStarted.future;

      var cancelled = false;
      var replacementReported = false;
      final update = repository.applyFullDownload(
        plan,
        isCancelled: () => cancelled,
        onDbReplaced: () => replacementReported = true,
      );
      await _waitUntil(
        () => DatabaseLibraryProvider.operationQueue.busyCount.value >= 2,
      );
      cancelled = true;
      releaseBlocker.complete();
      await blocker;

      await expectLater(update, throwsA(isA<PatchDownloadCancelled>()));
      expect(_readMarker(dbPath), 'old');
      expect(replacementReported, isFalse);
      expect(File('$dbPath.applying').existsSync(), isFalse);
      expect(File('$dbPath.backup').existsSync(), isFalse);
    },
  );

  test(
    'applyFullDownload: ביטול אחרי beginApply ולפני rename משחזר את ה-DB הישן',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final recovery = _GatedAfterBeginRecovery();
      final repository = _localFullDownloadRepository(
        tmp: tmp,
        dbPath: dbPath,
        recovery: recovery,
      );
      var cancelled = false;
      var replacementReported = false;
      final update = repository.applyFullDownload(
        _localFullDownloadPlan(),
        isCancelled: () => cancelled,
        onDbReplaced: () => replacementReported = true,
      );

      await recovery.beginCompleted.future;
      cancelled = true;
      recovery.releaseBegin.complete();

      await expectLater(update, throwsA(isA<PatchDownloadCancelled>()));
      expect(_readMarker(dbPath), 'old');
      expect(replacementReported, isFalse);
      expect(File('$dbPath.applying').existsSync(), isFalse);
      expect(File('$dbPath.backup').existsSync(), isFalse);
    },
  );

  test(
    'applyFullDownload: commit מדווח לפני refresh גם אם refresh נכשל',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final refresh = _ThrowingRefreshService();
      final repository = _localFullDownloadRepository(
        tmp: tmp,
        dbPath: dbPath,
        refreshService: refresh,
      );
      var replacementReported = false;

      await expectLater(
        repository.applyFullDownload(
          _localFullDownloadPlan(),
          onDbReplaced: () {
            replacementReported = true;
            expect(_readMarker(dbPath), 'new');
            expect(refresh.called, isFalse);
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(replacementReported, isTrue);
      expect(refresh.called, isTrue);
      expect(_readMarker(dbPath), 'new');
    },
  );

  test(
    'applyFullDownload: כשל חילוץ מוחק ארכיון ו-sidecar — מונע לולאת resume',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final bytes = Uint8List.fromList(List<int>.filled(2048, 7));
      final downloader = PatchDownloader(
        httpClient: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
          );
        }),
        decompress: (b) async => b,
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: downloader,
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-07-19T00:00:00Z',
        diskSpaceProvider: (_) async => DiskSpaceInfo.unknown,
        fullDbExtractor: (a, o) async => throw Exception('ארכיון פגום'),
      );
      final plan = LibraryUpdatePlan.fullDownload(
        localVersion: 1,
        targetVersion: 2,
        asset: ReleaseAsset(
          name: DatabaseConstants.databaseArchiveFileName,
          downloadUrl: 'https://x/seforim.db.zst',
          size: bytes.length,
        ),
        releaseTag: 'v2',
      );

      await expectLater(
        repository.applyFullDownload(plan),
        throwsA(isA<Exception>()),
      );

      final archive = File(
        p.join(tmp.path, 'library_update_cache', 'seforim.db.zst'),
      );
      expect(archive.existsSync(), isFalse);
      expect(
        File(PatchDownloader.resumeSidecarPath(archive.path)).existsSync(),
        isFalse,
      );
      expect(File('$dbPath.new').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  group('applyFullDownload: בדיקת מקום פנוי לפני ההורדה', () {
    const oneGb = 1 << 30;

    LibraryUpdateRepository repo(
      Future<DiskSpaceInfo> Function(String dirPath) diskSpaceProvider,
      String dbPath,
    ) {
      return LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: PatchDownloader(
          // כל הגעה לרשת מסומנת בחריגה ייחודית — הבדיקות מבחינות בינה לבין
          // כשל מקום פנוי.
          httpClient: MockClient.streaming(
            (request, bodyStream) async => throw Exception('download-started'),
          ),
          decompress: (b) async => b,
        ),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-08-19T00:00:00Z',
        diskSpaceProvider: diskSpaceProvider,
        fullDbExtractor: (a, o) async => fail('אסור להגיע לחילוץ'),
      );
    }

    LibraryUpdatePlan plan() => LibraryUpdatePlan.fullDownload(
      localVersion: 1,
      targetVersion: 2,
      asset: ReleaseAsset(
        name: DatabaseConstants.databaseArchiveFileName,
        downloadUrl: 'https://x/seforim.db.zst',
        size: oneGb,
      ),
      releaseTag: 'v2',
    );

    test('אותו volume בלי מספיק מקום — נכשל עם הודעה ברורה', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final repository = repo(
        (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: oneGb),
        dbPath,
      );

      await expectLater(
        repository.applyFullDownload(plan()),
        throwsA(
          isA<LibraryUpdateDiskSpaceException>().having(
            (e) => e.message,
            'message',
            contains('אין מספיק מקום פנוי'),
          ),
        ),
      );
    });

    test(
      'volumes נפרדים: כונן החילוץ מלא נתפס גם כשכונן ההורדה פנוי',
      () async {
        final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
        _writeDb(dbPath, version: 1, marker: 'old');
        final repository = repo(
          (dirPath) async => dirPath.contains('library_update_cache')
              ? const DiskSpaceInfo(volumeId: 'D:\\', freeBytes: 100 * oneGb)
              : const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: oneGb),
          dbPath,
        );

        await expectLater(
          repository.applyFullDownload(plan()),
          throwsA(
            isA<LibraryUpdateDiskSpaceException>().having(
              (e) => e.message,
              'message',
              contains('לחילוץ'),
            ),
          ),
        );
      },
    );

    test('מקום פנוי מספיק — הבדיקה עוברת וההורדה מתחילה', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final repository = repo(
        (_) async =>
            const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 100 * oneGb),
        dbPath,
      );

      // ההורדה עצמה נכשלת בכוונה (MockClient זורק fail) — מספיק לוודא
      // שהכשל אינו כשל מקום פנוי, כלומר הבדיקה לא חסמה.
      await expectLater(
        repository.applyFullDownload(plan()),
        throwsA(isNot(isA<LibraryUpdateDiskSpaceException>())),
      );
    });

    test('patch מחולץ ישן נמחק לפני בדיקת המקום', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
        ..createSync(recursive: true);
      final stale = File(p.join(cacheDir.path, 'patch-v9-v10.db'))
        ..writeAsBytesSync(List<int>.filled(2000, 0));
      final repository = repo(
        (_) async => DiskSpaceInfo(
          volumeId: 'C:\\',
          freeBytes: stale.existsSync() ? oneGb : 100 * oneGb,
        ),
        dbPath,
      );

      await expectLater(
        repository.applyFullDownload(plan()),
        throwsA(isNot(isA<LibraryUpdateDiskSpaceException>())),
      );
      expect(stale.existsSync(), isFalse);
    });
  });

  group('applyDeltaPlan: בדיקת מקום פנוי לפני הורדת הצעד', () {
    const oneGb = 1 << 30;

    LibraryUpdateRepository repo(
      Future<DiskSpaceInfo> Function(String dirPath) diskSpaceProvider,
      String dbPath, {
      PatchDownloader? downloader,
    }) {
      return LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader:
            downloader ??
            PatchDownloader(
              httpClient: MockClient.streaming(
                (request, bodyStream) async =>
                    throw Exception('download-started'),
              ),
              decompress: (b) async => b,
            ),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-07T00:00:00Z',
        diskSpaceProvider: diskSpaceProvider,
      );
    }

    test('אותו volume בלי מקום לדחוס+מחולץ+WAL — נכשל לפני ההורדה', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final repository = repo(
        (_) async =>
            const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 2 * oneGb),
        dbPath,
      );

      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: oneGb, uncompressedSize: 2 * oneGb),
        ),
        throwsA(
          isA<LibraryUpdateDiskSpaceException>().having(
            (e) => e.message,
            'message',
            contains('אין מספיק מקום פנוי'),
          ),
        ),
      );
    });

    test('volumes נפרדים: אין מקום ל-WAL ליד ה-DB', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final repository = repo(
        (dirPath) async => dirPath.contains('library_update_cache')
            ? const DiskSpaceInfo(volumeId: 'D:\\', freeBytes: 100 * oneGb)
            : const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: oneGb),
        dbPath,
      );

      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: oneGb, uncompressedSize: 2 * oneGb),
        ),
        throwsA(
          isA<LibraryUpdateDiskSpaceException>().having(
            (e) => e.message,
            'message',
            contains('להחלת'),
          ),
        ),
      );
    });

    test('patch מחולץ קיים אינו נספר כמקום שיידרש להורדה', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
        ..createSync(recursive: true);
      final contents = List<int>.filled(2000, 0);
      File(p.join(cacheDir.path, 'patch.db')).writeAsBytesSync(contents);
      final repository = repo(
        (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 2500),
        dbPath,
        downloader: StreamingPatchDownloader(
          httpClient: MockClient.streaming(
            (request, bodyStream) async => throw Exception('אסור להוריד'),
          ),
          extractor: (archive, output) async => fail('אסור לחלץ'),
        ),
      );

      // בלי השימוש החוזר היו נדרשים 5000 בייטים ובדיקת המקום הייתה חוסמת.
      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(
            size: 1000,
            uncompressedSize: 2000,
            uncompressedSha256: sha256.convert(contents).toString(),
          ),
        ),
        throwsA(isNot(isA<LibraryUpdateDiskSpaceException>())),
      );
    });

    test(
      'patch מחולץ בגודל נכון אך hash שגוי אינו עוקף את בדיקת המקום',
      () async {
        final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
        _writeDb(dbPath, version: 1, marker: 'old');
        final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
          ..createSync(recursive: true);
        final extracted = File(p.join(cacheDir.path, 'patch.db'))
          ..writeAsBytesSync(List<int>.filled(2000, 0));
        final repository = repo(
          (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 2500),
          dbPath,
          downloader: StreamingPatchDownloader(
            httpClient: MockClient.streaming(
              (request, bodyStream) async => throw Exception('אסור להוריד'),
            ),
          ),
        );

        await expectLater(
          repository.applyDeltaPlan(
            _deltaPlan(
              size: 1000,
              uncompressedSize: 2000,
              uncompressedSha256: sha256
                  .convert(List<int>.filled(2000, 1))
                  .toString(),
            ),
          ),
          throwsA(isA<LibraryUpdateDiskSpaceException>()),
        );
        expect(extracted.existsSync(), isFalse);
      },
    );

    test('partial דחוס בלי sidecar אינו מנוכה מדרישת המקום', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
        ..createSync(recursive: true);
      File(p.join(cacheDir.path, 'patch.db.zst')).writeAsBytesSync(
        List<int>.filled(400, 0),
      );
      final repository = repo(
        (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 4800),
        dbPath,
      );

      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: 1000, uncompressedSize: 2000),
        ),
        throwsA(isA<LibraryUpdateDiskSpaceException>()),
      );
    });

    test(
      'partial דחוס עם sidecar מטוקן שגוי אינו מנוכה מדרישת המקום',
      () async {
        final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
        _writeDb(dbPath, version: 1, marker: 'old');
        final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
          ..createSync(recursive: true);
        final partial = File(p.join(cacheDir.path, 'patch.db.zst'))
          ..writeAsBytesSync(List<int>.filled(400, 0));
        File(PatchDownloader.resumeSidecarPath(partial.path)).writeAsStringSync(
          'wrong-token\n"etag-v1"',
        );
        final repository = repo(
          (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 4800),
          dbPath,
        );

        await expectLater(
          repository.applyDeltaPlan(
            _deltaPlan(size: 1000, uncompressedSize: 2000),
          ),
          throwsA(isA<LibraryUpdateDiskSpaceException>()),
        );
      },
    );

    test('partial דחוס בלי ETag חזק אינו מנוכה מדרישת המקום', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
        ..createSync(recursive: true);
      final partial = File(p.join(cacheDir.path, 'patch.db.zst'))
        ..writeAsBytesSync(List<int>.filled(400, 0));
      File(PatchDownloader.resumeSidecarPath(partial.path)).writeAsStringSync(
        'aa\nW/"weak-etag"',
      );
      final repository = repo(
        (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 4800),
        dbPath,
      );

      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: 1000, uncompressedSize: 2000),
        ),
        throwsA(isA<LibraryUpdateDiskSpaceException>()),
      );
    });

    test('partial דחוס עם token ו-ETag חזקים מנוכה מדרישת המקום', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
        ..createSync(recursive: true);
      final partial = File(p.join(cacheDir.path, 'patch.db.zst'))
        ..writeAsBytesSync(List<int>.filled(400, 0));
      File(PatchDownloader.resumeSidecarPath(partial.path)).writeAsStringSync(
        'aa\n"etag-v1"',
      );
      final repository = repo(
        (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 4800),
        dbPath,
      );

      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: 1000, uncompressedSize: 2000),
        ),
        throwsA(isNot(isA<LibraryUpdateDiskSpaceException>())),
      );
    });

    test('patch של תוכנית אחרת נמחק גם כשהריצה נעצרת על חוסר מקום', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final cacheDir = Directory(p.join(tmp.path, 'library_update_cache'))
        ..createSync(recursive: true);
      final stale = File(p.join(cacheDir.path, 'patch-v9-v10.db'))
        ..writeAsBytesSync(List<int>.filled(2000, 0));
      final repository = repo(
        (_) async => const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 10),
        dbPath,
      );

      // בלי הניקוי המוקדם, השריד היה תופס את המקום שחסר וחוסם כל ניסיון הבא.
      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: 1000, uncompressedSize: 2000),
        ),
        throwsA(isA<LibraryUpdateDiskSpaceException>()),
      );
      expect(stale.existsSync(), isFalse);
    });

    test('מקום פנוי מספיק — הבדיקה עוברת וההורדה מתחילה', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      final repository = repo(
        (_) async =>
            const DiskSpaceInfo(volumeId: 'C:\\', freeBytes: 100 * oneGb),
        dbPath,
      );

      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(size: oneGb, uncompressedSize: 2 * oneGb),
        ),
        throwsA(isNot(isA<LibraryUpdateDiskSpaceException>())),
      );
    });
  });

  test(
    'applyDeltaPlan: ה-apply ב-isolate אינו לוכד את ה-downloader הלא-sendable',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');

      // downloader עם http.Client אמיתי (IOClient — לא-sendable, כמו בייצור),
      // אך מחזיר patch מקומי בלי רשת.
      final downloader = _LocalPatchDownloader(p.join(tmp.path, 'patch.db'));
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: downloader,
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-06-28T00:00:00Z',
      );

      // onProgress שלוכד Completer לא-sendable — מדמה את ה-bloc האמיתי, שלוכד
      // _Emitter/_AsyncCompleter ב-onProgress. שני מקורות לא-sendable נבדקים
      // יחד: ה-repository (HttpClient) וה-onProgress (Completer).
      final emitterLike = Completer<void>();

      // רגרסיה: לפני התיקון ה-spawn נכשל ב-ArgumentError "object is unsendable"
      // (ה-closure לכד את ה-repository או את onStage→onProgress). אחרי התיקון
      // ה-apply רץ ב-isolate ונכשל על ה-patch הריק → PatchApplyException.
      await expectLater(
        repository.applyDeltaPlan(
          _deltaPlan(),
          onProgress: (_) => emitterLike.future.ignore(),
        ),
        throwsA(isA<PatchApplyException>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('applyDeltaPlan מעביר התקדמות אימות מה-downloader', () async {
    final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
    _writeDb(dbPath, version: 1, marker: 'old');
    final repository = LibraryUpdateRepository(
      discovery: _unusedDiscovery(),
      downloader: _LocalPatchDownloader(
        p.join(tmp.path, 'patch.db'),
        verifyProgress: (64, 128),
      ),
      refreshService: _NoopRefreshService(),
      dbPathProvider: () => dbPath,
      dataRootProvider: () async => tmp.path,
      nowTimestamp: () => '2026-09-08T00:00:00Z',
    );
    final reports = <LibraryUpdateProgress>[];

    await expectLater(
      repository.applyDeltaPlan(_deltaPlan(), onProgress: reports.add),
      throwsA(isA<PatchApplyException>()),
    );

    expect(
      reports,
      contains(
        isA<LibraryUpdateProgress>()
            .having((p) => p.phase, 'phase', LibraryUpdatePhase.verifying)
            .having((p) => p.stepIndex, 'stepIndex', 0)
            .having((p) => p.totalSteps, 'totalSteps', 1)
            .having((p) => p.applyProgress, 'applyProgress', 0.5),
      ),
    );
  });

  test(
    'applyDeltaPlan מחזיר את היומן ל-DELETE גם כשה-apply נכשל',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');

      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _LocalPatchDownloader(p.join(tmp.path, 'patch.db')),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-06-28T00:00:00Z',
      );

      await expectLater(
        repository.applyDeltaPlan(_deltaPlan()),
        throwsA(isA<PatchApplyException>()),
      );

      // יומן WAL שנשאר היה שובר פתיחת RO על מדיה לקריאה-בלבד.
      expect(_journalMode(dbPath), 'delete');
      expect(File('$dbPath-wal').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'נסיגה מ-WAL לסגירת חיבור ה-RO נרשמת ל-errors.txt',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');
      AppPaths.debugOverrideDataRootPath(tmp.path);
      // קובץ לקריאה-בלבד: SQLite פותח אותו RO בשקט וההמרה ל-WAL לא תופסת.
      await _setReadOnly(dbPath, true);

      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _LocalPatchDownloader(p.join(tmp.path, 'patch.db')),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-07T00:00:00Z',
      );

      try {
        await expectLater(
          repository.applyDeltaPlan(_deltaPlan()),
          throwsA(anything),
        );
        final log = ErrorLogFile.resolveFile().readAsStringSync();
        expect(log, contains('journal_mode=WAL failed'));
        expect(log, contains('readonly database'));
      } finally {
        await _setReadOnly(dbPath, false);
        AppPaths.debugOverrideDataRootPath(null);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'applyDeltaPlan מסמן reconcile מלא כשמשתנה תוכן שאינו ניתן למיפוי לספר',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      // שריד מריצה קודמת שנקטעה — חייב להתנקות בסיום תוכנית מוצלחת.
      final stale = File(
        p.join(tmp.path, 'library_update_cache', 'patch-v9-v10.db'),
      )..createSync(recursive: true);
      final refresh = _NoopRefreshService();
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
        refreshService: refresh,
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-01T00:00:00Z',
      );

      final result = await repository.applyDeltaPlan(
        _schema4DeltaPlan([
          _schema4Edge(
            fromVersion: 1,
            toVersion: 2,
            patchName: 'patch-1-2.db',
            toHash: _logicalHash(expectedPath),
          ),
        ]),
      );

      expect(result.appliedSteps, 1);
      expect(result.changedBookIds, isEmpty);
      expect(result.requiresFullIndexRefresh, isTrue);
      expect(refresh.called, isTrue);
      expect(const LocalDbVersionReader().read(dbPath).dbVersion, 2);
      expect(stale.existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a read worker that does not release after a committed WAL patch does not fail the update',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-28T00:00:00Z',
      );
      // ה-dispose שב-setUp חוסם את ה-worker עד אתחול; כאן רק מעירים אותו.
      DbReadWorker.allowReopen();
      await DbReadWorker.request('open', const {});
      DbReadWorker.lifecycleCommandTimeout = Duration.zero;
      try {
        final result = await repository.applyDeltaPlan(
          _schema4DeltaPlan([
            _schema4Edge(
              fromVersion: 1,
              toVersion: 2,
              patchName: 'patch-1-2.db',
              toHash: _logicalHash(expectedPath),
            ),
          ]),
        );

        expect(result.appliedSteps, 1);
        expect(const LocalDbVersionReader().read(dbPath).dbVersion, 2);
        expect(_journalMode(dbPath), 'delete');
      } finally {
        DbReadWorker.lifecycleCommandTimeout = const Duration(seconds: 4);
        await DbReadWorker.resumeAfterExternalWrite();
        DbReadWorker.disposeForTesting();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'applyDeltaPlan מדווח התקדמות שורות בשלב ה-upserts',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-01T00:00:00Z',
      );

      final progress = <LibraryUpdateProgress>[];
      await repository.applyDeltaPlan(
        _schema4DeltaPlan([
          _schema4Edge(
            fromVersion: 1,
            toVersion: 2,
            patchName: 'patch-1-2.db',
            toHash: _logicalHash(expectedPath),
          ),
        ]),
        onProgress: progress.add,
      );

      final rowProgress = progress
          .where(
            (e) =>
                e.phase == LibraryUpdatePhase.applying &&
                e.stage == 'upserts' &&
                e.applyProgress != null,
          )
          .toList();
      expect(
        rowProgress,
        isNotEmpty,
        reason: 'בלי מד שורות המשתמש רואה ספינר בלתי-מוגדר לאורך כל ההחלה',
      );
      expect(rowProgress.every((e) => e.applyProgress! >= 0), isTrue);
      expect(rowProgress.last.applyProgress, lessThanOrEqualTo(1.0));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('checkForUpdate מעביר ל-planner את גודל ה-DB המקומי', () async {
    final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
    _writeDb(dbPath, version: 1, marker: 'old');
    final planner = _RecordingPlanner();
    final repository = LibraryUpdateRepository(
      discovery: _unusedDiscovery(),
      planner: planner,
      downloader: _PatchMapDownloader(const {}),
      refreshService: _NoopRefreshService(),
      dbPathProvider: () => dbPath,
      dataRootProvider: () async => tmp.path,
      nowTimestamp: () => '2026-09-01T00:00:00Z',
    );

    await repository.checkForUpdate(allowPrerelease: false);

    expect(planner.seenLocalDbSizeBytes, File(dbPath).lengthSync());
  });

  test('checkForUpdate קורא את הגרסה המקומית מחוץ ל-UI isolate', () async {
    final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
    _writeDb(dbPath, version: 1, marker: 'old');
    final planner = _RecordingPlanner();
    final repository = LibraryUpdateRepository(
      discovery: _unusedDiscovery(),
      planner: planner,
      versionReader: _IsolateRecordingReader(Isolate.current.debugName),
      downloader: _PatchMapDownloader(const {}),
      dbPathProvider: () => dbPath,
      dataRootProvider: () async => tmp.path,
    );

    await repository.checkForUpdate(allowPrerelease: false);

    expect(planner.seenLocalVersion, _IsolateRecordingReader.otherIsolate);
  });

  test('release בסכמה חדשה ללא דלתא דורש עדכון אפליקציה', () async {
    final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
    _writeDb(dbPath, version: 1, marker: 'old');
    final repository = LibraryUpdateRepository(
      discovery: LibraryUpdateDiscovery(
        supportedDbSchemaVersion: DatabaseConstants.readableDbSchemaVersion,
        client: GithubLibraryReleaseClient(
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode([
                {
                  'tag_name': 'v2',
                  'draft': false,
                  'prerelease': false,
                  'assets': [
                    {
                      'name': 'seforim-schema7.db.zst',
                      'browser_download_url': 'https://example.com/schema7',
                      'size': 100,
                    },
                  ],
                },
              ]),
              200,
            ),
          ),
        ),
      ),
      downloader: _PatchMapDownloader(const {}),
      dbPathProvider: () => dbPath,
    );

    final plan = await repository.checkForUpdate(allowPrerelease: false);
    expect(plan.kind, LibraryUpdatePlanKind.blocked);
    expect(plan.targetVersion, 2);
    expect(plan.reason, contains('נדרש עדכון אפליקציה'));
    expect(plan.reason, contains('DB 7'));
    expect(plan.fullDbAsset, isNull);
  });

  test(
    'כשל בצעד דלתא מאוחר מדווח את הצעדים שכבר נכתבו ומרענן runtime',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final firstPatch = p.join(tmp.path, 'patch-1-2.db');
      final invalidPatch = p.join(tmp.path, 'patch-2-3.db');
      _writeSourcePatch(
        firstPatch,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      _writeSourcePatch(
        invalidPatch,
        fromVersion: 2,
        toVersion: 3,
        sourceName: 'newer',
        patchFormatVersion: 99,
      );
      final refresh = _NoopRefreshService();
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({
          'patch-1-2.db': firstPatch,
          'patch-2-3.db': invalidPatch,
        }),
        refreshService: refresh,
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-01T00:00:00Z',
      );
      final plan = _schema4DeltaPlan([
        _schema4Edge(
          fromVersion: 1,
          toVersion: 2,
          patchName: 'patch-1-2.db',
          toHash: _logicalHash(expectedPath),
        ),
        _schema4Edge(
          fromVersion: 2,
          toVersion: 3,
          patchName: 'patch-2-3.db',
          toHash: 'unused',
        ),
      ]);

      await expectLater(
        repository.applyDeltaPlan(plan),
        throwsA(
          isA<PartiallyAppliedLibraryDeltaException>()
              .having(
                (e) => e.cause,
                'cause',
                isA<PatchApplyException>(),
              )
              .having(
                (e) => e.appliedResult.appliedSteps,
                'appliedSteps',
                1,
              )
              .having(
                (e) => e.appliedResult.requiresFullIndexRefresh,
                'requiresFullIndexRefresh',
                isTrue,
              ),
        ),
      );

      expect(refresh.called, isTrue);
      expect(const LocalDbVersionReader().read(dbPath).dbVersion, 2);
      expect(_readSourceName(dbPath), 'new');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  group('applierProvider', () {
    LibraryUpdateRepository buildRepository(
      String dbPath,
      String patchPath,
      Future<PatchApplier> Function() applierProvider, {
      Future<void> Function()? sqliteTempDirectoryInitializer,
    }) => LibraryUpdateRepository(
      discovery: _unusedDiscovery(),
      downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
      refreshService: _NoopRefreshService(),
      dbPathProvider: () => dbPath,
      dataRootProvider: () async => tmp.path,
      nowTimestamp: () => '2026-09-29T00:00:00Z',
      applierProvider: applierProvider,
      sqliteTempDirectoryInitializer: sqliteTempDirectoryInitializer,
    );

    LibraryUpdatePlan onePatchPlan(String expectedPath) => _schema4DeltaPlan([
      _schema4Edge(
        fromVersion: 1,
        toVersion: 2,
        patchName: 'patch-1-2.db',
        toHash: _logicalHash(expectedPath),
      ),
    ]);

    test('ה-applier שהוזרק הוא זה שרץ ב-isolate של ה-apply', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      var calls = 0;
      // ה-patch בפורמט 4; applier שתומך רק עד 3 נכשל רק אם הוא זה שהופעל.
      final repository = buildRepository(dbPath, patchPath, () async {
        calls++;
        return const PatchApplier(supportedPatchFormatVersion: 3);
      });

      await expectLater(
        repository.applyDeltaPlan(onePatchPlan(expectedPath)),
        throwsA(isA<PatchApplyException>()),
      );

      expect(calls, 1);
      expect(const LocalDbVersionReader().read(dbPath).dbVersion, 1);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('cache מוקטן של mobile עובר ל-isolate וה-apply מצליח', () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      var setupCalls = 0;
      final repository = buildRepository(
        dbPath,
        patchPath,
        () async => LibraryUpdateSqliteSetup.applierForPhysicalRam(2048),
        sqliteTempDirectoryInitializer: () async {
          setupCalls++;
        },
      );

      await repository.applyDeltaPlan(onePatchPlan(expectedPath));

      expect(const LocalDbVersionReader().read(dbPath).dbVersion, 2);
      expect(_readSourceName(dbPath), 'new');
      expect(setupCalls, 1);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  test(
    'מניפסט עם hash לכל טבלה: אימות חלקי, שלב verifyDeferred, בלי סטייה',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-07T00:00:00Z',
      );
      final stages = <String>[];

      final result = await repository.applyDeltaPlan(
        _schema4DeltaPlan([
          _schema4Edge(
            fromVersion: 1,
            toVersion: 2,
            patchName: 'patch-1-2.db',
            toHash: _logicalHash(expectedPath),
            fromTableHashes: _tableHashes(dbPath),
            toTableHashes: _tableHashes(expectedPath),
          ),
        ]),
        onProgress: (progress) {
          final stage = progress.stage;
          if (stage != null) stages.add(stage);
        },
      );

      expect(result.appliedSteps, 1);
      expect(stages, contains('verifyDeferred'));
      expect(_readSourceName(dbPath), 'new');
      // רמז הבתים לכל טבלה נשמר לריצה הבאה.
      final hintFile = File(
        p.join(tmp.path, 'library_update_cache', 'verify_table_bytes.json'),
      );
      expect(hintFile.existsSync(), isTrue);
      expect(
        (jsonDecode(hintFile.readAsStringSync()) as Map).keys,
        contains('source'),
      );
      expect(
        File(
          p.join(tmp.path, 'library_update_cache', 'verify_total_bytes.txt'),
        ).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'סטייה בטבלה שאף צעד לא נגע בה מדווחת אחרי ה-commit ונרשמת ל-errors.txt',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      final pristinePath = p.join(tmp.path, 'pristine.db');
      final expectedPath = p.join(tmp.path, 'expected.db');
      // ה-manifest נבנה מ-DB תקין; המקומי זהה לו פרט ל-author שסטה.
      _writeSchema4SourceDb(
        pristinePath,
        version: 1,
        sourceName: 'old',
        authorName: 'תקין',
      );
      _writeSchema4SourceDb(
        expectedPath,
        version: 2,
        sourceName: 'new',
        authorName: 'תקין',
      );
      _writeSchema4SourceDb(
        dbPath,
        version: 1,
        sourceName: 'old',
        authorName: 'סוטה',
      );
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      AppPaths.debugOverrideDataRootPath(tmp.path);
      final refresh = _NoopRefreshService();
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
        refreshService: refresh,
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-07T00:00:00Z',
      );

      try {
        await expectLater(
          repository.applyDeltaPlan(
            _schema4DeltaPlan([
              _schema4Edge(
                fromVersion: 1,
                toVersion: 2,
                patchName: 'patch-1-2.db',
                toHash: _logicalHash(expectedPath),
                fromTableHashes: _tableHashes(pristinePath),
                toTableHashes: _tableHashes(expectedPath),
              ),
            ]),
          ),
          throwsA(
            isA<LibraryDeltaContentDriftException>()
                .having(
                  (e) => e.driftedTables,
                  'driftedTables',
                  contains('author'),
                )
                .having((e) => e.appliedResult.appliedSteps, 'appliedSteps', 1),
          ),
        );

        // העדכון עצמו הוחל ורוענן — הסטייה אינה rollback.
        expect(_readSourceName(dbPath), 'new');
        expect(refresh.called, isTrue);
        expect(
          ErrorLogFile.resolveFile().readAsStringSync(),
          contains('Library Update: content drift in untouched tables'),
        );
      } finally {
        AppPaths.debugOverrideDataRootPath(null);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'שרשרת שבה צעד אחד בלי hash לכל טבלה: אין שלב verifyDeferred',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expected2 = p.join(tmp.path, 'expected2.db');
      _writeSchema4SourceDb(expected2, version: 2, sourceName: 'new');
      final expected3 = p.join(tmp.path, 'expected3.db');
      _writeSchema4SourceDb(expected3, version: 3, sourceName: 'newer');
      final firstPatch = p.join(tmp.path, 'patch-1-2.db');
      final secondPatch = p.join(tmp.path, 'patch-2-3.db');
      _writeSourcePatch(
        firstPatch,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      _writeSourcePatch(
        secondPatch,
        fromVersion: 2,
        toVersion: 3,
        sourceName: 'newer',
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({
          'patch-1-2.db': firstPatch,
          'patch-2-3.db': secondPatch,
        }),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-07T00:00:00Z',
      );
      final stages = <String>[];

      final result = await repository.applyDeltaPlan(
        _schema4DeltaPlan([
          _schema4Edge(
            fromVersion: 1,
            toVersion: 2,
            patchName: 'patch-1-2.db',
            toHash: _logicalHash(expected2),
            fromTableHashes: _tableHashes(dbPath),
            toTableHashes: _tableHashes(expected2),
          ),
          _schema4Edge(
            fromVersion: 2,
            toVersion: 3,
            patchName: 'patch-2-3.db',
            toHash: _logicalHash(expected3),
          ),
        ]),
        onProgress: (progress) {
          final stage = progress.stage;
          if (stage != null) stages.add(stage);
        },
      );

      // הצעד הישן אימת את כל ה-DB, ולכן אין טבלה שנותרה לא-מאומתת.
      expect(result.appliedSteps, 2);
      expect(_readSourceName(dbPath), 'newer');
      expect(stages, isNot(contains('verifyDeferred')));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'כשל בצעד מאוחר עדיין מדווח סטייה בטבלה שנדחתה בצעד שהושלם',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      final pristinePath = p.join(tmp.path, 'pristine.db');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(
        pristinePath,
        version: 1,
        sourceName: 'old',
        authorName: 'תקין',
      );
      _writeSchema4SourceDb(
        expectedPath,
        version: 2,
        sourceName: 'new',
        authorName: 'תקין',
      );
      _writeSchema4SourceDb(
        dbPath,
        version: 1,
        sourceName: 'old',
        authorName: 'סוטה',
      );
      final firstPatch = p.join(tmp.path, 'patch-1-2.db');
      final invalidPatch = p.join(tmp.path, 'patch-2-3.db');
      _writeSourcePatch(
        firstPatch,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      _writeSourcePatch(
        invalidPatch,
        fromVersion: 2,
        toVersion: 3,
        sourceName: 'newer',
        patchFormatVersion: 99,
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({
          'patch-1-2.db': firstPatch,
          'patch-2-3.db': invalidPatch,
        }),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-08T00:00:00Z',
      );

      await expectLater(
        repository.applyDeltaPlan(
          _schema4DeltaPlan([
            _schema4Edge(
              fromVersion: 1,
              toVersion: 2,
              patchName: 'patch-1-2.db',
              toHash: _logicalHash(expectedPath),
              fromTableHashes: _tableHashes(pristinePath),
              toTableHashes: _tableHashes(expectedPath),
            ),
            _schema4Edge(
              fromVersion: 2,
              toVersion: 3,
              patchName: 'patch-2-3.db',
              toHash: 'unused',
            ),
          ]),
        ),
        throwsA(
          isA<LibraryDeltaContentDriftException>()
              .having(
                (e) => e.driftedTables,
                'driftedTables',
                contains('author'),
              )
              .having((e) => e.appliedResult.appliedSteps, 'appliedSteps', 1),
        ),
      );
      expect(const LocalDbVersionReader().read(dbPath).dbVersion, 2);
      expect(_readSourceName(dbPath), 'new');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'מניפסט בלי hash לכל טבלה: אימות DB מלא, בלי שלב verifyDeferred',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeSchema4SourceDb(dbPath, version: 1, sourceName: 'old');
      final expectedPath = p.join(tmp.path, 'expected.db');
      _writeSchema4SourceDb(expectedPath, version: 2, sourceName: 'new');
      final patchPath = p.join(tmp.path, 'patch-1-2.db');
      _writeSourcePatch(
        patchPath,
        fromVersion: 1,
        toVersion: 2,
        sourceName: 'new',
      );
      final repository = LibraryUpdateRepository(
        discovery: _unusedDiscovery(),
        downloader: _PatchMapDownloader({'patch-1-2.db': patchPath}),
        refreshService: _NoopRefreshService(),
        dbPathProvider: () => dbPath,
        dataRootProvider: () async => tmp.path,
        nowTimestamp: () => '2026-09-07T00:00:00Z',
      );
      final stages = <String>[];

      final result = await repository.applyDeltaPlan(
        _schema4DeltaPlan([
          _schema4Edge(
            fromVersion: 1,
            toVersion: 2,
            patchName: 'patch-1-2.db',
            toHash: _logicalHash(expectedPath),
          ),
        ]),
        onProgress: (progress) {
          final stage = progress.stage;
          if (stage != null) stages.add(stage);
        },
      );

      expect(result.appliedSteps, 1);
      expect(stages, contains('verifyToHash'));
      expect(stages, isNot(contains('verifyDeferred')));
      expect(
        File(
          p.join(tmp.path, 'library_update_cache', 'verify_table_bytes.json'),
        ).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'קורא RO ממשיך לקרוא בזמן כתיבת WAL (הנחת היסוד של עדכון ללא חסימה)',
    () async {
      final dbPath = p.join(tmp.path, DatabaseConstants.databaseFileName);
      _writeDb(dbPath, version: 1, marker: 'old');

      // קורא שנפתח לפני ההמרה ל-WAL — כמו חיבור ה-RO של האפליקציה.
      final reader = sqlite3.sqlite3.open(
        dbPath,
        mode: sqlite3.OpenMode.readOnly,
      );
      final writer = sqlite3.sqlite3.open(dbPath);
      try {
        writer.execute('PRAGMA journal_mode=WAL');
        writer.execute('BEGIN');
        writer.execute("UPDATE marker SET value = 'new' WHERE id = 1");

        // באמצע ה-transaction: הקורא רואה את ה-snapshot הישן, בלי חסימה.
        final during = reader.select('SELECT value FROM marker WHERE id = 1');
        expect(during.first['value'], 'old');

        writer.execute('COMMIT');
        final after = reader.select('SELECT value FROM marker WHERE id = 1');
        expect(after.first['value'], 'new');
      } finally {
        reader.close();
        writer.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _setReadOnly(String path, bool readOnly) async {
  final result = Platform.isWindows
      ? await Process.run('attrib', [readOnly ? '+R' : '-R', path])
      : await Process.run('chmod', [readOnly ? '444' : '644', path]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}

String _journalMode(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    return db
        .select('PRAGMA journal_mode')
        .first
        .values
        .first
        .toString()
        .toLowerCase();
  } finally {
    db.close();
  }
}

/// לוכד את גודל ה-DB המקומי שהריפוזיטורי מעביר ל-planner.
class _RecordingPlanner extends LibraryUpdatePlanner {
  int? seenLocalDbSizeBytes;
  int? seenLocalVersion;

  @override
  LibraryUpdatePlan plan({
    required int localVersion,
    required int? localSchemaVersion,
    required bool hasLocalVersionMeta,
    required int latestVersion,
    int? latestDbSchemaVersion,
    required List<PatchEdge> edges,
    ReleaseAsset? latestFullDbAsset,
    String? latestReleaseTag,
    int? localDbSizeBytes,
  }) {
    seenLocalDbSizeBytes = localDbSizeBytes;
    seenLocalVersion = localVersion;
    return super.plan(
      localVersion: localVersion,
      localSchemaVersion: localSchemaVersion,
      hasLocalVersionMeta: hasLocalVersionMeta,
      latestVersion: latestVersion,
      latestDbSchemaVersion: latestDbSchemaVersion,
      edges: edges,
      latestFullDbAsset: latestFullDbAsset,
      latestReleaseTag: latestReleaseTag,
      localDbSizeBytes: localDbSizeBytes,
    );
  }
}

/// מחזיר גרסה שמקודדת את ה-isolate שבו רץ. sendable (שדה מחרוזת בלבד).
class _IsolateRecordingReader extends LocalDbVersionReader {
  const _IsolateRecordingReader(this.callerName);

  static const int callingIsolate = 1;
  static const int otherIsolate = 2;

  final String? callerName;

  @override
  LocalDbVersion read(String dbPath) => LocalDbVersion(
    dbVersion: Isolate.current.debugName == callerName
        ? callingIsolate
        : otherIsolate,
    schemaVersion: 6,
    hasVersionMeta: true,
  );
}

LibraryUpdateDiscovery _unusedDiscovery() {
  return LibraryUpdateDiscovery(
    client: GithubLibraryReleaseClient(
      httpClient: MockClient((request) async => http.Response('[]', 200)),
    ),
  );
}

DynamicLibrary? _tryOpenSystemLibzstd() {
  const candidates = [
    '/opt/homebrew/lib/libzstd.dylib',
    '/usr/local/lib/libzstd.dylib',
    '/usr/lib/libzstd.dylib',
    'libzstd.so.1',
    'libzstd.so',
    '/usr/lib/x86_64-linux-gnu/libzstd.so.1',
    '/lib/x86_64-linux-gnu/libzstd.so.1',
  ];
  for (final path in candidates) {
    try {
      return DynamicLibrary.open(path);
    } catch (_) {}
  }
  return null;
}

Uint8List _fixtureFullDbArchive() {
  return base64Decode(
    'KLUv/WQAP2UKAMLPOzdQjdIBCMuZpGfaNpmZmeZmQTSK9rsjSWP7ZTsye9njicgi8cxGjCbp'
    '38MUW8v3/WuJhPiY7L1TG/VsacPbEKw9jQouIWXFXzEUwMgrwo2s/CdhFV81oICRkIBT8j'
    'jTV1GijTcyVlI8wk9x/H8F/JccTfPuiWr1clbDxFG3EneY8VgmkaGjkjQd6a2dRruagWG'
    'SHzCTsQDAC4PMYmZdT5ai+iA0IzqEdSQ8GKixCTGzCU9vnKZ7fhw6Wc+sM7EH66ukj3bV'
    'iuj1gJeLZSJBzCFM+czyJXyJgCTcgtH6391wCE/5Ql/afd6o6+U+FBUBISCAgpkklpEH'
    '9QHmA4D1GgBhgACAdQFsNsrHlwFQ4JRBa1MBSJjSKugz9wT4mQZHfIiMgYAjdi3fZw0D'
    '4zDfpq2vfjLU2BCPLng7FIPR0FEGnri5sxLLWXACmkf2Jw==',
  );
}

void _writeDb(String dbPath, {required int version, required String marker}) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute(
      "INSERT INTO schema_meta VALUES ('db_version', ?), "
      "('db_schema_version', '1')",
      [version.toString()],
    );
    db.execute('CREATE TABLE marker (id INTEGER PRIMARY KEY, value TEXT)');
    db.execute('INSERT INTO marker VALUES (1, ?)', [marker]);
    db.execute('PRAGMA journal_mode=DELETE');
  } finally {
    db.close();
  }
}

String? _readMarker(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    final rows = db.select('SELECT value FROM marker WHERE id = 1');
    return rows.isEmpty ? null : rows.first['value'] as String?;
  } finally {
    db.close();
  }
}

LibraryUpdatePlan _localFullDownloadPlan() => LibraryUpdatePlan.fullDownload(
  localVersion: 1,
  targetVersion: 2,
  asset: const ReleaseAsset(
    name: DatabaseConstants.databaseArchiveFileName,
    downloadUrl: 'https://x/seforim.db.zst',
    size: 1,
  ),
  releaseTag: 'v2',
);

LibraryUpdateRepository _localFullDownloadRepository({
  required Directory tmp,
  required String dbPath,
  LibraryDbRecoveryService recovery = const LibraryDbRecoveryService(),
  LibraryRuntimeRefreshService refreshService =
      const LibraryRuntimeRefreshService(),
}) => LibraryUpdateRepository(
  discovery: _unusedDiscovery(),
  downloader: PatchDownloader(
    httpClient: MockClient.streaming(
      (request, bodyStream) async => http.StreamedResponse(
        Stream.value(const [1]),
        200,
        contentLength: 1,
      ),
    ),
    decompress: (bytes) async => bytes,
  ),
  recovery: recovery,
  refreshService: refreshService,
  dbPathProvider: () => dbPath,
  dataRootProvider: () async => tmp.path,
  nowTimestamp: () => '2026-09-01T00:00:00Z',
  diskSpaceProvider: (_) async => DiskSpaceInfo.unknown,
  fullDbExtractor: (archivePath, outputPath) async {
    _writeDb(outputPath, version: 2, marker: 'new');
  },
);

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timeout while waiting for asynchronous condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _GatedAfterBeginRecovery extends LibraryDbRecoveryService {
  final beginCompleted = Completer<void>();
  final releaseBegin = Completer<void>();

  @override
  Future<void> beginApply({
    required String dbPath,
    required int fromVersion,
    required int toVersion,
    required String timestamp,
    bool createBackup = true,
  }) async {
    await super.beginApply(
      dbPath: dbPath,
      fromVersion: fromVersion,
      toVersion: toVersion,
      timestamp: timestamp,
      createBackup: createBackup,
    );
    beginCompleted.complete();
    await releaseBegin.future;
  }
}

class _ThrowingRefreshService extends LibraryRuntimeRefreshService {
  bool called = false;

  @override
  Future<void> refreshAfterDbUpdate() async {
    called = true;
    throw StateError('refresh failed');
  }
}

class _NoopRefreshService extends LibraryRuntimeRefreshService {
  bool called = false;

  @override
  Future<void> refreshAfterDbUpdate() async {
    called = true;
  }
}

/// downloader עם http.Client אמיתי (IOClient לא-sendable), שמחזיר patch מקומי.
class _LocalPatchDownloader extends PatchDownloader {
  _LocalPatchDownloader(this.patchPath, {this.verifyProgress})
    : super(decompress: (b) async => b);
  final String patchPath;
  final (int, int)? verifyProgress;

  @override
  Future<String> downloadAndExtract({
    required PatchFileEntry patchFile,
    required String downloadUrl,
    required Directory destDir,
    void Function(int downloaded, int? total)? onProgress,
    void Function(int bytesDone, int bytesTotal)? onVerifyProgress,
    bool Function()? isCancelled,
  }) async {
    final progress = verifyProgress;
    if (progress != null) onVerifyProgress?.call(progress.$1, progress.$2);
    return patchPath;
  }
}

class _PatchMapDownloader extends PatchDownloader {
  _PatchMapDownloader(this.patchPaths) : super(decompress: (b) async => b);

  final Map<String, String> patchPaths;

  @override
  Future<String> downloadAndExtract({
    required PatchFileEntry patchFile,
    required String downloadUrl,
    required Directory destDir,
    void Function(int downloaded, int? total)? onProgress,
    void Function(int bytesDone, int bytesTotal)? onVerifyProgress,
    bool Function()? isCancelled,
  }) async => patchPaths[patchFile.file]!;
}

/// ה-hash לכל טבלה בסדר של סכמה 4 — הבסיס למפות שבמניפסט.
Map<String, String> _tableHashes(String dbPath, {int schemaVersion = 4}) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    return const LogicalContentHasher()
        .computeReport(
          db,
          tableOrder: hashTableOrderForSchemaVersion(schemaVersion),
        )
        .tableHashes;
  } finally {
    db.close();
  }
}

/// ה-hash הכולל בסדר של סכמה 4, כמו ה-edges של [_schema4Edge].
String _logicalHash(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    return const LogicalContentHasher().compute(
      db,
      tableOrder: hashTableOrderForSchemaVersion(4),
    );
  } finally {
    db.close();
  }
}

void _writeSchema4SourceDb(
  String dbPath, {
  required int version,
  required String sourceName,
  String? authorName,
}) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute(
      "INSERT INTO schema_meta VALUES ('db_version', ?), "
      "('db_schema_version', '4')",
      [version.toString()],
    );
    db.execute('CREATE TABLE source (id INTEGER PRIMARY KEY, name TEXT)');
    db.execute('INSERT INTO source VALUES (1, ?)', [sourceName]);
    if (authorName != null) {
      db.execute('CREATE TABLE author (id INTEGER PRIMARY KEY, name TEXT)');
      db.execute('INSERT INTO author VALUES (1, ?)', [authorName]);
    }
    db.execute('PRAGMA journal_mode=DELETE');
  } finally {
    db.close();
  }
}

void _writeSourcePatch(
  String patchPath, {
  required int fromVersion,
  required int toVersion,
  required String sourceName,
  int patchFormatVersion = 4,
}) {
  final db = sqlite3.sqlite3.open(patchPath);
  try {
    db.execute('CREATE TABLE patch_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute(
      "INSERT INTO patch_meta VALUES ('schema_version', ?), "
      "('from_version', ?), ('to_version', ?)",
      [patchFormatVersion, fromVersion, toVersion],
    );
    db.execute(
      'CREATE TABLE migrations (version INTEGER PRIMARY KEY, sql TEXT)',
    );
    db.execute(
      'CREATE TABLE upsert_schema_meta (key TEXT PRIMARY KEY, value TEXT)',
    );
    db.execute(
      "INSERT INTO upsert_schema_meta VALUES ('db_version', ?)",
      [toVersion.toString()],
    );
    db.execute(
      'CREATE TABLE upsert_source (id INTEGER PRIMARY KEY, name TEXT)',
    );
    db.execute('INSERT INTO upsert_source VALUES (1, ?)', [sourceName]);
  } finally {
    db.close();
  }
}

PatchEdge _schema4Edge({
  required int fromVersion,
  required int toVersion,
  required String patchName,
  required String toHash,
  Map<String, String>? fromTableHashes,
  Map<String, String>? toTableHashes,
}) {
  final manifest = DeltaManifest.fromJson({
    'fromVersion': fromVersion,
    'toVersion': toVersion,
    'fromSchemaVersion': 4,
    'toSchemaVersion': 4,
    'patchFormatVersion': 4,
    'fromContentHash': 'unused',
    'toContentHash': toHash,
    'fromTableContentHashes': ?fromTableHashes,
    'toTableContentHashes': ?toTableHashes,
    'patchFiles': [
      {
        'file': patchName,
        'compression': 'zstd',
        'sha256': 'aa',
        'size': 1,
        'uncompressedSha256': 'bb',
        'uncompressedSize': 1,
      },
    ],
  });
  return PatchEdge(
    manifest: manifest,
    patchFileUrls: {patchName: 'https://x/$patchName'},
    manifestUrl: 'https://x/$patchName.manifest.json',
  );
}

LibraryUpdatePlan _schema4DeltaPlan(List<PatchEdge> steps) =>
    LibraryUpdatePlan.delta(
      localVersion: steps.first.fromVersion,
      targetVersion: steps.last.toVersion,
      steps: steps,
    );

String? _readSourceName(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    return db.select('SELECT name FROM source WHERE id = 1').first['name']
        as String?;
  } finally {
    db.close();
  }
}

LibraryUpdatePlan _deltaPlan({
  String file = 'patch.db.zst',
  int size = 1,
  int uncompressedSize = 1,
  String uncompressedSha256 = 'bb',
}) {
  final manifest = DeltaManifest.fromJson({
    'fromVersion': 1,
    'toVersion': 2,
    'fromSchemaVersion': 1,
    'toSchemaVersion': 1,
    'fromContentHash': 'deadbeef',
    'toContentHash': 'cafef00d',
    'patchFiles': [
      {
        'file': file,
        'compression': 'zstd',
        'sha256': 'aa',
        'size': size,
        'uncompressedSha256': uncompressedSha256,
        'uncompressedSize': uncompressedSize,
      },
    ],
  });
  return LibraryUpdatePlan.delta(
    localVersion: 1,
    targetVersion: 2,
    steps: [
      PatchEdge(
        manifest: manifest,
        patchFileUrls: {file: 'https://x/$file'},
        manifestUrl: 'https://x/manifest.json',
      ),
    ],
  );
}
