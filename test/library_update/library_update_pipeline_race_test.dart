import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/library_update/repository/library_update_repository.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/library_update/services/library_runtime_refresh_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('library_pipeline_race_');
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

  for (final scenario in [
    (name: 'same DB and cache', sameDb: true, sameCache: true),
    (name: 'same DB, different caches', sameDb: true, sameCache: false),
    (name: 'different DBs, same cache', sameDb: false, sameCache: true),
  ]) {
    test(
      'cancel then immediate retry is excluded until teardown: ${scenario.name}',
      () async {
        final firstDb = p.join(tmp.path, 'first.db');
        final secondDb = scenario.sameDb
            ? firstDb
            : p.join(tmp.path, 'second.db');
        final firstCache = Directory(p.join(tmp.path, 'first-cache'))
          ..createSync();
        final secondCache = scenario.sameCache
            ? firstCache
            : (Directory(p.join(tmp.path, 'second-cache'))..createSync());
        _writeDb(firstDb, 'old');
        if (!scenario.sameDb) _writeDb(secondDb, 'old');
        final entered = Completer<void>();
        final releaseWorker = Completer<void>();
        var cancelled = false;
        var contenderExtractions = 0;

        final first = _repository(
          firstDb,
          firstCache.path,
          (
            source,
            output, {
            required maxOutputBytes,
            isCancelled,
            onProgress,
          }) async {
            _writeDb(output, 'old worker staging', version: 2);
            entered.complete();
            await releaseWorker.future;
            if (isCancelled?.call() ?? false)
              throw const PatchDownloadCancelled();
          },
        );
        final second = _repository(
          secondDb,
          secondCache.path,
          (
            source,
            output, {
            required maxOutputBytes,
            isCancelled,
            onProgress,
          }) async {
            contenderExtractions++;
            expect(_marker(secondDb), 'old');
            _writeDb(output, 'new', version: 2);
          },
        );
        final oldOutcome = expectLater(
          first.applyFullDownload(_plan(), isCancelled: () => cancelled),
          throwsA(isA<PatchDownloadCancelled>()),
        );
        try {
          await entered.future;
          cancelled = true;
          await expectLater(
            second.applyFullDownload(_plan()),
            throwsA(isA<PatchDownloadException>()),
          );
          expect(contenderExtractions, 0);
          expect(_marker(firstDb), 'old');
          expect(_marker(secondDb), 'old');
          expect(_marker('$firstDb.new'), 'old worker staging');
        } finally {
          releaseWorker.complete();
          await oldOutcome;
        }

        expect(File('$firstDb.new').existsSync(), isFalse);
        expect(_marker(firstDb), 'old');
        expect(
          File(
            p.join(firstCache.path, 'library_update_cache', 'seforim.db.zst'),
          ).existsSync(),
          isTrue,
        );
        await second.applyFullDownload(_plan());
        expect(contenderExtractions, 1);
        expect(_marker(secondDb), 'new');
        if (!scenario.sameDb) expect(_marker(firstDb), 'old');
        expect(File('$secondDb.new').existsSync(), isFalse);
      },
    );
  }
}

LibraryUpdateRepository _repository(
  String dbPath,
  String dataRoot,
  FullDbExtractor extractor,
) {
  final client = MockClient.streaming(
    (request, stream) async => http.StreamedResponse(
      Stream.value(const [1]),
      200,
      contentLength: 1,
      headers: const {'etag': '"fixture"'},
    ),
  );
  final downloader = PatchDownloader(
    httpClient: client,
    decompress: (bytes) async => bytes,
  );
  addTearDown(client.close);
  return LibraryUpdateRepository(
    discovery: LibraryUpdateDiscovery(
      client: GithubLibraryReleaseClient(httpClient: client),
    ),
    downloader: downloader,
    fullDbExtractor: extractor,
    dbPathProvider: () => dbPath,
    dataRootProvider: () async => dataRoot,
    nowTimestamp: () => '2026-11-05T00:00:00Z',
    diskSpaceProvider: (_) async => DiskSpaceInfo.unknown,
    refreshService: _NoopRefresh(),
    accessGate: LibraryAccessGate(
      selfAccess: LibraryAccessRoutine(
        suspend: () async {},
        resume: (_) async {},
      ),
      renameProbe: false,
      logError: (_, _, _) {},
    ),
  );
}

LibraryUpdatePlan _plan() => LibraryUpdatePlan.fullDownload(
  localVersion: 1,
  targetVersion: 2,
  asset: const ReleaseAsset(
    name: 'seforim.db.zst',
    downloadUrl: 'https://fixture.invalid/seforim.db.zst',
    size: 1,
  ),
  releaseTag: 'v2',
);

void _writeDb(String path, String marker, {int version = 1}) {
  final db = sqlite3.open(path);
  try {
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute(
      "INSERT INTO schema_meta VALUES ('db_version', ?), ('db_schema_version', '1')",
      [version.toString()],
    );
    db.execute('CREATE TABLE marker (value TEXT)');
    db.execute('INSERT INTO marker VALUES (?)', [marker]);
    db.execute('PRAGMA journal_mode=DELETE');
  } finally {
    db.close();
  }
}

String _marker(String path) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return db.select('SELECT value FROM marker').single['value'] as String;
  } finally {
    db.close();
  }
}

class _NoopRefresh extends LibraryRuntimeRefreshService {
  @override
  Future<void> refreshAfterDbUpdate() async {}
}
