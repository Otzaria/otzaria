import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_planner.dart';
import 'package:path/path.dart' as p;

AttachedUpdateArtifact _artifact({
  required AttachedUpdateCompression compression,
  required int size,
  required String sha256,
  required int downloadSize,
  String url = 'https://updates.example.org/lib/part',
}) => AttachedUpdateArtifact(
  compression: compression,
  size: size,
  sha256: sha256,
  parts: [AttachedUpdatePart(url: url, size: downloadSize, sha256: sha256)],
);

void main() {
  late Directory temp;
  late String installed;
  late String installedSha256;

  setUp(() async {
    AttachedUpdateArtifactPlanner.clearCacheForTesting();
    temp = await Directory.systemTemp.createTemp('otzaria_delta_plan');
    installed = p.join(temp.path, 'lib.db');
    final bytes = List<int>.generate(4096, (i) => i % 251);
    await File(installed).writeAsBytes(bytes);
    installedSha256 = sha256.convert(bytes).toString();
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  AttachedUpdateManifest manifest(List<AttachedUpdateDelta> deltas) =>
      AttachedUpdateManifest(
        libraryId: 'lib',
        dbVersion: 3,
        full: _artifact(
          compression: AttachedUpdateCompression.zstd,
          size: 9000,
          sha256: 'a' * 64,
          downloadSize: 5000,
        ),
        deltas: deltas,
      );

  AttachedUpdateDelta delta({
    int fromDbVersion = 2,
    String? fromSha256,
    int downloadSize = 1000,
    String url = 'https://updates.example.org/lib/patch',
  }) => AttachedUpdateDelta(
    fromDbVersion: fromDbVersion,
    fromSha256: fromSha256 ?? installedSha256,
    artifact: _artifact(
      compression: AttachedUpdateCompression.zstdPatch,
      size: 9000,
      sha256: 'a' * 64,
      downloadSize: downloadSize,
      url: url,
    ),
  );

  Future<AttachedUpdatePlan> planWith(
    List<AttachedUpdateDelta> deltas, {
    int? pointerSize,
    int maxBaseBytes = kMaxDeltaBaseBytes,
    Future<String> Function(String)? hashFile,
  }) {
    final planner = hashFile == null
        ? AttachedUpdateArtifactPlanner(
            pointerSize: pointerSize ?? 8,
            maxBaseBytes: maxBaseBytes,
          )
        : AttachedUpdateArtifactPlanner(
            pointerSize: pointerSize ?? 8,
            maxBaseBytes: maxBaseBytes,
            hashFile: hashFile,
          );
    return planner.plan(
      manifest(deltas),
      installedPath: installed,
      installedDbVersion: 2,
    );
  }

  test('picks the smallest applicable delta', () async {
    final small = delta(downloadSize: 700, url: 'https://x.example.org/small');
    final plan = await planWith([delta(downloadSize: 1500), small]);
    expect(plan.isDelta, isTrue);
    expect(plan.delta, same(small));
    expect(plan.artifact.compressedSize, 700);
  });

  test('selects a matching base instead of a smaller foreign delta', () async {
    final matching = delta(
      fromSha256: sha256
          .convert(await File(installed).readAsBytes())
          .toString(),
      downloadSize: 1500,
    );
    final foreign = delta(fromSha256: 'c' * 64, downloadSize: 100);
    final plan = await planWith([foreign, matching]);
    expect(plan.delta, same(matching));
  });

  test('a delta for another db_version is ignored', () async {
    final plan = await planWith([delta(fromDbVersion: 1)]);
    expect(plan.isDelta, isFalse);
    expect(plan.artifact.compressedSize, 5000);
  });

  test('a single candidate does not hash the installed file', () async {
    var calls = 0;
    final plan = await planWith(
      [
        delta(fromSha256: 'b' * 64),
        delta(fromDbVersion: 1),
        delta(downloadSize: 5000),
      ],
      hashFile: (_) async {
        calls++;
        throw StateError('the file must not be hashed');
      },
    );
    expect(plan.isDelta, isTrue);
    expect(calls, 0);
  });

  test('multiple candidates hash the installed file only once', () async {
    var calls = 0;
    final matching = delta(downloadSize: 700);
    final plan = await planWith(
      [delta(), delta(fromSha256: 'b' * 64, downloadSize: 100), matching],
      hashFile: (path) async {
        expect(path, installed);
        calls++;
        return installedSha256;
      },
    );
    expect(plan.delta, same(matching));
    expect(calls, 1);
  });

  test(
    'multiple candidates without a matching base fall back to full',
    () async {
      final plan = await planWith([
        delta(fromSha256: 'b' * 64),
        delta(fromSha256: 'c' * 64),
      ]);
      expect(plan.isDelta, isFalse);
    },
  );

  test('a hash failure falls back to the full artifact', () async {
    final plan = await planWith(
      [delta(), delta(downloadSize: 700)],
      hashFile: (_) async => throw const FileSystemException('read failed'),
    );
    expect(plan.isDelta, isFalse);
  });

  test(
    'a delta that is not smaller than the full download is ignored',
    () async {
      final plan = await planWith([delta(downloadSize: 5000)]);
      expect(plan.isDelta, isFalse);
    },
  );

  test('a 32-bit process never uses a delta', () async {
    final plan = await planWith([delta()], pointerSize: 4);
    expect(plan.isDelta, isFalse);
  });

  test('an installed file over the window ceiling is ignored', () async {
    final plan = await planWith([delta()], maxBaseBytes: 100);
    expect(plan.isDelta, isFalse);
  });

  test('a missing installed file falls back to the full artifact', () async {
    await File(installed).delete();
    final plan = await planWith([delta()]);
    expect(plan.isDelta, isFalse);
  });

  for (final change in ['size', 'modified', 'path']) {
    test('caches repeated plans and invalidates on $change', () async {
      var calls = 0;
      Future<String> hash(String path) async {
        calls++;
        return sha256.convert(await File(path).readAsBytes()).toString();
      }

      final candidates = [delta(), delta(fromSha256: 'c' * 64)];
      expect((await planWith(candidates, hashFile: hash)).isDelta, isTrue);
      expect((await planWith(candidates, hashFile: hash)).isDelta, isTrue);
      expect(calls, 1);
      final previous = await FileStat.stat(installed);
      switch (change) {
        case 'size':
          await File(installed).writeAsBytes([1, 2, 3]);
          await File(installed).setLastModified(previous.modified);
        case 'modified':
          await File(installed).writeAsBytes(List.filled(previous.size, 42));
          await File(
            installed,
          ).setLastModified(previous.modified.add(const Duration(seconds: 1)));
        case 'path':
          final copy = await File(
            installed,
          ).copy(p.join(temp.path, 'other.db'));
          await copy.setLastModified(previous.modified);
          installed = copy.path;
      }
      final expectedSha = sha256
          .convert(await File(installed).readAsBytes())
          .toString();
      final matching = delta(fromSha256: expectedSha);
      expect(
        (await planWith([
          matching,
          delta(fromSha256: 'c' * 64),
        ], hashFile: hash)).delta,
        same(matching),
      );
      expect(calls, 2);
    });
  }

  test('a failed hash is retried instead of cached', () async {
    var calls = 0;
    Future<String> hash(String _) async {
      if (++calls == 1) throw const FileSystemException('read failed');
      return installedSha256;
    }

    final candidates = [delta(), delta(fromSha256: 'c' * 64)];
    expect((await planWith(candidates, hashFile: hash)).isDelta, isFalse);
    expect((await planWith(candidates, hashFile: hash)).isDelta, isTrue);
    expect(calls, 2);
  });
}
