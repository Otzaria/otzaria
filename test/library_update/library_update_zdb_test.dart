import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';
import 'package:otzaria/library_update/services/library_zdb_install.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/memory_settings_cache.dart';
import '../helpers/zdb_fixture.dart';

/// מסלול ההורדה המלאה של seforim.zdb (A3) ומדיניות ה-overlay (A4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String zdbPath;
  late String releaseZdb;
  late Uint8List releaseBytes;
  late FullDbManifest manifest;
  late ReleaseAsset asset;

  setUpAll(() => expect(ensureLibraryVfs(), isTrue));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('library_update_zdb_test_');
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      tmp.path,
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
    zdbPath = LibraryZdbFiles.zdbPathIn(tmp.path);
    // ה-asset של ה-release, מחוץ לתיקיית הספרייה.
    final releaseDir = Directory(p.join(tmp.path, 'release'))..createSync();
    releaseZdb = p.join(releaseDir.path, 'seforim-schema6.zdb');
    await writeFixtureZdb(releaseZdb, version: 2, marker: 'release');
    releaseBytes = File(releaseZdb).readAsBytesSync();
    manifest = fixtureManifestFor(releaseZdb, dbVersion: 2);
    asset = ReleaseAsset(
      name: 'seforim-schema6.zdb',
      downloadUrl: 'https://x/seforim-schema6.zdb',
      size: releaseBytes.length,
      id: 1,
      updatedAt: '2026-10-01T00:00:00Z',
    );
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    tmp.deleteSync(recursive: true);
  });

  LibraryUpdatePlan fullPlan({int localVersion = 1}) =>
      LibraryUpdatePlan.fullDownload(
        localVersion: localVersion,
        targetVersion: 2,
        asset: asset,
        releaseTag: 'v2',
      );

  LibraryUpdateRepository repository({
    required String dbPath,
    FullDbManifest? fullManifest,
    bool withFullDb = true,
    Uint8List? served,
    bool Function(String path)? isOpenInProcess,
    bool idle = true,
    List<String>? retargeted,
    _CountingRefresh? refresh,
    int? latestVersion,
    void Function()? onRequest,
  }) {
    final body = served ?? releaseBytes;
    return LibraryUpdateRepository(
      discovery: _FixedDiscovery(
        LibraryDiscoveryResult(
          latestVersion: latestVersion ?? 2,
          edges: const [],
          latestFullDbAsset: withFullDb ? asset : null,
          latestReleaseTag: 'v2',
          latestDbSchemaVersion: 6,
          latestFullDbManifest: withFullDb ? (fullManifest ?? manifest) : null,
        ),
      ),
      downloader: PatchDownloader(
        httpClient: MockClient.streaming((request, _) async {
          onRequest?.call();
          return http.StreamedResponse(
            Stream.value(body),
            200,
            contentLength: body.length,
            headers: const {'etag': '"zdb-1"'},
          );
        }),
        decompress: (b) async => b,
      ),
      refreshService: refresh ?? _CountingRefresh(),
      accessGate: LibraryAccessGate(
        selfAccess: LibraryAccessRoutine(
          suspend: () async {},
          resume: (_) async {},
        ),
        renameProbe: false,
        isOpenInProcess: isOpenInProcess,
        logError: (_, _, _) {},
      ),
      dbPathProvider: () => dbPath,
      dataRootProvider: () async => tmp.path,
      diskSpaceProvider: (_) async => DiskSpaceInfo.unknown,
      isLibraryIdle: () => idle,
      onLegacyDbReplaced: (legacy, zdb) async =>
          retargeted?.addAll([legacy, zdb]),
    );
  }

  String downloadPath() => LibraryZdbFiles.downloadPathFor(zdbPath);

  group('applyFullDownload: zdb', () {
    test('מעבר מ-seforim.db: מתקין zdb ומוחק את הישן ולוואיו', () async {
      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);
      File('$legacy-wal').writeAsStringSync('');
      final retargeted = <String>[];
      final refresh = _CountingRefresh();
      var replaced = false;
      final phases = <LibraryUpdatePhase>[];

      // כמו ה-bloc: callback שלוכד אובייקט שאינו sendable.
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      await repository(
        dbPath: legacy,
        retargeted: retargeted,
        refresh: refresh,
      ).applyFullDownload(
        fullPlan(),
        onDbReplaced: () => replaced = true,
        onProgress: (progress) {
          unsendable.hashCode;
          phases.add(progress.phase);
        },
      );

      expect(readFixtureLibrary(zdbPath), (version: 2, marker: 'release'));
      expect(DatabaseConstants.resolveLibraryDbPath(tmp.path), zdbPath);
      for (final suffix in LibraryZdbFiles.legacySuffixes) {
        expect(File('$legacy$suffix').existsSync(), isFalse, reason: suffix);
      }
      expect(retargeted, [legacy, zdbPath]);
      expect(replaced, isTrue);
      expect(refresh.calls, 1);
      expect(
        phases,
        containsAllInOrder([
          LibraryUpdatePhase.downloading,
          LibraryUpdatePhase.verifying,
          LibraryUpdatePhase.applying,
          LibraryUpdatePhase.refreshing,
          LibraryUpdatePhase.done,
        ]),
      );
      for (final leftover in [
        downloadPath(),
        PatchDownloader.resumeSidecarPath(downloadPath()),
        '$zdbPath.new',
        '$zdbPath.install',
        '$zdbPath.backup',
        '$zdbPath.applying',
      ]) {
        expect(File(leftover).existsSync(), isFalse, reason: leftover);
      }
    });

    test('zdb קיים עם overlay מוחלף בבסיס החדש, בלי overlay', () async {
      await writeFixtureZdb(zdbPath, version: 1, marker: 'old');
      growZdbOverlay(zdbPath);
      expect(File('$zdbPath-zovl').existsSync(), isTrue);

      await repository(dbPath: zdbPath).applyFullDownload(fullPlan());

      expect(File('$zdbPath-zovl').existsSync(), isFalse);
      expect(readFixtureLibrary(zdbPath), (version: 2, marker: 'release'));
    });

    test(
      '-zovl שנשאר ליד ההורדה אינו חוסם התקנה (לפני ואחרי ניקוי העלייה)',
      () async {
        final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
        writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);
        // כמו אחרי קריסה באמצע ייבוא עם overlay: מועמד + -zovl, בלי resume.
        final other = p.join(tmp.path, 'other.zdb');
        await writeFixtureZdb(other, version: 1, marker: 'imported');
        growZdbOverlay(other);
        File(other).copySync(downloadPath());
        File('$other-zovl').copySync('${downloadPath()}-zovl');
        File('${downloadPath()}.new').writeAsStringSync('x');
        File('${downloadPath()}.new-zlck').writeAsStringSync('');

        await cleanUpZdbLeftovers(tmp.path);
        for (final suffix in ['', '-zovl', '.new', '.new-zlck', '-zlck']) {
          expect(
            File('${downloadPath()}$suffix').existsSync(),
            isFalse,
            reason: suffix,
          );
        }

        // גם בלי ניקוי העלייה: שארית שנוצרה אחריו נמחקת לפני ההורדה והאימות.
        File('${downloadPath()}-zovl').writeAsStringSync('stale overlay');
        var requests = 0;
        await repository(
          dbPath: legacy,
          served: releaseBytes,
          onRequest: () => requests++,
        ).applyFullDownload(fullPlan());

        expect(readFixtureLibrary(zdbPath), (version: 2, marker: 'release'));
        expect(requests, 1);
        expect(File('${downloadPath()}-zovl').existsSync(), isFalse);
      },
    );

    test('sha256 שאינו תואם: ההורדה נמחקת והספרייה לא נגעה', () async {
      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);
      final bad = fixtureManifestFor(
        releaseZdb,
        dbVersion: 2,
        file: asset.name,
        sha256Hex: 'a' * 64,
      );
      await expectLater(
        repository(
          dbPath: legacy,
          fullManifest: bad,
        ).applyFullDownload(fullPlan()),
        throwsA(isA<PatchDownloadException>()),
      );
      expect(File(downloadPath()).existsSync(), isFalse);
      expect(File(zdbPath).existsSync(), isFalse);
      expect(File(legacy).existsSync(), isTrue);
    });

    final headerCases = <String, FullDbManifest Function()>{
      'fileUuid': () => fixtureManifestFor(
        releaseZdb,
        dbVersion: 2,
        fileUuid: 'f' * 32,
      ),
      'contentXxh64': () => fixtureManifestFor(
        releaseZdb,
        dbVersion: 2,
        contentXxh64: 'f' * 16,
      ),
      'logicalSize': () =>
          fixtureManifestFor(releaseZdb, dbVersion: 2, logicalSize: 4096),
    };
    for (final entry in headerCases.entries) {
      test('${entry.key} שאינו תואם: ההורדה נמחקת לפני ההתקנה', () async {
        final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
        writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);
        await expectLater(
          repository(
            dbPath: legacy,
            fullManifest: entry.value(),
          ).applyFullDownload(fullPlan()),
          throwsA(isA<LibraryZdbVerificationException>()),
        );
        expect(File(downloadPath()).existsSync(), isFalse);
        expect(
          File(PatchDownloader.resumeSidecarPath(downloadPath())).existsSync(),
          isFalse,
        );
        expect(File(zdbPath).existsSync(), isFalse);
        expect(File(legacy).existsSync(), isTrue);
      });
    }

    test('גודל שאינו תואם לנכס — אין מניפסט תואם, ואין הורדה', () async {
      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);
      await expectLater(
        repository(
          dbPath: legacy,
          fullManifest: fixtureManifestFor(releaseZdb, dbVersion: 2, size: 9),
        ).applyFullDownload(fullPlan()),
        throwsA(isA<FullDbManifestException>()),
      );
      expect(File(downloadPath()).existsSync(), isFalse);
    });

    test('formatMajor שאינו נתמך נדחה לפני ההורדה', () async {
      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);
      await expectLater(
        repository(
          dbPath: legacy,
          fullManifest: fixtureManifestFor(
            releaseZdb,
            dbVersion: 2,
            formatMajor: 2,
          ),
        ).applyFullDownload(fullPlan()),
        throwsA(isA<LibraryZdbVerificationException>()),
      );
      expect(File(downloadPath()).existsSync(), isFalse);
    });

    test('busy: הבסיס הישן וה-overlay נשארים, וההורדה נשמרת להמשך', () async {
      await writeFixtureZdb(zdbPath, version: 1, marker: 'old');
      growZdbOverlay(zdbPath);
      final overlayBefore = File('$zdbPath-zovl').lengthSync();
      final reader = sqlite3.sqlite3.open(
        zdbPath,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        await expectLater(
          // השער עובר, ו-installZdb עצמו מגלה את החיבור הפתוח.
          repository(
            dbPath: zdbPath,
            isOpenInProcess: (_) => false,
          ).applyFullDownload(fullPlan()),
          throwsA(
            isA<LibraryZdbException>().having((e) => e.isBusy, 'isBusy', true),
          ),
        );
      } finally {
        reader.close();
      }
      expect(File('$zdbPath-zovl').lengthSync(), overlayBefore);
      expect(readFixtureLibrary(zdbPath).marker, 'old');
      expect(File(downloadPath()).lengthSync(), releaseBytes.length);
      expect(
        File(PatchDownloader.resumeSidecarPath(downloadPath())).existsSync(),
        isTrue,
      );
    });

    test('seforim.db.zst מעל ספריית zdb עדיין חסום', () async {
      await writeFixtureZdb(zdbPath, version: 1);
      await expectLater(
        repository(dbPath: zdbPath).applyFullDownload(
          LibraryUpdatePlan.fullDownload(
            localVersion: 1,
            targetVersion: 2,
            asset: const ReleaseAsset(
              name: DatabaseConstants.databaseArchiveFileName,
              downloadUrl: 'https://x/seforim.db.zst',
              size: 1,
            ),
            releaseTag: 'v2',
          ),
        ),
        throwsA(isA<LibraryUpdateZdbFullDownloadUnsupportedException>()),
      );
    });
  });

  group('checkForUpdate', () {
    LibraryUpdateRepository recordingRepository(String dbPath) =>
        LibraryUpdateRepository(
          discovery: _FixedDiscovery(
            const LibraryDiscoveryResult(
              latestVersion: 0,
              edges: [],
              latestFullDbAsset: null,
              latestReleaseTag: null,
            ),
          ),
          versionReader: _IsolateRecordingReader(Isolate.current.debugName),
          downloader: PatchDownloader(decompress: (b) async => b),
          dbPathProvider: () => dbPath,
          dataRootProvider: () async => tmp.path,
        );

    test('גרסת zdb נקראת מחוץ ל-UI isolate, ומסד רגיל עליו', () async {
      await writeFixtureZdb(zdbPath, version: 2);
      final zdbPlan = await recordingRepository(
        zdbPath,
      ).checkForUpdate(allowPrerelease: false);
      expect(zdbPlan.localVersion, _IsolateRecordingReader.otherIsolate);

      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      writeFixtureLibraryDb(legacy, version: 2, schemaVersion: 5);
      final plainPlan = await recordingRepository(
        legacy,
      ).checkForUpdate(allowPrerelease: false);
      expect(plainPlan.localVersion, _IsolateRecordingReader.callingIsolate);
    });
  });

  group('maintainLibraryStorage', () {
    Future<LibraryUpdateRepository> checked(
      LibraryUpdateRepository repo,
    ) async {
      await repo.checkForUpdate(allowPrerelease: false);
      return repo;
    }

    test('מתחת לסף — אין פעולה, והורדה שנשארה נמחקת', () async {
      await writeFixtureZdb(zdbPath, version: 2);
      File(downloadPath()).writeAsStringSync('stale');
      final repo = await checked(repository(dbPath: zdbPath));
      expect(
        await repo.maintainLibraryStorage(),
        LibraryStorageMaintenance.notNeeded,
      );
      expect(File(downloadPath()).existsSync(), isFalse);
    });

    test('מעל הסף — מוריד ומתקין את הבסיס העדכני', () async {
      await writeFixtureZdb(zdbPath, version: 2, marker: 'local');
      growZdbOverlay(zdbPath);
      final refresh = _CountingRefresh();
      final phases = <LibraryUpdatePhase>{};
      final repo = await checked(
        repository(dbPath: zdbPath, refresh: refresh),
      );
      expect(
        await repo.maintainLibraryStorage(
          onProgress: (progress) => phases.add(progress.phase),
        ),
        LibraryStorageMaintenance.rebased,
      );
      expect(File('$zdbPath-zovl').existsSync(), isFalse);
      expect(readFixtureLibrary(zdbPath).marker, 'release');
      expect(refresh.calls, 1);
      expect(phases, contains(LibraryUpdatePhase.optimizing));
    });

    test('בלי DB מלא זמין — דחיסה מקומית כשהמשתמש אינו קורא', () async {
      await writeFixtureZdb(zdbPath, version: 2, marker: 'local');
      growZdbOverlay(zdbPath);
      final repo = await checked(
        repository(dbPath: zdbPath, withFullDb: false),
      );
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      var compactProgress = 0;
      expect(
        await repo.maintainLibraryStorage(
          onProgress: (progress) {
            unsendable.hashCode;
            if (progress.stage == LibraryUpdateRepository.zdbStageCompact) {
              compactProgress++;
            }
          },
        ),
        LibraryStorageMaintenance.compacted,
      );
      expect(compactProgress, greaterThan(0));
      expect(File('$zdbPath-zovl').existsSync(), isFalse);
      expect(readFixtureLibrary(zdbPath).marker, 'local');
    });

    test('הורדה שנכשלה — נופלים לדחיסה', () async {
      await writeFixtureZdb(zdbPath, version: 2, marker: 'local');
      growZdbOverlay(zdbPath);
      final repo = await checked(
        repository(dbPath: zdbPath, served: Uint8List(10)),
      );
      expect(
        await repo.maintainLibraryStorage(),
        LibraryStorageMaintenance.compacted,
      );
      expect(readFixtureLibrary(zdbPath).marker, 'local');
      expect(File(downloadPath()).existsSync(), isFalse);
    });

    test('בסיס ישן מהמקומי אינו מותקן', () async {
      await writeFixtureZdb(zdbPath, version: 3, marker: 'local');
      growZdbOverlay(zdbPath);
      final repo = await checked(
        repository(dbPath: zdbPath, idle: false, latestVersion: 3),
      );
      expect(
        await repo.maintainLibraryStorage(),
        LibraryStorageMaintenance.deferred,
      );
      expect(readFixtureLibrary(zdbPath).marker, 'local');
      expect(File(downloadPath()).existsSync(), isFalse);
    });

    test('המשתמש קורא — הדחיסה נדחית וה-overlay נשאר', () async {
      await writeFixtureZdb(zdbPath, version: 2);
      growZdbOverlay(zdbPath);
      final repo = await checked(
        repository(dbPath: zdbPath, withFullDb: false, idle: false),
      );
      expect(
        await repo.maintainLibraryStorage(),
        LibraryStorageMaintenance.deferred,
      );
      expect(File('$zdbPath-zovl').existsSync(), isTrue);
    });

    test('busy — נדחה בלי לזרוק, והספרייה לא נפגעת', () async {
      await writeFixtureZdb(zdbPath, version: 2, marker: 'local');
      growZdbOverlay(zdbPath);
      final repo = await checked(
        repository(
          dbPath: zdbPath,
          isOpenInProcess: (_) => false,
          withFullDb: false,
        ),
      );
      final reader = sqlite3.sqlite3.open(
        zdbPath,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        expect(
          await repo.maintainLibraryStorage(),
          LibraryStorageMaintenance.deferred,
        );
      } finally {
        reader.close();
      }
      expect(File('$zdbPath-zovl').existsSync(), isTrue);
      expect(readFixtureLibrary(zdbPath).marker, 'local');
    });

    test('busy בהתקנת הבסיס — נדחה ואינו נופל לדחיסה', () async {
      await writeFixtureZdb(zdbPath, version: 2, marker: 'local');
      growZdbOverlay(zdbPath);
      final repo = await checked(
        repository(dbPath: zdbPath, isOpenInProcess: (_) => false),
      );
      final reader = sqlite3.sqlite3.open(
        zdbPath,
        mode: sqlite3.OpenMode.readOnly,
      );
      try {
        expect(
          await repo.maintainLibraryStorage(),
          LibraryStorageMaintenance.deferred,
        );
      } finally {
        reader.close();
      }
      expect(File('$zdbPath-zovl').existsSync(), isTrue);
      expect(File(downloadPath()).existsSync(), isTrue);
    });

    test('ספריית seforim.db — אין מה לייעל', () async {
      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      writeFixtureLibraryDb(legacy, version: 2, schemaVersion: 5);
      expect(
        await repository(dbPath: legacy).maintainLibraryStorage(),
        LibraryStorageMaintenance.notNeeded,
      );
    });
  });
}

class _FixedDiscovery extends LibraryUpdateDiscovery {
  _FixedDiscovery(this.result)
    : super(
        client: GithubLibraryReleaseClient(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        ),
      );

  final LibraryDiscoveryResult result;

  @override
  Future<LibraryDiscoveryResult> discover({
    required bool allowPrerelease,
  }) async => result;
}

class _CountingRefresh extends LibraryRuntimeRefreshService {
  int calls = 0;

  @override
  Future<void> refreshAfterDbUpdate() async => calls++;
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
