import 'dart:async';
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
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../empty_library/library_package_test_support.dart';
import '../../helpers/seforim_fixture_db.dart';
import '../../support/zstd_test_lib.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _id = 'otzaria.zmanenu';
const _url = 'https://official.example.org/zmanenu/manifest.json';
const _releasePrefix = 'https://official.example.org/zmanenu/releases/v';

class _FakeFetcher extends AttachedUpdateFetcher {
  Uint8List manifest = Uint8List(0);
  Uint8List signature = Uint8List(0);
  final urls = <String>[];

  /// מניפסטים של רילייס לפי גרסה; גרסה שאינה כאן מחזירה 404.
  final releases = <int, ({Uint8List manifest, Uint8List signature})>{};
  bool offline = false;

  @override
  Future<({Uint8List manifest, Uint8List signature})> fetchSignedManifest(
    String manifestUrl, {
    AttachedUpdateCancelToken? cancel,
  }) async {
    urls.add(manifestUrl);
    if (offline) {
      throw const AttachedUpdateNetworkException('no route to host');
    }
    if (manifestUrl.startsWith(_releasePrefix)) {
      final version = int.parse(
        manifestUrl.substring(_releasePrefix.length).split('/').first,
      );
      return releases[version] ??
          (throw const AttachedUpdateHttpException(HttpStatus.notFound));
    }
    return (manifest: manifest, signature: signature);
  }
}

/// Copies a prepared database to the output instead of downloading.
class _FakeDownloader extends AttachedUpdateDownloader {
  String? source;
  Future<void> Function(AttachedUpdateCancelToken? cancel)? hold;
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
    await hold?.call(cancel);
    await File(source!).copy(outputPath);
  }
}

class _FailBackupCleanup extends AttachedUpdateFileSwap {
  @override
  Future<void> discardBackup(String target) async {
    throw FileSystemException('backup cleanup failed', target);
  }
}

String _sha(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final zstd = openZstdForTests();
  late Directory temp;
  late AttachedLibraryRegistry registry;
  late AttachedLibrariesRepository repository;
  late _FakeFetcher fetcher;
  late _FakeDownloader downloader;
  late String privateKey;
  late String publicKey;
  late OfficialAttachedLibrary entry;
  var counter = 0;

  var now = DateTime(2026, 11, 21);
  late String dropDirectory;

  AttachedLibraryUpdateService service({
    Future<AttachedLibraryProbeResult> Function(String)? probe,
    AttachedUpdateFileSwap swap = const AttachedUpdateFileSwap(lockRetries: 1),
  }) => AttachedLibraryUpdateService(
    repository: repository,
    fetcher: fetcher,
    downloader: downloader,
    probe: probe ?? (path) async => AttachedLibraryProbe.probeSync(path),
    swap: swap,
    diskSpace: (_) async => DiskSpaceInfo(volumeId: 'V', freeBytes: 1 << 40),
    workDirectory: () async => p.join(temp.path, 'work'),
    isOfflineMode: () => false,
    areUpdatesEnabled: () => true,
    isAutoCheckDue: () => true,
    recordCheck: () async {},
    openZstd: () => openZstdForTests()!,
    now: () => now,
    dropDirectory: () async => dropDirectory,
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

  /// The signed manifest that a tagged release publishes for [db].
  ({Uint8List manifest, Uint8List signature}) signedRelease(
    String db, {
    required int version,
    String? signWith,
  }) {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(
          AttachedUpdateManifest(
            libraryId: _id,
            dbVersion: version,
            full: artifactOf(db, 'v$version'),
            deltas: const [],
          ).toJson(),
        ),
      ),
    );
    return (
      manifest: bytes,
      signature: Uint8List.fromList(
        ascii.encode(
          AttachedUpdateSignature.sign(bytes, signWith ?? privateKey),
        ),
      ),
    );
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
    now = DateTime(2026, 11, 21);
    dropDirectory = p.join(temp.path, 'drop');
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
      displayName: 'מחברי זמננו',
      manifestUrl: _url,
      publicKey: publicKey,
      releaseManifestUrlTemplate: '$_releasePrefix{version}/manifest.json',
      offlineName: 'zmanenu',
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
    expect(builtIn.displayName, 'מחברי זמננו');
    expect(
      builtIn.manifestUrl,
      'https://github.com/Otzaria/zmanenu-library/releases/latest/download/manifest.json',
    );
    expect(
      builtIn.releaseManifestUrlFor(3),
      'https://github.com/Otzaria/zmanenu-library/releases/download/v3/manifest.json',
    );
    expect(builtIn.offlinePackageName, 'zmanenu-offline.tar.zst');
    expect(builtIn.offlineDatabaseName, 'zmanenu.db');
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

      // A further manual copy is attached too, and marked as a duplicate.
      final again = await repository.importFile(database());
      expect(again.isOk, isTrue);
      expect(
        repository.libraries
            .singleWhere((l) => l.path == again.library!.path)
            .status,
        AttachedLibraryStatus.duplicateSlug,
      );
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
    expect(library.displayName, 'מחברי זמננו');
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

  /// Replaces the installed file behind the repository's back.
  Future<void> replaceOnDisk(String path, String replacement) async {
    await registry.closeAll();
    File(replacement).copySync(path);
    File(
      path,
    ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
  }

  group('a file that is exactly the signed release is adopted', () {
    test('after a crash between the swap and saving the record', () async {
      publish(database());
      final svc = service();
      final library = await installOfficial(svc);
      final next = database(version: '2');
      await replaceOnDisk(library.path, next);
      await repository.rescan();
      expect(repository.libraries.single.isOfficial, isFalse);

      publish(next, version: 2);
      final downloadsBefore = downloader.artifacts.length;
      await svc.runScheduledCheck();
      final adopted = repository.libraries.single;
      expect(svc.statusOf(adopted), const AttachedUpdateUpToDate());
      expect(downloader.artifacts.length, downloadsBefore);
      expect(adopted.isOfficial, isTrue);
      expect(
        adopted.official,
        AttachedOfficialInstall(
          libraryId: _id,
          dbVersion: 2,
          sha256: _sha(next),
        ),
      );
    });

    test('after a backup restore dropped the official mark', () async {
      publish(database());
      final svc = service();
      final library = await installOfficial(svc);
      const store = AttachedLibraryStore();
      await store.forgetUpdatePins();
      registry.update(store.loadLibrariesOrNull()!);
      await repository.rescan();
      expect(repository.libraries.single.official, isNull);
      expect(
        AttachedLibraryUpdateService.notInstalledOfficial(repository.libraries),
        [entry],
      );

      final downloadsBefore = downloader.artifacts.length;
      await installOfficial(svc);
      expect(downloader.artifacts.length, downloadsBefore);
      final adopted = repository.libraries.single;
      expect(adopted.path, library.path);
      expect(adopted.official, library.official);
    });

    test('but not a file that differs from it', () async {
      publish(database());
      final svc = service();
      final library = await installOfficial(svc);
      final other = database(version: '2');
      final db = sqlite3.sqlite3.open(other);
      db.execute('CREATE TABLE tampered (x INTEGER)');
      db.close();
      await replaceOnDisk(library.path, other);
      await repository.rescan();

      publish(database(version: '2'), version: 2);
      expect(
        await svc.adoptIfSignedMatch(
          library.path,
          (await svc.check(
            repository.libraries.single,
          )).offer!,
        ),
        isNull,
      );
      expect(repository.libraries.single.isOfficial, isFalse);
    });
  });

  test('a full download never installs an older release', () async {
    final installed = database(version: '2');
    publish(installed, version: 2);
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

    // A replayed, still validly signed, older manifest.
    publish(database(), version: 1);
    await svc.runScheduledCheck();
    final current = repository.libraries.single;
    expect(svc.statusOf(current).offer!.dbVersion, 1);
    final downloadsBefore = downloader.artifacts.length;
    await svc.install(current, forceFull: true);
    expect(
      svc.statusOf(current),
      isA<AttachedUpdateFailed>().having(
        (f) => f.error,
        'error',
        AttachedUpdateError.notApplicable,
      ),
    );
    expect(downloader.artifacts.length, downloadsBefore);
    expect(repository.libraries.single.fingerprint!.dbVersion, '2');
  });

  test('removing a library stops its running update and clears it', () async {
    final library = (await repository.importFile(database())).library!;
    publish(database(version: '2'), version: 2);
    final svc = service();
    expect(await svc.check(library), isA<AttachedUpdateAvailable>());
    final started = Completer<void>();
    downloader.hold = (cancel) async {
      started.complete();
      while (!cancel!.isCancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      throw const AttachedUpdateCancelled();
    };
    final bloc = AttachedLibrariesBloc(
      addLibraryEvent: (_) {},
      repository: repository,
      updates: svc,
    );
    addTearDown(bloc.close);
    final installing = svc.install(library);
    await started.future;
    expect(svc.statusOf(library).isRunning, isTrue);

    bloc.add(RemoveAttachedLibrary(library));
    await installing;
    expect(repository.libraries, isEmpty);
    expect(svc.statuses.value.containsKey(library.path), isFalse);
    expect(
      Settings.getValue<String>(
            SettingsRepository.keyAttachedLibraryPendingUpdates,
          ) ??
          '',
      isNot(contains(jsonEncode(library.path).replaceAll('"', ''))),
    );
  });

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

  group('a manually attached copy of a published release is identified', () {
    test('a byte-identical copy is adopted and then updates itself, '
        'without writing to the user\'s file', () async {
      final manual = database();
      fetcher.releases[1] = signedRelease(manual, version: 1);
      final userSha = _sha(manual);
      final attached = (await repository.importFile(manual)).library!;
      expect(attached.mode, AttachedLibraryMode.link);
      expect(attached.isOfficial, isFalse);

      final svc = service();
      await svc.adoptManualCopies();
      expect(fetcher.urls, ['${_releasePrefix}1/manifest.json']);
      final adopted = repository.libraries.single;
      expect(adopted.path, manual);
      expect(adopted.isOfficial, isTrue);
      expect(adopted.official!.sha256, userSha);

      // A newer release is installed unasked, as a managed copy.
      final next = database(version: '2');
      publish(next, version: 2);
      await svc.runScheduledCheck();
      final managed = repository.libraries.singleWhere((l) => l.isOk);
      expect(managed.isOfficial, isTrue);
      expect(managed.mode, AttachedLibraryMode.copy);
      expect(managed.path, await repository.officialPathFor(_id));
      expect(managed.fingerprint!.dbVersion, '2');
      expect(managed.priority, adopted.priority);
      expect(svc.statusOf(managed), const AttachedUpdateInstalled(2));
      final old = repository.libraries.singleWhere((l) => l.path == manual);
      expect(old.official, isNull);
      expect(old.status, AttachedLibraryStatus.duplicateSlug);
      expect(_sha(manual), userSha);
    });

    test('a changed copy is not adopted, and is retried only when the file '
        'changes or after a week', () async {
      final manual = database();
      fetcher.releases[1] = signedRelease(database(), version: 1);
      final db = sqlite3.sqlite3.open(manual);
      db.execute('CREATE TABLE edited (x INTEGER)');
      db.close();
      await repository.importFile(manual);

      final svc = service();
      await svc.adoptManualCopies();
      expect(repository.libraries.single.isOfficial, isFalse);
      expect(
        svc.statusOf(repository.libraries.single),
        isA<AttachedUpdateIdle>(),
      );
      expect(fetcher.urls, hasLength(1));

      await svc.adoptManualCopies();
      now = now.add(const Duration(days: 6));
      await service().adoptManualCopies();
      expect(fetcher.urls, hasLength(1));

      now = now.add(const Duration(days: 2));
      await service().adoptManualCopies();
      expect(fetcher.urls, hasLength(2));
      expect(repository.libraries.single.isOfficial, isFalse);
    });

    test('a version without a release (404) stays a regular database, '
        'and a network failure is retried next time', () async {
      final manual = database(version: '7');
      await repository.importFile(manual);

      fetcher.offline = true;
      await service().adoptManualCopies();
      fetcher.offline = false;
      await service().adoptManualCopies();
      expect(fetcher.urls, [
        '${_releasePrefix}7/manifest.json',
        '${_releasePrefix}7/manifest.json',
      ]);
      final library = repository.libraries.single;
      expect(library.isOfficial, isFalse);
      expect(library.isOk, isTrue);

      // The 404 was recorded: no request until the week has passed.
      await service().adoptManualCopies();
      expect(fetcher.urls, hasLength(2));
    });

    test('nothing is fetched in offline mode', () async {
      await repository.importFile(database());
      await AttachedLibraryUpdateService(
        repository: repository,
        fetcher: fetcher,
        isOfflineMode: () => true,
      ).adoptManualCopies();
      expect(fetcher.urls, isEmpty);
    });

    test(
      'two copies: the verified one is active, then the managed one',
      () async {
        final published = database();
        publish(published);
        final svc = service();
        final managed = await installOfficial(svc);

        // Same release attached by hand: attached, but inactive and untouched.
        final manualPath = p.join(temp.path, 'manual', 'zmanenu.db');
        File(manualPath)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(File(published).readAsBytesSync());
        final manual = (await repository.importFile(manualPath)).library!;
        fetcher.releases[1] = signedRelease(published, version: 1);
        await svc.adoptManualCopies();
        expect(
          fetcher.urls.where((u) => u.startsWith(_releasePrefix)),
          isEmpty,
        );
        AttachedLibrary byPath(String path) =>
            repository.libraries.singleWhere((l) => l.path == path);
        expect(byPath(manual.path).status, AttachedLibraryStatus.duplicateSlug);
        expect(byPath(managed.path).isOk, isTrue);

        // The managed copy changes on disk: the verified manual copy wins.
        await registry.closeAll();
        final db = sqlite3.sqlite3.open(managed.path);
        db.execute('CREATE TABLE edited (x INTEGER)');
        db.close();
        File(managed.path).setLastModifiedSync(
          DateTime.now().add(const Duration(minutes: 1)),
        );
        await repository.rescan();
        expect(byPath(managed.path).isOfficial, isFalse);
        await svc.adoptManualCopies();
        expect(byPath(manual.path).isOfficial, isTrue);
        expect(byPath(manual.path).isOk, isTrue);
        expect(
          byPath(managed.path).status,
          AttachedLibraryStatus.duplicateSlug,
        );
      },
    );
  });

  group('offline package', skip: zstd == null ? 'no libzstd' : null, () {
    /// `zmanenu-offline.tar.zst` with [db] and a manifest signed by
    /// [signWith]: one file, or [split] into parts with a parts manifest.
    /// Returns the file a user would pick ([pick]: part-000 or manifest).
    String package(
      String db, {
      int version = 1,
      String? signWith,
      String? manifestOf,
      String? folder,
      bool split = false,
      String pick = 'part-000',
    }) {
      const name = 'zmanenu-offline.tar.zst';
      final signed = signedRelease(
        manifestOf ?? db,
        version: version,
        signWith: signWith,
      );
      final archive = zstdCompress(
        zstd!,
        buildTar({
          'zmanenu.db': File(db).readAsBytesSync(),
          'manifest.json': signed.manifest,
          'manifest.json.sig': signed.signature,
        }),
      );
      final dir = Directory(folder ?? p.join(temp.path, 'pkg${counter++}'))
        ..createSync(recursive: true);
      if (!split) {
        final path = p.join(dir.path, name);
        File(path).writeAsBytesSync(archive);
        return path;
      }
      writeSplitAsset(dir, name, archive, partSize: archive.length ~/ 3 + 1);
      return p.join(
        dir.path,
        pick == 'manifest' ? '$name.manifest.json' : '$name.$pick',
      );
    }

    /// A database of [version] whose content differs from [database]'s.
    String different({String version = '1'}) {
      final path = database(version: version);
      final db = sqlite3.sqlite3.open(path);
      db.execute('CREATE TABLE other (x INTEGER)');
      db.close();
      return path;
    }

    test(
      'a valid single-file package installs a verified managed copy',
      () async {
        final db = database(version: '3');
        final svc = service();
        expect(
          await svc.importOfflinePackage(package(db, version: 3)),
          OfficialPackageResult.installed,
        );
        final library = repository.libraries.single;
        expect(library.isOfficial, isTrue);
        expect(library.mode, AttachedLibraryMode.copy);
        expect(library.path, await repository.officialPathFor(_id));
        expect(library.official!.dbVersion, 3);
        expect(_sha(library.path), _sha(db));
        expect(fetcher.urls, isEmpty);
        expect(downloader.artifacts, isEmpty);

        // The same package again changes nothing.
        expect(
          await svc.importOfflinePackage(package(db, version: 3)),
          OfficialPackageResult.alreadyInstalled,
        );
      },
    );

    test(
      'a restored registry does not let an older signed package replace its database',
      () async {
        final svc = service();
        final version3 = database(version: '3');
        expect(
          await svc.importOfflinePackage(package(version3, version: 3)),
          OfficialPackageResult.installed,
        );
        final previous = repository.libraries.single;
        await repository.setHidden(previous, true);
        const store = AttachedLibraryStore();
        await store.forgetUpdatePins();
        registry.update(store.loadLibrariesOrNull()!);
        await repository.rescan();
        expect(repository.libraries.single.official, isNull);
        final older = package(database());
        final result = await svc.importOfflinePackage(older);
        expect(
          (
            result,
            repository.libraries.single.fingerprint?.dbVersion,
            repository.libraries.single.hidden,
            _sha(previous.path),
          ),
          (OfficialPackageResult.olderVersion, '3', true, _sha(version3)),
        );
      },
    );

    test(
      'a failed official replacement preserves the existing database',
      () async {
        final svc = service();
        final db = database(version: '3');
        await svc.importOfflinePackage(package(db, version: 3));
        final previous = repository.libraries.single;
        const store = AttachedLibraryStore();
        await store.forgetUpdatePins();
        registry.update(store.loadLibrariesOrNull()!);
        await repository.rescan();
        final incoming = database(version: '4');
        await expectLater(
          repository.installOfficial(
            incoming,
            official: AttachedOfficialInstall(
              libraryId: _id,
              dbVersion: 4,
              sha256: _sha(incoming),
            ),
            accept: (_) => false,
          ),
          throwsA(isA<AttachedUpdateVerificationFailed>()),
        );
        expect(File(previous.path).existsSync(), isTrue);
        expect(_sha(previous.path), _sha(db));
      },
    );

    test('the drop location can restore a missing managed database', () async {
      final svc = service();
      final db = database(version: '3');
      await svc.importOfflinePackage(package(db, version: 3));
      final previous = repository.libraries.single;
      File(previous.path).deleteSync();
      await repository.rescan();
      expect(
        repository.libraries.single.status,
        AttachedLibraryStatus.unreachable,
      );
      package(db, version: 3, folder: dropDirectory);
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.installed,
      });
      expect(File(previous.path).existsSync(), isTrue);
    });

    test(
      'an explicit whole package can be picked beside a rejected split package',
      () async {
        final svc = service();
        package(
          database(),
          folder: dropDirectory,
          split: true,
          manifestOf: different(),
        );
        expect(await svc.importDroppedPackages(), {
          entry: OfficialPackageResult.hashMismatch,
        });
        final next = database(version: '2');
        final whole = package(next, version: 2, folder: dropDirectory);
        expect(
          await svc.importOfflinePackage(whole),
          OfficialPackageResult.installed,
        );
        expect(repository.libraries.single.official!.dbVersion, 2);
        expect(File(whole).existsSync(), isTrue);
      },
    );

    test(
      'an explicit split package can be picked beside a whole package',
      () async {
        final svc = service();
        package(database(), folder: dropDirectory);
        final next = database(version: '2');
        final part = package(
          next,
          version: 2,
          folder: dropDirectory,
          split: true,
        );
        expect(
          await svc.importOfflinePackage(part),
          OfficialPackageResult.installed,
        );
        expect(repository.libraries.single.official!.dbVersion, 2);
      },
    );

    test(
      'drop collection deletes only the parts named by the selected manifest',
      () async {
        final svc = service();
        final part = package(database(), folder: dropDirectory, split: true);
        final extra = File(part.replaceFirst('.part-000', '.part-999'));
        extra.writeAsStringSync('unused');
        expect(await svc.importDroppedPackages(), {
          entry: OfficialPackageResult.installed,
        });
        expect(Directory(dropDirectory).listSync().map((file) => file.path), [
          extra.path,
        ]);
      },
    );

    test(
      'drop collection keeps a whole package replaced during installation',
      () async {
        final oldPackage = package(database(), folder: dropDirectory);
        final next = package(database(version: '2'), version: 2);
        final svc = service(
          probe: (path) async {
            if (path.endsWith('.update-new')) {
              File(next).copySync(oldPackage);
              File(
                oldPackage,
              ).setLastModifiedSync(now.add(const Duration(hours: 1)));
            }
            return AttachedLibraryProbe.probeSync(path);
          },
        );
        expect(await svc.importDroppedPackages(), {
          entry: OfficialPackageResult.installed,
        });
        expect(_sha(oldPackage), _sha(next));
        expect(repository.libraries.single.official!.dbVersion, 1);
      },
    );

    test(
      'crash recovery keeps a committed copy when backup cleanup failed',
      () async {
        final svc = service(swap: _FailBackupCleanup());
        await svc.importOfflinePackage(package(database()));
        final path = repository.libraries.single.path;
        final next = database(version: '2');
        expect(
          await svc.importOfflinePackage(package(next, version: 2)),
          OfficialPackageResult.installed,
        );
        final backup = File(AttachedUpdateFileSwap.backupPathFor(path));
        expect(backup.existsSync(), isTrue);
        registry.update(const AttachedLibraryStore().loadLibrariesOrNull()!);
        await repository.recoverInterruptedUpdates();
        expect(backup.existsSync(), isFalse);
        expect(_sha(path), _sha(next));
        expect(repository.libraries.single.official!.dbVersion, 2);
      },
    );

    for (final split in [false, true]) {
      test(
        'picked ${split ? 'split' : 'whole'} package reads only selected cache files',
        () async {
          const archiveName = 'zmanenu-offline.tar.zst';
          final svc = service();
          final db = database(version: '2');
          final source = package(db, version: 2, split: split);
          final files = Directory(
            p.dirname(source),
          ).listSync().whereType<File>();
          final picked = <String, String>{};
          for (final file in files) {
            final cache = await temp.createTemp('picker');
            final copy = await file.copy(p.join(cache.path, 'cached'));
            picked[p.basename(file.path)] = copy.path;
          }
          if (split) {
            const missing = '$archiveName.part-001';
            final partial = {...picked};
            final path = partial.remove(missing)!;
            final first = partial['$archiveName.part-000']!;
            await File(path).copy(p.join(p.dirname(first), missing));
            expect(
              await svc.importOfflinePackageFromFolder(
                SelectedPackageFolder(partial, displayName: archiveName),
                archiveName,
              ),
              OfficialPackageResult.notPackage,
            );
          }
          expect(
            await svc.importOfflinePackageFromFolder(
              SelectedPackageFolder(picked, displayName: archiveName),
              archiveName,
            ),
            OfficialPackageResult.installed,
          );
          expect(_sha(repository.libraries.single.path), _sha(db));
        },
      );
    }

    test('a newer package updates the installed copy in place', () async {
      final svc = service();
      await svc.importOfflinePackage(package(database()));
      final path = repository.libraries.single.path;
      final next = database(version: '2');
      expect(
        await svc.importOfflinePackage(package(next, version: 2)),
        OfficialPackageResult.installed,
      );
      expect(repository.libraries.single.path, path);
      expect(repository.libraries.single.official!.dbVersion, 2);
      expect(_sha(path), _sha(next));
    });

    test('a wrong signature, a wrong hash and an older version are '
        'rejected', () async {
      final svc = service();
      final other = AttachedUpdateSignature.generatePrivateKey();
      expect(
        await svc.importOfflinePackage(package(database(), signWith: other)),
        OfficialPackageResult.badSignature,
      );
      expect(
        await svc.importOfflinePackage(
          package(database(), manifestOf: different()),
        ),
        OfficialPackageResult.hashMismatch,
      );
      expect(repository.libraries, isEmpty);
      expect(
        Directory(p.dirname(await repository.officialPathFor(_id))).existsSync()
            ? Directory(
                p.dirname(await repository.officialPathFor(_id)),
              ).listSync()
            : const [],
        isEmpty,
      );

      await svc.importOfflinePackage(
        package(database(version: '2'), version: 2),
      );
      expect(
        await svc.importOfflinePackage(package(database())),
        OfficialPackageResult.olderVersion,
      );
      expect(repository.libraries.single.official!.dbVersion, 2);
      expect(
        await svc.importOfflinePackage(p.join(temp.path, 'missing.tar.zst')),
        OfficialPackageResult.notPackage,
      );
    });

    for (final pick in ['part-000', 'manifest']) {
      test('a split package installs when the user picks its $pick', () async {
        final db = database(version: '4');
        expect(
          await service().importOfflinePackage(
            package(db, version: 4, split: true, pick: pick),
          ),
          OfficialPackageResult.installed,
        );
        expect(repository.libraries.single.official!.dbVersion, 4);
        expect(_sha(repository.libraries.single.path), _sha(db));
      });
    }

    test(
      'a split package with a missing or corrupt part is rejected',
      () async {
        final svc = service();
        final first = package(database(), split: true);
        File('${first.substring(0, first.length - 3)}001').deleteSync();
        expect(
          await svc.importOfflinePackage(first),
          OfficialPackageResult.notPackage,
        );
        final second = package(database(), split: true);
        final part = File('${second.substring(0, second.length - 3)}002');
        final bytes = part.readAsBytesSync();
        bytes[bytes.length - 1] ^= 0xff;
        part.writeAsBytesSync(bytes);
        expect(
          await svc.importOfflinePackage(second),
          OfficialPackageResult.notPackage,
        );
        expect(repository.libraries, isEmpty);
      },
    );

    test('the drop location: an installed package is deleted (both forms), '
        'a bad one stays', () async {
      package(database(), folder: dropDirectory, split: true);
      final svc = service();
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.installed,
      });
      expect(Directory(dropDirectory).listSync(), isEmpty);
      expect(repository.libraries.single.isOfficial, isTrue);

      final bad = package(
        database(version: '2'),
        version: 2,
        manifestOf: different(version: '2'),
        folder: dropDirectory,
      );
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.hashMismatch,
      });
      expect(File(bad).existsSync(), isTrue);
      expect(repository.libraries.single.official!.dbVersion, 1);

      File(bad).deleteSync();
      final next = database(version: '3');
      package(next, version: 3, folder: dropDirectory);
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.installed,
      });
      expect(Directory(dropDirectory).listSync(), isEmpty);
      expect(repository.libraries.single.official!.dbVersion, 3);
    });

    test('a rejected dropped package is unpacked and reported once, until '
        'it changes; an older one is deleted', () async {
      final svc = service();
      final bad = package(
        database(),
        manifestOf: different(),
        folder: dropDirectory,
      );
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.hashMismatch,
      });
      expect(await svc.importDroppedPackages(), isEmpty);
      expect(await svc.importDroppedPackages(), isEmpty);
      expect(File(bad).existsSync(), isTrue);

      File(bad).setLastModifiedSync(DateTime(2020));
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.hashMismatch,
      });
      File(bad).deleteSync();

      await svc.importOfflinePackage(
        package(database(version: '2'), version: 2),
      );
      final older = package(database(), folder: dropDirectory);
      expect(await svc.importDroppedPackages(), {
        entry: OfficialPackageResult.olderVersion,
      });
      expect(File(older).existsSync(), isFalse);
    });

    test(
      'unpack folders left by a crash are deleted on the next import',
      () async {
        final leftover = Directory(
          p.join(
            p.dirname(await repository.officialPathFor(_id)),
            '.offline-1',
          ),
        )..createSync(recursive: true);
        File(p.join(leftover.path, 'zmanenu.db')).writeAsStringSync('x');
        expect(
          await service().importOfflinePackage(package(database())),
          OfficialPackageResult.installed,
        );
        expect(leftover.existsSync(), isFalse);
      },
    );

    test('an offline import waits for a running official download', () async {
      publish(database());
      final svc = service();
      await svc.checkOfficialOffers();
      final started = Completer<void>();
      final release = Completer<void>();
      downloader.hold = (_) async {
        started.complete();
        await release.future;
      };
      final downloading = svc.installOfficial(entry);
      await started.future;
      final next = database(version: '2');
      var imported = false;
      final importing = svc
          .importOfflinePackage(package(next, version: 2))
          .whenComplete(() => imported = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(imported, isFalse);

      release.complete();
      await downloading;
      expect(await importing, OfficialPackageResult.installed);
      expect(repository.libraries.single.official!.dbVersion, 2);
      expect(_sha(repository.libraries.single.path), _sha(next));
    });

    test(
      'the default drop location is in the attached databases folder',
      () async {
        AppPaths.debugOverrideDataRootPath(temp.path);
        try {
          expect(
            await AttachedLibraryUpdateService.defaultDropDirectory(),
            p.join(temp.path, 'מסדים אישיים', 'להתקנה'),
          );
        } finally {
          AppPaths.debugOverrideDataRootPath(null);
        }
      },
    );
  });
}
