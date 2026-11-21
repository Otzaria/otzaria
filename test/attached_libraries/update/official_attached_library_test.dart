import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/models/official_attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_store.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_downloader.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_file_swap.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_signature.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _id = 'otzaria.zmanenu';
const _url = 'https://official.example.org/zmanenu/manifest.json';

class _FakeFetcher extends AttachedUpdateFetcher {
  Uint8List manifest = Uint8List(0);
  Uint8List signature = Uint8List(0);
  final urls = <String>[];

  @override
  Future<({Uint8List manifest, Uint8List signature})> fetchSignedManifest(
    String manifestUrl, {
    AttachedUpdateCancelToken? cancel,
  }) async {
    urls.add(manifestUrl);
    return (manifest: manifest, signature: signature);
  }
}

/// Copies a prepared database to the output instead of downloading.
class _FakeDownloader extends AttachedUpdateDownloader {
  String? source;
  final artifacts = <AttachedUpdateArtifact>[];
  final basePaths = <String?>[];

  @override
  Future<void> download(
    AttachedUpdateArtifact artifact, {
    required String combinedPath,
    required String outputPath,
    String? basePath,
    AttachedUpdateProgress? onProgress,
    AttachedUpdateProgress? onExtractionProgress,
    AttachedUpdateCancelToken? cancel,
    void Function()? onWaitingForWifi,
  }) async {
    artifacts.add(artifact);
    basePaths.add(basePath);
    onProgress?.call(1, 2);
    await File(source!).copy(outputPath);
  }
}

String _sha(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository repository;
  late _FakeFetcher fetcher;
  late _FakeDownloader downloader;
  late String privateKey;
  late String publicKey;
  late OfficialAttachedLibrary entry;
  var counter = 0;

  AttachedLibraryUpdateService service() => AttachedLibraryUpdateService(
    repository: repository,
    fetcher: fetcher,
    downloader: downloader,
    probe: (path) async => AttachedLibraryProbe.probeSync(path),
    swap: const AttachedUpdateFileSwap(lockRetries: 1),
    diskSpace: (_) async => DiskSpaceInfo(volumeId: 'V', freeBytes: 1 << 40),
    workDirectory: () async => p.join(temp.path, 'work'),
    isOfflineMode: () => false,
    areUpdatesEnabled: () => true,
    isAutoCheckDue: () => true,
    recordCheck: () async {},
  );

  /// A fixture database that declares [libraryId] and an update source.
  String database({
    String version = '1',
    String libraryId = _id,
    String? key,
    String url = _url,
  }) {
    final folder = Directory(p.join(temp.path, 'db${counter++}'))
      ..createSync(recursive: true);
    final created = SeforimFixtureDb.create(
      Directory(p.join(temp.path, 'raw${counter++}'))..createSync(),
      SeforimFixtureVariant.full,
    );
    final path = p.join(folder.path, 'lib.db');
    File(created).copySync(path);
    final db = sqlite3.sqlite3.open(path);
    for (final entry in {
      'library_id': libraryId,
      'db_version': version,
      'update_manifest_url': url,
      'update_public_key': key ?? publicKey,
    }.entries) {
      db.execute('DELETE FROM schema_meta WHERE key = ?', [entry.key]);
      db.execute('INSERT INTO schema_meta VALUES (?, ?)', [
        entry.key,
        entry.value,
      ]);
    }
    db.close();
    return path;
  }

  AttachedUpdateArtifact artifactOf(String path, String name) {
    final digest = _sha(path);
    final size = File(path).lengthSync();
    return AttachedUpdateArtifact(
      compression: AttachedUpdateCompression.none,
      size: size,
      sha256: digest,
      parts: [
        AttachedUpdatePart(
          url: 'https://official.example.org/zmanenu/$name',
          size: size,
          sha256: digest,
        ),
      ],
    );
  }

  /// Publishes [newDb]; with [deltaFrom] also a small patch from that file.
  void publish(
    String newDb, {
    int version = 1,
    String? signWith,
    String? deltaFrom,
  }) {
    final full = artifactOf(newDb, 'full');
    final manifest = AttachedUpdateManifest(
      libraryId: _id,
      dbVersion: version,
      full: full,
      deltas: [
        if (deltaFrom != null)
          AttachedUpdateDelta(
            fromDbVersion: version - 1,
            fromSha256: _sha(deltaFrom),
            artifact: AttachedUpdateArtifact(
              compression: AttachedUpdateCompression.zstdPatch,
              size: full.size,
              sha256: full.sha256,
              parts: [
                AttachedUpdatePart(
                  url: 'https://official.example.org/zmanenu/patch',
                  size: 1,
                  sha256: full.sha256,
                ),
              ],
            ),
          ),
      ],
    );
    fetcher.manifest = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest.toJson())),
    );
    fetcher.signature = Uint8List.fromList(
      ascii.encode(
        AttachedUpdateSignature.sign(fetcher.manifest, signWith ?? privateKey),
      ),
    );
    downloader.source = newDb;
  }

  Future<AttachedLibrary> installOfficial(
    AttachedLibraryUpdateService svc,
  ) async {
    await svc.checkOfficialOffers();
    expect(svc.officialStatusOf(_id), isA<AttachedUpdateAvailable>());
    await svc.installOfficial(entry);
    expect(svc.officialStatusOf(_id), isA<AttachedUpdateInstalled>());
    return repository.libraries.singleWhere((l) => l.isOfficial);
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    temp = await Directory.systemTemp.createTemp('otzaria_official');
    registry = AttachedLibraryRegistry(idleTimeout: null);
    repository = AttachedLibrariesRepository(
      registry: registry,
      probe: (path) async => AttachedLibraryProbe.probeSync(path),
      copyDirectory: () async => p.join(temp.path, 'copies'),
      copyByDefault: false,
    );
    fetcher = _FakeFetcher();
    downloader = _FakeDownloader();
    privateKey = AttachedUpdateSignature.generatePrivateKey();
    publicKey = AttachedUpdateSignature.publicKeyOf(privateKey);
    entry = OfficialAttachedLibrary(
      libraryId: _id,
      displayName: 'מחברי זמנינו',
      manifestUrl: _url,
      publicKey: publicKey,
    );
    OfficialAttachedLibraries.catalogForTesting = [entry];
    AttachedUpdateArtifactPlanner.clearCacheForTesting();
  });

  tearDown(() async {
    OfficialAttachedLibraries.catalogForTesting = null;
    await registry.closeAll();
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  test('the built-in entry: name, release manifest URL, active with its key', () {
    OfficialAttachedLibraries.catalogForTesting = null;
    final builtIn = OfficialAttachedLibraries.byId(_id)!;
    expect(builtIn.displayName, 'מחברי זמנינו');
    expect(
      builtIn.manifestUrl,
      'https://github.com/Otzaria/zmanenu-library/releases/latest/download/manifest.json',
    );
    expect(builtIn.isActive, zmanenuPublicKey.isNotEmpty);
    if (!builtIn.isActive) {
      expect(
        AttachedLibraryUpdateService.notInstalledOfficial(const []),
        isEmpty,
      );
    }
  });

  group('trust comes from the signature, not from the file', () {
    test('a copied id and key do not make a file official', () async {
      final attached = await repository.importFile(database());
      final fake = attached.library!;
      expect(fake.isOfficial, isFalse);
      expect(
        AttachedLibraryUpdateService.notInstalledOfficial(
          repository.libraries,
        ),
        [entry],
      );

      // A newer official release is found, but never installed unasked.
      publish(database(version: '2'), version: 2);
      final svc = service();
      await svc.runScheduledCheck();
      expect(svc.statusOf(fake), isA<AttachedUpdateAvailable>());
      expect(downloader.artifacts, isEmpty);
      expect(repository.libraries.single.fingerprint!.dbVersion, '1');
    });

    test('a manifest with a bad signature is rejected', () async {
      final other = AttachedUpdateSignature.generatePrivateKey();
      publish(database(), signWith: other);
      final svc = service();
      await svc.checkOfficialOffers();
      expect(
        svc.officialStatusOf(_id),
        const AttachedUpdateFailed(AttachedUpdateError.badSignature),
      );
      await svc.installOfficial(entry);
      expect(downloader.artifacts, isEmpty);
      expect(repository.libraries, isEmpty);
    });

    test('the installed official copy wins over a manual one', () async {
      final manual = (await repository.importFile(database())).library!;
      publish(database());
      await installOfficial(service());

      final byPath = {for (final l in repository.libraries) l.path: l};
      expect(byPath[manual.path]!.status, AttachedLibraryStatus.duplicateSlug);
      expect(repository.libraries.where((l) => l.isOk).single.isOfficial, true);

      // And a further manual copy is refused as a duplicate.
      final again = await repository.importFile(database());
      expect(again.problem, AttachedLibraryProblem.duplicateSlug);
    });
  });

  test('download and install marks a managed copy as official', () async {
    // The file names another host and key; neither is ever used.
    final published = database(
      key: AttachedUpdateSignature.publicKeyOf(
        AttachedUpdateSignature.generatePrivateKey(),
      ),
      url: 'https://attacker.example.net/manifest.json',
    );
    publish(published);
    final svc = service();
    await svc.checkOfficialOffers();
    final offer = svc.officialStatusOf(_id).offer!;
    expect(offer.manifest.full.compressedSize, File(published).lengthSync());

    final changed = repository.changes.first;
    final library = await installOfficial(svc);
    expect(await changed, isA<Set<String>>());
    expect(library.mode, AttachedLibraryMode.copy);
    expect(
      p.isWithin(p.join(temp.path, 'copies', 'official'), library.path),
      isTrue,
    );
    expect(library.displayName, 'מחברי זמנינו');
    expect(library.updateSource, entry.source);
    expect(library.updateSourceMismatch, isFalse);
    expect(
      library.official,
      AttachedOfficialInstall(
        libraryId: _id,
        dbVersion: 1,
        sha256: _sha(published),
      ),
    );
    expect(
      AttachedLibraryUpdateService.notInstalledOfficial(repository.libraries),
      isEmpty,
    );
    expect(
      const AttachedLibraryStore().loadLibrariesOrNull()!.single.official,
      library.official,
    );

    // A backup archive is not a trusted source for the official mark.
    await const AttachedLibraryStore().forgetUpdatePins();
    expect(
      const AttachedLibraryStore().loadLibrariesOrNull()!.single.isOfficial,
      isFalse,
    );
  });

  test('an installed official copy updates itself through a delta', () async {
    publish(database());
    final svc = service();
    final library = await installOfficial(svc);

    final next = database(version: '2');
    publish(next, version: 2, deltaFrom: library.path);
    await svc.runScheduledCheck();

    expect(svc.statusOf(library), const AttachedUpdateInstalled(2));
    expect(
      downloader.artifacts.last.compression,
      AttachedUpdateCompression.zstdPatch,
    );
    expect(downloader.basePaths.last, library.path);
    final updated = repository.libraries.single;
    expect(updated.fingerprint!.dbVersion, '2');
    expect(updated.official!.dbVersion, 2);
    expect(updated.official!.sha256, _sha(next));
    expect(updated.updateSource, entry.source);
  });

  test(
    'a modified official copy is not updated until a full download',
    () async {
      publish(database());
      final svc = service();
      final library = await installOfficial(svc);
      await registry.closeAll();
      final db = sqlite3.sqlite3.open(library.path);
      db.execute('CREATE TABLE tampered (x INTEGER)');
      db.close();
      File(
        library.path,
      ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
      await repository.rescan();
      // Changed on disk outside the installer: no longer shown as official.
      final unverified = repository.libraries.single;
      expect(unverified.isOfficial, isFalse);
      expect(unverified.official!.verified, isFalse);
      expect(
        const AttachedLibraryStore().loadLibrariesOrNull()!.single.isOfficial,
        isFalse,
      );

      final next = database(version: '2');
      publish(next, version: 2, deltaFrom: next);
      final downloadsBefore = downloader.artifacts.length;
      await svc.runScheduledCheck();
      final current = repository.libraries.single;
      expect(
        svc.statusOf(current),
        isA<AttachedUpdateFailed>().having(
          (f) => f.error,
          'error',
          AttachedUpdateError.integrityMismatch,
        ),
      );
      expect(downloader.artifacts.length, downloadsBefore);

      await svc.install(current, forceFull: true);
      expect(svc.statusOf(current), const AttachedUpdateInstalled(2));
      expect(
        downloader.artifacts.last.compression,
        AttachedUpdateCompression.none,
      );
      expect(repository.libraries.single.official!.sha256, _sha(next));
      expect(repository.libraries.single.isOfficial, isTrue);
    },
  );

  group('the download offer', () {
    test('is not offered once installed', () async {
      publish(database());
      final svc = service();
      await installOfficial(svc);
      fetcher.urls.clear();
      await svc.checkOfficialOffers();
      expect(fetcher.urls, isEmpty);
    });

    test('is not offered again after a refusal', () async {
      publish(database());
      final svc = service();
      await svc.setOfficialDeclined(_id, declined: true);
      await svc.checkOfficialOffers();
      expect(fetcher.urls, isEmpty);
      expect(svc.officialStatusOf(_id), const AttachedUpdateIdle());
      final state = AttachedLibrariesState(
        officialOffers: AttachedLibraryUpdateService.notInstalledOfficial(
          repository.libraries,
        ),
        declinedOfficial: svc.declinedOfficial(),
      );
      expect(state.shownOfficialOffers, isEmpty);

      // Still available from settings: undoing the refusal fetches again.
      await svc.setOfficialDeclined(_id, declined: false);
      await svc.checkOfficialOffers();
      expect(fetcher.urls, [_url]);
    });

    test('an inactive entry (no key) offers nothing', () async {
      OfficialAttachedLibraries.catalogForTesting = [
        const OfficialAttachedLibrary(
          libraryId: _id,
          displayName: 'x',
          manifestUrl: _url,
          publicKey: '',
        ),
      ];
      final svc = service();
      await svc.checkOfficialOffers();
      expect(fetcher.urls, isEmpty);
      expect(
        AttachedLibraryUpdateService.notInstalledOfficial(const []),
        isEmpty,
      );
    });
  });
}
