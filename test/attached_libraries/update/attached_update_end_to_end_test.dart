import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/models/attached_library_update_status.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_library_update_service.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_delta_applier.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_downloader.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_host_policy.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../../tool/src/personal_db_update_tool.dart';
import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _manifestUrl = 'https://updates.example.org/lib/manifest.json';

/// The zstd CLI and a libzstd for FFI, or null (the test is skipped).
({String exe, String lib})? _findZstd() {
  final which = Process.runSync(Platform.isWindows ? 'where' : 'which', [
    'zstd',
  ]);
  if (which.exitCode != 0) return null;
  final exe = (which.stdout as String).split(RegExp(r'[\r\n]+')).first.trim();
  final dir = p.dirname(File(exe).resolveSymbolicLinksSync());
  for (final candidate in [
    ?Platform.environment['LIBZSTD_PATH'],
    p.join(dir, 'dll', 'libzstd.dll'),
    p.join(dir, 'libzstd.dll'),
    'libzstd.so.1',
    'libzstd.so',
    '/opt/homebrew/lib/libzstd.dylib',
    '/usr/local/lib/libzstd.dylib',
  ]) {
    try {
      DynamicLibrary.open(candidate);
      return (exe: exe, lib: candidate);
    } catch (_) {}
  }
  return null;
}

// Top-level so the closure sent to the download isolate captures only a path.
AttachedUpdatePatchDecoder _patchWith(String lib) =>
    (patch, base, output, max, _) async => decodePatchSyncForTest(
      patch,
      base,
      output,
      DynamicLibrary.open(lib),
      maxOutputBytes: max,
    );

AttachedUpdateDecompressor _decompressWith(String lib) =>
    (archive, output, max) async => decompressSyncForTest(
      archive,
      output,
      DynamicLibrary.open(lib),
      maxOutputBytes: max,
    );

/// The real fetcher, with the published https URLs served from loopback.
class _LoopbackFetcher extends AttachedUpdateFetcher {
  _LoopbackFetcher(this.port)
    : super(policy: AttachedUpdateHostPolicy.allowLoopbackForTesting({port}));

  final int port;

  Uri _local(Uri uri) => Uri.parse(
    'http://127.0.0.1:$port/${uri.pathSegments.last}',
  );

  @override
  Future<Uint8List> fetchBytes(
    Uri uri, {
    required int maxBytes,
    AttachedUpdateCancelToken? cancel,
  }) => super.fetchBytes(_local(uri), maxBytes: maxBytes, cancel: cancel);

  @override
  Future<void> downloadParts(
    List<AttachedUpdatePart> parts,
    String targetPath, {
    void Function(int received, int total)? onProgress,
    AttachedUpdateCancelToken? cancel,
  }) => super.downloadParts(
    [
      for (final part in parts)
        AttachedUpdatePart(
          url: _local(Uri.parse(part.url)).toString(),
          size: part.size,
          sha256: part.sha256,
        ),
    ],
    targetPath,
    onProgress: onProgress,
    cancel: cancel,
  );
}

void main() {
  test(
    'zstd output larger than the declared size aborts as corrupt, output deleted',
    () async {
      final zstd = _findZstd();
      if (zstd == null) {
        markTestSkipped('zstd / libzstd not available');
        return;
      }
      final temp = await Directory.systemTemp.createTemp('otzaria_upd_bomb');
      try {
        // 8 MB of zeros packs to a few hundred bytes.
        final raw = p.join(temp.path, 'raw.db');
        File(raw).writeAsBytesSync(Uint8List(8 << 20));
        final archive = p.join(temp.path, 'combined.zst');
        final packed = Process.runSync(zstd.exe, [
          '-q',
          '-f',
          raw,
          '-o',
          archive,
        ]);
        expect(packed.exitCode, 0);
        File(raw).deleteSync();
        final output = p.join(temp.path, 'out.db');
        final builder = AttachedUpdateArtifactBuilder(
          decompress: _decompressWith(zstd.lib),
        );

        await expectLater(
          builder.build(
            AttachedUpdateArtifact(
              compression: AttachedUpdateCompression.zstd,
              size: 1000,
              sha256: '0' * 64,
              parts: const [],
            ),
            archive,
            output,
          ),
          throwsA(
            // "exceeds" = stopped while streaming, not the size check after.
            isA<AttachedUpdateArtifactMismatch>().having(
              (e) => e.message,
              'message',
              contains('exceeds'),
            ),
          ),
        );
        expect(File(output).existsSync(), isFalse);
      } finally {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    },
  );

  test(
    'signed, zstd, split manifest: download in the isolate and install',
    () async {
      final zstd = _findZstd();
      if (zstd == null) {
        markTestSkipped('zstd / libzstd not available');
        return;
      }
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final temp = await Directory.systemTemp.createTemp('otzaria_upd_e2e');
      final registry = AttachedLibraryRegistry(idleTimeout: null);
      HttpServer? server;
      try {
        final keyPath = p.join(temp.path, 'publisher.key');
        final publicKey = keygen(keyPath);

        String database(String version) {
          final dir = Directory(p.join(temp.path, 'v$version'))..createSync();
          final path = SeforimFixtureDb.create(
            dir,
            SeforimFixtureVariant.full,
          );
          final db = sqlite3.sqlite3.open(path);
          for (final entry in {
            'library_id': 'e2e-lib',
            'db_version': version,
            'update_manifest_url': _manifestUrl,
            'update_public_key': publicKey,
          }.entries) {
            db.execute('INSERT OR REPLACE INTO schema_meta VALUES (?, ?)', [
              entry.key,
              entry.value,
            ]);
          }
          // Incompressible, so the zstd archive really splits into parts.
          db.execute('CREATE TABLE e2e_filler (data BLOB)');
          db.execute('INSERT INTO e2e_filler VALUES (randomblob(60000))');
          db.close();
          return path;
        }

        final installed = p.join(temp.path, 'library', 'e2e.db');
        Directory(p.dirname(installed)).createSync();
        File(database('1')).copySync(installed);

        final outDir = p.join(temp.path, 'published');
        final packed = await pack(
          dbPath: database('2'),
          outDir: outDir,
          urlPrefix: 'https://updates.example.org/lib',
          partSize: 8192,
          level: 3,
          zstdExecutable: zstd.exe,
        );
        expect(packed.manifest.full.parts.length, greaterThanOrEqualTo(2));
        expect(
          packed.manifest.full.compression,
          AttachedUpdateCompression.zstd,
        );
        final signaturePath = sign(packed.manifestPath, keyPath);

        final served = <String>[];
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final name = request.uri.pathSegments.last;
          served.add(name);
          final file = File(switch (name) {
            'manifest.json' => packed.manifestPath,
            'manifest.json.sig' => signaturePath,
            _ => p.join(outDir, name),
          });
          if (!file.existsSync()) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.contentLength = file.lengthSync();
            await request.response.addStream(file.openRead());
          }
          await request.response.close();
        });

        final fetcher = _LoopbackFetcher(server.port);
        final repository = AttachedLibrariesRepository(
          registry: registry,
          probe: (path) async => AttachedLibraryProbe.probeSync(path),
          copyDirectory: () async => p.join(temp.path, 'copies'),
          copyByDefault: false,
        );
        final service = AttachedLibraryUpdateService(
          repository: repository,
          fetcher: fetcher,
          downloader: AttachedUpdateDownloader(
            fetcher: fetcher,
            builder: AttachedUpdateArtifactBuilder(
              decompress: _decompressWith(zstd.lib),
            ),
            certificates: () async => const [],
          ),
          probe: (path) async => AttachedLibraryProbe.probeSync(path),
          diskSpace: (_) async =>
              DiskSpaceInfo(volumeId: 'V', freeBytes: 1 << 40),
          workDirectory: () async => p.join(temp.path, 'work'),
          isOfflineMode: () => false,
          areUpdatesEnabled: () => true,
          isAutoCheckDue: () => true,
          recordCheck: () async {},
        );

        final attached = await repository.importFile(
          installed,
          mode: AttachedLibraryMode.link,
        );
        final library = attached.library!;
        expect(library.updateSource!.publicKey, publicKey);

        final found = await service.check(library);
        expect(found, isA<AttachedUpdateAvailable>());
        expect(found.offer!.dbVersion, 2);

        await service.install(library);
        expect(service.statusOf(library), const AttachedUpdateInstalled(2));
        expect(
          served,
          containsAll([
            'manifest.json',
            'manifest.json.sig',
            for (final part in packed.manifest.full.parts)
              Uri.parse(part.url).pathSegments.last,
          ]),
        );

        final probe = AttachedLibraryProbe.probeSync(installed);
        expect(probe.isOk, isTrue);
        expect(probe.fingerprint!.dbVersion, '2');
        final db = sqlite3.sqlite3.open(
          installed,
          mode: sqlite3.OpenMode.readOnly,
        );
        try {
          expect(
            db.select('SELECT COUNT(*) AS n FROM book').single['n'],
            greaterThan(0),
          );
        } finally {
          db.close();
        }
        expect(repository.libraries.single.fingerprint!.dbVersion, '2');
        expect(
          File(p.join(p.dirname(installed), 'e2e.db.bak-update')).existsSync(),
          isFalse,
        );
      } finally {
        await server?.close(force: true);
        await registry.closeAll();
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    },
  );

  for (final (multipleBases, foreignOnly, missingPatch, label) in [
    (false, false, false, 'a delta'),
    (true, false, false, 'multiple bases'),
    (true, true, false, 'a foreign delta'),
    (true, true, true, 'a missing foreign delta'),
  ]) {
    test(
      'signed manifest with $label: installs verified output',
      () async {
        final zstd = _findZstd();
        if (zstd == null) {
          markTestSkipped('zstd / libzstd not available');
          return;
        }
        await Settings.init(cacheProvider: MemoryCacheProvider());
        final temp = await Directory.systemTemp.createTemp('otzaria_upd_delta');
        final registry = AttachedLibraryRegistry(idleTimeout: null);
        HttpServer? server;
        try {
          final keyPath = p.join(temp.path, 'publisher.key');
          final publicKey = keygen(keyPath);

          final installed = p.join(temp.path, 'library', 'delta.db');
          Directory(p.dirname(installed)).createSync();
          final source = SeforimFixtureDb.create(
            Directory(p.join(temp.path, 'v1'))..createSync(),
            SeforimFixtureVariant.full,
          );
          File(source).copySync(installed);
          final base = sqlite3.sqlite3.open(installed);
          for (final entry in {
            'library_id': 'delta-lib',
            'db_version': '1',
            'update_manifest_url': _manifestUrl,
            'update_public_key': publicKey,
          }.entries) {
            base.execute('INSERT OR REPLACE INTO schema_meta VALUES (?, ?)', [
              entry.key,
              entry.value,
            ]);
          }
          base.execute('CREATE TABLE delta_filler (data BLOB)');
          base.execute('INSERT INTO delta_filler VALUES (randomblob(200000))');
          base.close();

          final repository = AttachedLibrariesRepository(
            registry: registry,
            probe: (path) async => AttachedLibraryProbe.probeSync(path),
            copyDirectory: () async => p.join(temp.path, 'copies'),
            copyByDefault: false,
          );
          final attached = await repository.importFile(
            installed,
            mode: AttachedLibraryMode.link,
          );
          final library = attached.library!;

          // הגרסה החדשה נגזרת מהקובץ המותקן, ולכן התיקון קטן מהקובץ המלא.
          final updated = p.join(temp.path, 'v2.db');
          File(installed).copySync(updated);
          final next = sqlite3.sqlite3.open(updated);
          next.execute(
            "UPDATE schema_meta SET value = '2' WHERE key = 'db_version'",
          );
          if (multipleBases) {
            next.execute(
              'UPDATE delta_filler SET data = randomblob(60000) || substr(data, 60001)',
            );
          }
          next.execute('CREATE TABLE delta_note (text TEXT)');
          next.execute("INSERT INTO delta_note VALUES ('v2')");
          next.close();

          final outDir = p.join(temp.path, 'published');
          final packed = await pack(
            dbPath: updated,
            outDir: outDir,
            urlPrefix: 'https://updates.example.org/lib',
            partSize: 8192,
            level: 3,
            zstdExecutable: zstd.exe,
            deltaFrom: [installed],
          );
          final delta = packed.manifest.deltas.single;
          expect(
            delta.artifact.compression,
            AttachedUpdateCompression.zstdPatch,
          );
          expect(
            delta.artifact.compressedSize,
            lessThan(packed.manifest.full.compressedSize),
          );
          final foreignNames = <String>[];
          if (multipleBases) {
            final foreignBase = p.join(temp.path, 'other-v1.db');
            File(updated).copySync(foreignBase);
            final other = sqlite3.sqlite3.open(foreignBase);
            other.execute(
              "UPDATE schema_meta SET value = '1' WHERE key = 'db_version'",
            );
            other.close();
            final foreignDir = p.join(temp.path, 'published-foreign');
            final foreignPack = await pack(
              dbPath: updated,
              outDir: foreignDir,
              urlPrefix: 'https://updates.example.org/lib',
              partSize: 8192,
              level: 3,
              zstdExecutable: zstd.exe,
              deltaFrom: [foreignBase],
            );
            final foreign = foreignPack.manifest.deltas.single;
            final parts = <AttachedUpdatePart>[];
            for (final part in foreign.artifact.parts) {
              final name = Uri.parse(part.url).pathSegments.last;
              final renamed = 'foreign-$name';
              File(p.join(foreignDir, name)).copySync(p.join(outDir, renamed));
              foreignNames.add(renamed);
              parts.add(
                AttachedUpdatePart(
                  url: 'https://updates.example.org/lib/$renamed',
                  size: part.size,
                  sha256: part.sha256,
                ),
              );
            }
            expect(foreign.fromSha256, isNot(delta.fromSha256));
            expect(
              foreign.artifact.compressedSize,
              lessThan(delta.artifact.compressedSize),
            );
            final manifest = AttachedUpdateManifest(
              libraryId: packed.manifest.libraryId,
              dbVersion: packed.manifest.dbVersion,
              full: packed.manifest.full,
              deltas: [
                if (!foreignOnly) delta,
                AttachedUpdateDelta(
                  fromDbVersion: foreign.fromDbVersion,
                  fromSha256: foreign.fromSha256,
                  artifact: AttachedUpdateArtifact(
                    compression: foreign.artifact.compression,
                    size: foreign.artifact.size,
                    sha256: foreign.artifact.sha256,
                    parts: parts,
                  ),
                ),
              ],
            );
            File(
              packed.manifestPath,
            ).writeAsStringSync(jsonEncode(manifest.toJson()));
          }
          final signaturePath = sign(packed.manifestPath, keyPath);

          final served = <String>[];
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            final name = request.uri.pathSegments.last;
            served.add(name);
            final file = File(switch (name) {
              'manifest.json' => packed.manifestPath,
              'manifest.json.sig' => signaturePath,
              _ => p.join(outDir, name),
            });
            if (!file.existsSync() ||
                (missingPatch && foreignNames.contains(name))) {
              request.response.statusCode = HttpStatus.notFound;
            } else {
              request.response.contentLength = file.lengthSync();
              await request.response.addStream(file.openRead());
            }
            await request.response.close();
          });

          final fetcher = _LoopbackFetcher(server.port);
          var hashCalls = 0;
          final service = AttachedLibraryUpdateService(
            planner: AttachedUpdateArtifactPlanner(
              hashFile: (path) async {
                hashCalls++;
                return AttachedUpdateArtifactBuilder.sha256OfFile(path);
              },
            ),
            repository: repository,
            fetcher: fetcher,
            downloader: AttachedUpdateDownloader(
              fetcher: fetcher,
              deltaApplier: AttachedUpdateDeltaApplier(
                decodePatch: _patchWith(zstd.lib),
              ),
              builder: AttachedUpdateArtifactBuilder(
                decompress: _decompressWith(zstd.lib),
              ),
              certificates: () async => const [],
            ),
            probe: (path) async => AttachedLibraryProbe.probeSync(path),
            diskSpace: (_) async =>
                DiskSpaceInfo(volumeId: 'V', freeBytes: 1 << 40),
            workDirectory: () async => p.join(temp.path, 'work'),
            isOfflineMode: () => false,
            areUpdatesEnabled: () => true,
            isAutoCheckDue: () => true,
            recordCheck: () async {},
          );

          final found = await service.check(library);
          expect(found, isA<AttachedUpdateAvailable>());
          expect(
            found.offer!.downloadSize,
            foreignOnly
                ? AttachedUpdateManifest.parse(
                    File(packed.manifestPath).readAsBytesSync(),
                  ).deltas.single.artifact.compressedSize
                : delta.artifact.compressedSize,
          );

          await service.install(library);
          expect(service.statusOf(library), const AttachedUpdateInstalled(2));

          final deltaNames = [
            for (final part in delta.artifact.parts)
              Uri.parse(part.url).pathSegments.last,
          ];
          final fullNames = [
            for (final part in packed.manifest.full.parts)
              Uri.parse(part.url).pathSegments.last,
          ];
          expect(
            served,
            unorderedEquals([
              'manifest.json',
              'manifest.json.sig',
              if (foreignOnly) ...foreignNames else ...deltaNames,
              if (foreignOnly) ...fullNames,
            ]),
          );
          expect(hashCalls, multipleBases && !foreignOnly ? 1 : 0);
          if (!foreignOnly) {
            expect(served.where(foreignNames.contains), isEmpty);
            expect(
              served.where(fullNames.contains),
              isEmpty,
              reason: 'the full artifact must not be downloaded',
            );
          }
          expect(
            await AttachedUpdateArtifactBuilder.sha256OfFile(installed),
            packed.manifest.full.sha256,
          );
          expect(
            File(
              p.join(p.dirname(installed), 'delta.db.bak-update'),
            ).existsSync(),
            isFalse,
          );
          expect(
            AttachedLibraryProbe.probeSync(installed).fingerprint!.dbVersion,
            '2',
          );
        } finally {
          await server?.close(force: true);
          await registry.closeAll();
          try {
            await temp.delete(recursive: true);
          } catch (_) {}
        }
      },
    );
  }
}
