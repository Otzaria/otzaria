import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
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

class _NoopRefreshService extends LibraryRuntimeRefreshService {
  bool called = false;

  @override
  Future<void> refreshAfterDbUpdate() async {
    called = true;
  }
}

/// downloader עם http.Client אמיתי (IOClient לא-sendable), שמחזיר patch מקומי.
class _LocalPatchDownloader extends PatchDownloader {
  _LocalPatchDownloader(this.patchPath) : super(decompress: (b) async => b);
  final String patchPath;

  @override
  Future<String> downloadAndExtract({
    required PatchFileEntry patchFile,
    required String downloadUrl,
    required Directory destDir,
    void Function(int downloaded, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async => patchPath;
}

LibraryUpdatePlan _deltaPlan() {
  final manifest = DeltaManifest.fromJson({
    'fromVersion': 1,
    'toVersion': 2,
    'fromSchemaVersion': 1,
    'toSchemaVersion': 1,
    'fromContentHash': 'deadbeef',
    'toContentHash': 'cafef00d',
    'patchFiles': [
      {
        'file': 'patch.db.zst',
        'compression': 'zstd',
        'sha256': 'aa',
        'size': 1,
        'uncompressedSha256': 'bb',
        'uncompressedSize': 1,
      },
    ],
  });
  return LibraryUpdatePlan.delta(
    localVersion: 1,
    targetVersion: 2,
    steps: [
      PatchEdge(
        manifest: manifest,
        patchFileUrls: const {'patch.db.zst': 'https://x/patch.db.zst'},
        manifestUrl: 'https://x/manifest.json',
      ),
    ],
  );
}
