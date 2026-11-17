import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/managed_paths.dart';
import 'package:otzaria/update/differential/swap_plan.dart';
import 'package:otzaria/update/differential/update_engine.dart';
import 'package:otzaria/update/differential/update_package.dart';
import 'package:otzaria/update/differential/zstd_runner.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/generate_app_file_manifest.dart';
import '../../tool/release/generate_update_package.dart';

/// עץ התקנה סינתטי: ישן, חדש, וחבילת העדכון שביניהם.
class _Fixture {
  _Fixture(this.root);

  final Directory root;

  Directory get oldRoot => Directory(p.join(root.path, 'old'));
  Directory get newRoot => Directory(p.join(root.path, 'new'));
  File get package => File(p.join(root.path, 'package.zip'));

  /// חבילת הקבצים המלאים — הנסיגה של כל ערך שה-patch שלו אינו ישים.
  File get fullPackage => File(p.join(root.path, 'package-files.zip'));

  static const oldTag = '0.9.97+100';
  static const newTag = '0.9.97+101';

  late Map<String, Object?> oldManifest;
  late Map<String, Object?> newManifest;

  void build() {
    // תוכן חזרתי וגדול — patch עליו קטן משמעותית מהקובץ הדחוס המלא.
    final body = List.generate(
      4000,
      (i) => 'line $i of the otzaria binary\n',
    ).join();
    _write(oldRoot, 'otzaria.exe', utf8.encode('$body tail-old'));
    _write(newRoot, 'otzaria.exe', utf8.encode('$body tail-new'));

    // זהה בשתי הגרסאות — אמור להידלג לגמרי.
    final stable = utf8.encode('$body stable');
    _write(oldRoot, 'data/icudtl.dat', stable);
    _write(newRoot, 'data/icudtl.dat', stable);

    // אקראי ושונה לחלוטין — patch לא ישתלם, הערך ייארז כקובץ מלא.
    _write(oldRoot, 'config.bin', _randomBytes(8192, 1));
    _write(newRoot, 'config.bin', _randomBytes(8192, 2));

    // רק בחדש (קובץ מלא), ורק בישן (הסרה).
    _write(newRoot, 'data/added.txt', utf8.encode('a brand new asset'));
    _write(oldRoot, 'legacy.dll', utf8.encode('an obsolete library'));

    oldManifest = buildAppFileManifest(
      releaseTag: oldTag,
      releaseVersion: '0.9.97',
      platform: 'windows',
      architecture: 'x64',
      root: oldRoot,
    );
    newManifest = buildAppFileManifest(
      releaseTag: newTag,
      releaseVersion: '0.9.97',
      platform: 'windows',
      architecture: 'x64',
      root: newRoot,
    );
    buildUpdatePackage(
      oldManifest: oldManifest,
      oldRoot: oldRoot,
      newManifest: newManifest,
      newRoot: newRoot,
      output: package,
    );
    buildUpdatePackage(
      oldManifest: oldManifest,
      oldRoot: oldRoot,
      newManifest: newManifest,
      newRoot: newRoot,
      output: fullPackage,
      variant: UpdatePackageVariant.full,
    );
  }

  /// עותק טרי של ההתקנה הישנה, כמו אצל משתמש.
  Directory install(String name) {
    final copy = Directory(p.join(root.path, name));
    for (final entity in oldRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: oldRoot.path);
      final target = File(p.join(copy.path, relative));
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
    return copy;
  }

  static void _write(Directory root, String relative, List<int> bytes) {
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  static List<int> _randomBytes(int length, int seed) {
    final random = Random(seed);
    return List.generate(length, (_) => random.nextInt(256));
  }
}

Map<String, String> _hashTree(Directory root) {
  final hashes = <String, String>{};
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    hashes[p.relative(entity.path, from: root.path).replaceAll('\\', '/')] =
        sha256.convert(entity.readAsBytesSync()).toString();
  }
  return hashes;
}

DifferentialUpdateEngine _engine(
  Directory install,
  Directory work, {
  String platform = 'windows',
  String architecture = 'x64',
  String installedReleaseTag = _Fixture.oldTag,
}) => DifferentialUpdateEngine(
  installRoot: install,
  workRoot: work,
  platform: platform,
  architecture: architecture,
  installedReleaseTag: installedReleaseTag,
  // ברירת המחדל היא ה-zstd הארוז ליד קובץ ההרצה; בבדיקות משתמשים בזה
  // שב-PATH.
  zstd: const ZstdRunner(),
);

void main() {
  late Directory temp;
  late _Fixture fixture;
  final hasZstd = const Zstd().isAvailable;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('otzaria-update-engine');
    fixture = _Fixture(temp);
    if (hasZstd) fixture.build();
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Directory workDir() => Directory(p.join(temp.path, 'work'));

  group('תכנון העדכון', () {
    test('ארכיטקטורה שאינה תואמת עוצרת בלי לגעת בכלום', () async {
      final install = fixture.install('install');
      final before = _hashTree(install);
      final engine = _engine(install, workDir(), architecture: 'arm64');

      await expectLater(
        engine.prepare(fixture.package),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.targetMismatch,
          ),
        ),
      );
      expect(_hashTree(install), before);
      expect(engine.stagingRoot.existsSync(), isFalse);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('גרסת בסיס שאינה תואמת עוצרת בלי לגעת בכלום', () async {
      final install = fixture.install('install');
      final before = _hashTree(install);
      final engine = _engine(
        install,
        workDir(),
        installedReleaseTag: '0.9.96+1',
      );

      await expectLater(
        engine.prepare(fixture.package),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.baseVersionMismatch,
          ),
        ),
      );
      expect(_hashTree(install), before);
      expect(engine.stagingRoot.existsSync(), isFalse);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('קובץ שכבר בתוכן החדש נדלג — לא נפרס ולא מוחלף', () async {
      final install = fixture.install('install');
      File(p.join(fixture.newRoot.path, 'otzaria.exe')).copySync(
        p.join(install.path, 'otzaria.exe'),
      );
      final engine = _engine(install, workDir());
      final package = await UpdatePackage.open(fixture.package);
      final plan = await engine.planFor(package);

      final actions = {
        for (final step in plan.steps) step.entry.path: step.action,
      };
      expect(actions['otzaria.exe'], UpdateFileAction.alreadyUpToDate);
      expect(
        plan.work.map((s) => s.entry.path),
        isNot(contains('otzaria.exe')),
      );

      final staged = await engine.stage(package, plan);
      expect(staged.files.map((f) => f.path), isNot(contains('otzaria.exe')));
      expect(
        File(p.join(staged.stagingRoot.path, 'otzaria.exe')).existsSync(),
        isFalse,
      );
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('קובץ ששונה מקומית ושיש לו קובץ מלא — נכתב מהקובץ המלא', () async {
      final install = fixture.install('install');
      File(
        p.join(install.path, 'config.bin'),
      ).writeAsStringSync('the user replaced this file');
      final engine = _engine(install, workDir());
      final package = await UpdatePackage.open(fixture.package);
      final plan = await engine.planFor(package);

      final step = plan.steps.firstWhere((s) => s.entry.path == 'config.bin');
      expect(step.entry.isPatch, isFalse);
      expect(step.action, UpdateFileAction.writeFull);

      final staged = await engine.stage(package, plan);
      expect(
        sha256
            .convert(
              File(
                p.join(staged.stagingRoot.path, 'config.bin'),
              ).readAsBytesSync(),
            )
            .toString(),
        step.entry.newSha256,
      );
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('קובץ ששונה מקומית מסומן להשלמה מחבילת הקבצים המלאים', () async {
      final install = fixture.install('install');
      File(
        p.join(install.path, 'otzaria.exe'),
      ).writeAsStringSync('a locally modified binary');
      final engine = _engine(install, workDir());
      final plan = await engine.planFor(
        await UpdatePackage.open(fixture.package),
      );

      final actions = {
        for (final step in plan.steps) step.entry.path: step.action,
      };
      expect(actions['otzaria.exe'], UpdateFileAction.fromFallbackPackage);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('תכנון חוזר בודק את הקבצים מחדש ושומר על סדר המניפסט', () async {
      final install = fixture.install('install');
      final engine = _engine(install, workDir());
      final package = await UpdatePackage.open(fixture.package);
      final initialPlan = await engine.planFor(package);

      expect(
        initialPlan.steps.map((step) => step.entry),
        package.manifest.entries,
      );
      expect(initialPlan.steps.map((step) => step.action), [
        UpdateFileAction.writeFull,
        UpdateFileAction.writeFull,
        UpdateFileAction.applyPatch,
      ]);

      final newConfig = File(p.join(fixture.newRoot.path, 'config.bin'));
      newConfig.copySync(p.join(install.path, 'config.bin'));
      File(p.join(install.path, 'otzaria.exe')).deleteSync();
      final nextPlan = await engine.planFor(package);

      expect(
        nextPlan.steps.map((step) => step.entry),
        package.manifest.entries,
      );
      expect(nextPlan.steps.map((step) => step.action), [
        UpdateFileAction.alreadyUpToDate,
        UpdateFileAction.writeFull,
        UpdateFileAction.fromFallbackPackage,
      ]);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('תיקיית עבודה בתוך ההתקנה נדחית', () async {
      final install = fixture.install('install');
      final engine = _engine(install, Directory(p.join(install.path, 'work')));

      await expectLater(
        engine.prepare(fixture.package),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.environment,
          ),
        ),
      );
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);
  });

  group('נסיגה לחבילת הקבצים המלאים', () {
    test(
      'ערך שה-patch שלו אינו ישים מושלם מהחבילה המלאה והעדכון מצליח',
      () async {
        final install = fixture.install('install');
        File(
          p.join(install.path, 'otzaria.exe'),
        ).writeAsStringSync('a locally modified binary');
        final engine = _engine(install, workDir());

        var fetched = 0;
        final staged = await engine.prepare(
          fixture.package,
          fallbackPackage: () async {
            fetched++;
            return fixture.fullPackage;
          },
        );

        expect(fetched, 1);
        // התוצאה חייבת להיות זהה-בית לבנייה החדשה, גם בקובץ שנפל לנסיגה.
        final expected = _hashTree(fixture.newRoot);
        for (final file in staged.files) {
          expect(
            sha256
                .convert(
                  File(
                    p.join(staged.stagingRoot.path, file.path),
                  ).readAsBytesSync(),
                )
                .toString(),
            expected[file.path],
            reason: file.path,
          );
        }
        expect(
          staged.files.map((f) => f.path),
          contains('otzaria.exe'),
        );
      },
      skip: !hasZstd ? 'zstd is not on PATH' : null,
    );

    test('כשכל ה-patch מוחל — החבילה המלאה אינה מבוקשת כלל', () async {
      final install = fixture.install('install');
      final engine = _engine(install, workDir());

      var fetched = 0;
      await engine.prepare(
        fixture.package,
        fallbackPackage: () async {
          fetched++;
          return fixture.fullPackage;
        },
      );

      expect(fetched, 0);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test(
      'חבילה מלאה שאינה זמינה — נסיגה למתקין המלא בלי לגעת בהתקנה',
      () async {
        final install = fixture.install('install');
        final before = _hashTree(install);
        File(
          p.join(install.path, 'otzaria.exe'),
        ).writeAsStringSync('a locally modified binary');
        final after = _hashTree(install);
        final engine = _engine(install, workDir());

        await expectLater(
          engine.prepare(
            fixture.package,
            fallbackPackage: () async => throw const SocketException('offline'),
          ),
          throwsA(
            isA<DifferentialUpdateUnavailable>().having(
              (e) => e.reason,
              'reason',
              UpdateAbortReason.fallbackUnavailable,
            ),
          ),
        );
        // ההתקנה נשארה כפי שהייתה (כולל השינוי המקומי) והתוכן לא נגרע.
        expect(_hashTree(install), after);
        expect(before.keys, after.keys);
        expect(engine.stagingRoot.existsSync(), isFalse);
      },
      skip: !hasZstd ? 'zstd is not on PATH' : null,
    );

    test('חבילה מלאה של מעבר אחר נדחית', () async {
      final install = fixture.install('install');
      File(
        p.join(install.path, 'otzaria.exe'),
      ).writeAsStringSync('a locally modified binary');
      final engine = _engine(install, workDir());

      await expectLater(
        engine.prepare(
          fixture.package,
          // חבילת ה-patch עצמה אינה חבילת הקבצים המלאים.
          fallbackPackage: () async => fixture.package,
        ),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.fallbackUnavailable,
          ),
        ),
      );
      expect(engine.stagingRoot.existsSync(), isFalse);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);
  });

  group('zstd חסר', () {
    test('בנייה בלי zstd ארוז אינה זמינה ואינה כותבת דבר', () async {
      final install = fixture.install('install');
      final before = _hashTree(install);
      final engine = DifferentialUpdateEngine(
        installRoot: install,
        workRoot: workDir(),
        platform: 'windows',
        architecture: 'x64',
        installedReleaseTag: _Fixture.oldTag,
        zstd: ZstdRunner(
          executable: p.join(temp.path, 'no-such-zstd.exe'),
        ),
      );

      await expectLater(
        engine.prepare(fixture.package),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.environment,
          ),
        ),
      );
      expect(_hashTree(install), before);
      expect(engine.stagingRoot.existsSync(), isFalse);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('ARM64: אין zstd ארוז ליד קובץ ההרצה — אין זמינות', () async {
      // ה-CI מעתיק zstd.exe רק לבנייית x64; בבנייית ARM64 הוא נעדר,
      // ולכן המסלול מדווח שאינו זמין ואוצריא נשארת על המתקין המלא.
      final bundled = ZstdRunner.bundledZstdPath();
      if (Platform.isWindows && File(bundled).existsSync()) {
        return;
      }
      expect(await const ZstdRunner.bundled().isAvailable, isFalse);
    }, skip: !Platform.isWindows ? 'the bundled path is Windows-only' : null);
  });

  group('בניית ה-staging', () {
    test('כל קובץ שנבנה זהה-בית לבנייה החדשה', () async {
      final install = fixture.install('install');
      final engine = _engine(install, workDir());
      final staged = await engine.prepare(fixture.package);

      final expected = appFileManifestIndex(fixture.newManifest);
      for (final file in staged.files) {
        final produced = File(p.join(staged.stagingRoot.path, file.path));
        expect(produced.existsSync(), isTrue, reason: file.path);
        expect(
          sha256.convert(produced.readAsBytesSync()).toString(),
          expected[file.path]!['sha256'],
          reason: file.path,
        );
      }
      expect(
        staged.files.map((f) => f.path).toSet(),
        {'otzaria.exe', 'config.bin', 'data/added.txt'},
      );
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('ההתקנה החיה אינה נכתבת בשלב ההכנה', () async {
      final install = fixture.install('install');
      final before = _hashTree(install);
      final engine = _engine(install, workDir());
      final staged = await engine.prepare(fixture.package);

      expect(_hashTree(install), before);
      expect(p.isWithin(install.path, staged.stagingRoot.path), isFalse);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('payload פגום בלי חבילת נסיגה — העדכון נזנח', () async {
      final install = fixture.install('install');
      final before = _hashTree(install);
      final corrupted = File(p.join(temp.path, 'corrupted.zip'));
      corrupted.writeAsBytesSync(
        _corruptPayloads(fixture.package.readAsBytesSync()),
      );
      final engine = _engine(install, workDir());

      await expectLater(
        engine.prepare(corrupted),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.fallbackUnavailable,
          ),
        ),
      );
      expect(_hashTree(install), before);
      expect(engine.stagingRoot.existsSync(), isFalse);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('תוכנית ההחלפה מכילה רק את הקבצים שנבנו ואת ההסרות', () async {
      final install = fixture.install('install');
      final engine = _engine(install, workDir());
      final staged = await engine.prepare(fixture.package);
      // סימן מוויתור קודם אסור שיחזיר את הממשק ל"מוכן" מיד עם השיגור החדש.
      final staleGiveUp = File(
        p.join(staged.workRoot.path, kSwapGaveUpFileName),
      )..writeAsStringSync('');
      final planFile = await staged.writeSwapPlan(
        relaunchExecutable: p.join(install.path, 'otzaria.exe'),
        waitForPid: 4242,
      );
      expect(staleGiveUp.existsSync(), isFalse);

      final plan = SwapPlan.decode(planFile.readAsStringSync());
      expect(plan.removals.map((r) => r.path), ['legacy.dll']);
      expect(plan.files.map((f) => f.path).toSet(), {
        'otzaria.exe',
        'config.bin',
        'data/added.txt',
      });
      expect(plan.waitForPid, 4242);
      expect(plan.waitTimeout.inSeconds, greaterThan(0));
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);
  });

  group('קריאת החבילה מהדיסק', () {
    final payload = _Fixture._randomBytes(3 << 20, 7);

    File packageWith(Map<String, List<int>> files) {
      final archive = Archive();
      files.forEach(
        (name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)),
      );
      final file = File(p.join(temp.path, 'stream.zip'));
      file.writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      return file;
    }

    final manifestBytes = utf8.encode(jsonEncode(_fullManifest()));

    UpdatePackageEntry entryFor(String sha) => UpdatePackageEntry(
      path: 'otzaria.exe',
      method: 'full',
      compression: 'zstd',
      entryName: 'files/otzaria.exe.zst',
      entrySize: payload.length,
      entrySha256: sha,
      newSize: 1,
      newSha256: '0' * 64,
    );

    test('payload תקין נכתב לקובץ זהה-בית', () async {
      final package = await UpdatePackage.open(
        packageWith({
          kUpdatePackageManifestEntryName: manifestBytes,
          'files/otzaria.exe.zst': payload,
        }),
      );
      expect(package.manifest.kind, UpdatePackageKind.full);
      final out = File(p.join(temp.path, 'payload.bin'));
      await package.writePayloadTo(
        entryFor(sha256.convert(payload).toString()),
        out,
      );
      expect(out.readAsBytesSync(), payload);
    });

    test('payload שאינו תואם את ה-hash — packageCorrupt', () async {
      final package = await UpdatePackage.open(
        packageWith({
          kUpdatePackageManifestEntryName: manifestBytes,
          'files/otzaria.exe.zst': payload,
        }),
      );
      await expectLater(
        package.writePayloadTo(
          entryFor('f' * 64),
          File(p.join(temp.path, 'payload.bin')),
        ),
        _throwsAbort(UpdateAbortReason.packageCorrupt),
      );
    });

    test('payload חסר בחבילה — packageCorrupt', () async {
      final package = await UpdatePackage.open(
        packageWith({kUpdatePackageManifestEntryName: manifestBytes}),
      );
      await expectLater(
        package.writePayloadTo(
          entryFor(sha256.convert(payload).toString()),
          File(p.join(temp.path, 'payload.bin')),
        ),
        _throwsAbort(UpdateAbortReason.packageCorrupt),
      );
    });

    test('קובץ שאינו ZIP או בלי מניפסט — packageInvalid', () async {
      final notZip = File(p.join(temp.path, 'not.zip'))
        ..writeAsBytesSync(payload);
      await expectLater(
        UpdatePackage.open(notZip),
        _throwsAbort(UpdateAbortReason.packageInvalid),
      );
      await expectLater(
        UpdatePackage.open(packageWith({'files/otzaria.exe.zst': payload})),
        _throwsAbort(UpdateAbortReason.packageInvalid),
      );
    });
  });

  group('הגנת נתוני המשתמש', () {
    test('נתיב של נתוני משתמש נדחה כקובץ מנוהל', () {
      for (final path in const [
        'otzaria_data/settings.hive',
        'books/seforim.db',
        'index/meta.json',
        'databases/cache.db',
        'backups/latest.zip',
        'library_path.txt',
        'portable.marker',
      ]) {
        expect(isUserDataPath(path), isTrue, reason: path);
        expect(managedApplicationPathError(path), isNotNull, reason: path);
      }
      for (final path in const ['otzaria.exe', 'data/icudtl.dat']) {
        expect(managedApplicationPathError(path), isNull, reason: path);
      }
    });

    test('הסרה של נתיב נתוני משתמש מפילה את קריאת המניפסט', () {
      final manifest = jsonDecode(
        jsonEncode(_manifestWithRemoval('otzaria_data/settings.hive')),
      );
      expect(
        () => UpdatePackageManifest.fromJson(manifest),
        throwsA(
          isA<DifferentialUpdateUnavailable>().having(
            (e) => e.reason,
            'reason',
            UpdateAbortReason.packageInvalid,
          ),
        ),
      );
    });

    test('נתיב שבורח משורש ההתקנה נדחה', () {
      expect(
        () => UpdatePackageManifest.fromJson(
          jsonDecode(jsonEncode(_manifestWithRemoval('../otzaria.exe'))),
        ),
        throwsA(isA<DifferentialUpdateUnavailable>()),
      );
    });
  });
}

Map<String, Object?> _manifestWithRemoval(String path) => {
  'schemaVersion': 1,
  'platform': 'windows',
  'architecture': 'x64',
  'fromReleaseTag': 'a',
  'fromReleaseVersion': 'a',
  'toReleaseTag': 'b',
  'toReleaseVersion': 'b',
  'payloadSize': 0,
  'entries': const [],
  'removals': [
    {'path': path, 'oldSha256': '0' * 64, 'oldSize': 1},
  ],
};

/// משנה בית אחד בכל payload של החבילה.
List<int> _corruptPayloads(List<int> zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final rebuilt = Archive();
  for (final file in archive) {
    final bytes = List<int>.from(file.readBytes()!);
    if (file.name.startsWith('files/')) bytes[bytes.length ~/ 2] ^= 0xFF;
    rebuilt.addFile(ArchiveFile.noCompress(file.name, bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(rebuilt);
}

Map<String, Object?> _fullManifest() => {
  'schemaVersion': 1,
  'variant': 'full',
  'platform': 'windows',
  'architecture': 'x64',
  'fromReleaseTag': 'a',
  'fromReleaseVersion': 'a',
  'toReleaseTag': 'b',
  'toReleaseVersion': 'b',
  'payloadSize': 0,
  'entries': const [],
  'removals': const [],
};

Matcher _throwsAbort(UpdateAbortReason reason) => throwsA(
  isA<DifferentialUpdateUnavailable>().having(
    (e) => e.reason,
    'reason',
    reason,
  ),
);
