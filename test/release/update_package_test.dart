import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/generate_app_file_manifest.dart';
import '../../tool/release/generate_update_package.dart';

const _zstd = Zstd();

void main() {
  late Directory tmp;
  late Directory oldRoot;
  late Directory newRoot;
  late File output;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria-update-package');
    oldRoot = Directory('${tmp.path}/old')..createSync();
    newRoot = Directory('${tmp.path}/new')..createSync();
    output = File('${tmp.path}/package.zip');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void write(Directory root, String relative, List<int> bytes) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  /// גוף "בינארי" דחיס אך לא טריוויאלי, כך ש-patch באמת מוצא דמיון.
  List<int> body(int seed, int length) {
    final random = Random(seed);
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  Map<String, Object?> manifestOf(
    Directory root, {
    required String tag,
    String version = '0.9.97',
    String architecture = 'x64',
  }) => buildAppFileManifest(
    releaseTag: tag,
    releaseVersion: version,
    platform: 'windows',
    architecture: architecture,
    root: root,
  );

  UpdatePackageResult build({
    Map<String, Object?>? oldManifest,
    Map<String, Object?>? newManifest,
    double threshold = kPatchBenefitThreshold,
  }) => buildUpdatePackage(
    oldManifest: oldManifest ?? manifestOf(oldRoot, tag: '0.9.97+769'),
    oldRoot: oldRoot,
    newManifest: newManifest ?? manifestOf(newRoot, tag: '0.9.97+789'),
    newRoot: newRoot,
    output: output,
    threshold: threshold,
  );

  List<Map<String, Object?>> entriesOf(UpdatePackageResult result) =>
      (result.manifest['entries'] as List).cast<Map<String, Object?>>();

  Map<String, Object?> entryFor(UpdatePackageResult result, String path) =>
      entriesOf(result).firstWhere((e) => e['path'] == path);

  /// שני "בילדים" ריאליסטיים: קובץ שלא השתנה, קובץ שנערך, קובץ שנוסף,
  /// קובץ שהוסר, וקובץ עם שם עברי.
  void writeTwoBuilds() {
    final stable = body(1, 40000);
    write(oldRoot, 'pdfium.dll', stable);
    write(newRoot, 'pdfium.dll', stable);

    final edited = body(2, 120000);
    write(oldRoot, 'data/app.so', edited);
    write(newRoot, 'data/app.so', [
      ...edited.sublist(0, 60000),
      ...body(99, 400),
      ...edited.sublist(60000),
    ]);

    write(oldRoot, 'legacy_plugin.dll', body(3, 5000));
    write(newRoot, 'opentype_shaper.dll', body(4, 9000));

    final icon = body(5, 7000);
    write(oldRoot, 'data/flutter_assets/assets/icon/שמור וזכור.png', icon);
    write(newRoot, 'data/flutter_assets/assets/icon/שמור וזכור.png', icon);
  }

  group('בחירת patch מול קובץ מלא', () {
    test('הסף הוא 90% — רק patch שחוסך מעליו נבחר', () {
      expect(kPatchBenefitThreshold, 0.90);
      expect(shouldUsePatch(patchSize: 100, fullSize: 1000), isTrue);
      expect(shouldUsePatch(patchSize: 899, fullSize: 1000), isTrue);
      expect(shouldUsePatch(patchSize: 900, fullSize: 1000), isFalse);
      expect(shouldUsePatch(patchSize: 1200, fullSize: 1000), isFalse);
    });

    test('היחסים שנמדדו בפועל עוברים את הסף בנוחות', () {
      // 0.9.97+769 → 0.9.97+789, מתוך results.md.
      expect(
        shouldUsePatch(patchSize: 5199577, fullSize: 9492096),
        isTrue,
        reason: 'data/app.so — 55%, המקרה הגרוע שנמדד',
      );
      expect(shouldUsePatch(patchSize: 1195563, fullSize: 4451871), isTrue);
      expect(shouldUsePatch(patchSize: 10453, fullSize: 810721), isTrue);
    });
  });

  group('תוכן החבילה', () {
    setUp(writeTwoBuilds);

    test('רק קבצים ששונו ונוספו נכנסים; קובץ זהה מושמט', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final result = build();

      expect(
        entriesOf(result).map((e) => e['path']).toList()..sort(),
        ['data/app.so', 'opentype_shaper.dll'],
      );
      expect(result.unchangedFiles, 2);
      expect(entryFor(result, 'data/app.so')['method'], 'patch');
      expect(entryFor(result, 'opentype_shaper.dll')['method'], 'full');
      expect(validateUpdatePackageManifest(result.manifest), isEmpty);
    });

    test('קובץ שהוסר מיוצג כהסרה עם ה-hash הישן שלו', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final result = build();
      final removals = (result.manifest['removals'] as List).cast<Map>();

      expect(removals.map((r) => r['path']).toList(), ['legacy_plugin.dll']);
      expect(removals.single['oldSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(result.removedFiles, 1);
    });

    test('מידע של המשתמש אינו נארז ואינו ניתן למחיקה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      // קובץ שנוצר בזמן ריצה בשני העצים, ואינו במניפסט של אף גרסה.
      final oldManifest = manifestOf(oldRoot, tag: '0.9.97+769');
      final newManifest = manifestOf(newRoot, tag: '0.9.97+789');
      write(oldRoot, 'otzaria_data/settings.json', utf8.encode('{"a":1}'));
      write(newRoot, 'otzaria_data/settings.json', utf8.encode('{"a":1}'));
      write(oldRoot, 'errors.txt', utf8.encode('boom'));

      final result = build(
        oldManifest: oldManifest,
        newManifest: newManifest,
      );

      final touched = [
        ...entriesOf(result).map((e) => e['path']),
        ...(result.manifest['removals'] as List).map(
          (r) => (r as Map)['path'],
        ),
      ];
      expect(touched, isNot(contains('otzaria_data/settings.json')));
      expect(touched, isNot(contains('errors.txt')));
      // `errors.txt` קיים רק בעץ הישן — אילו היה מנוהל, הוא היה הסרה.
      expect(
        (result.manifest['removals'] as List).map((r) => (r as Map)['path']),
        ['legacy_plugin.dll'],
      );
    });

    test('ערך patch נושא hash ישן וחדש; ערך מלא נושא חדש בלבד', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final result = build();

      final patch = entryFor(result, 'data/app.so');
      expect(patch['oldSha256'], isA<String>());
      expect(
        patch['oldSize'],
        File('${oldRoot.path}/data/app.so').lengthSync(),
      );
      expect(patch['newSha256'], isA<String>());
      expect(patch['oldSha256'], isNot(patch['newSha256']));
      expect(patch['compression'], 'zstd-patch-from');

      final full = entryFor(result, 'opentype_shaper.dll');
      expect(full['oldSha256'], isNull);
      expect(full['compression'], 'zstd');
    });

    test('שמות ה-entry מספריים — שם עברי לא נכנס לארכיון', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final icon = body(5, 7000);
      write(newRoot, 'data/flutter_assets/assets/icon/שמור וזכור.png', [
        ...icon.sublist(0, 3000),
        ...body(7, 100),
        ...icon.sublist(3000),
      ]);
      final result = build();

      final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
      for (final file in archive.files) {
        expect(
          file.name,
          anyOf(
            kUpdateManifestEntryName,
            matches(RegExp(r'^files/[0-9]{4}\.bin$')),
          ),
        );
      }
      expect(
        entriesOf(result).map((e) => e['path']),
        contains('data/flutter_assets/assets/icon/שמור וזכור.png'),
      );
    });

    test('סף נמוך מאוד מכריח קובץ מלא במקום patch', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final permissive = build();
      expect(entryFor(permissive, 'data/app.so')['method'], 'patch');

      final strict = build(threshold: 0.0001);
      expect(entryFor(strict, 'data/app.so')['method'], 'full');
      expect(entryFor(strict, 'data/app.so')['oldSha256'], isNull);
      expect(strict.patchBytesSaved, 0);
    });

    test('שם הנכס נושא פלטפורמה, ארכיטקטורה ושני התגים', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      expect(
        build().assetName,
        'otzaria-update-windows-x64-0.9.97_769-to-0.9.97_789.zip',
      );
      expect(
        updatePackageAssetName(
          platform: 'windows',
          architecture: 'arm64',
          fromReleaseTag: '0.9.97+769',
          toReleaseTag: '0.9.97+789',
        ),
        'otzaria-update-windows-arm64-0.9.97_769-to-0.9.97_789.zip',
      );
    });
  });

  group('אי-התאמה נדחית', () {
    setUp(writeTwoBuilds);

    test('מניפסט x64 מול מניפסט arm64 אינו נבנה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      expect(
        () => build(
          newManifest: manifestOf(
            newRoot,
            tag: '0.9.97+789',
            architecture: 'arm64',
          ),
        ),
        throwsA(isA<AppFileManifestException>()),
      );
    });

    test('חבילת x64 אינה מוחלת על התקנת arm64', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      build();
      expect(
        () => applyUpdatePackage(
          package: output,
          root: oldRoot,
          platform: 'windows',
          architecture: 'arm64',
        ),
        throwsA(isA<UpdatePackageException>()),
      );
    });

    test('אותו תג בשני הצדדים נדחה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      expect(
        () => build(oldManifest: manifestOf(oldRoot, tag: '0.9.97+789')),
        throwsA(isA<UpdatePackageException>()),
      );
    });

    test('קובץ מקומי שאינו בסיס ה-patch מזוהה ואינו נכתב', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      build();

      final wrong = Directory('${tmp.path}/wrong')..createSync();
      _copyTree(oldRoot, wrong);
      final target = File('${wrong.path}/data/app.so');
      target.writeAsBytesSync(body(1234, 120000));
      final before = target.readAsBytesSync();

      expect(
        () => applyUpdatePackage(
          package: output,
          root: wrong,
          platform: 'windows',
          architecture: 'x64',
        ),
        throwsA(isA<UpdatePackageException>()),
      );
      expect(target.readAsBytesSync(), before);
    });

    test('חבילה פגומה נדחית לפני כתיבה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final result = build();
      final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
      final corrupted = Archive();
      for (final file in archive.files) {
        final bytes = file.readBytes()!;
        corrupted.addFile(
          file.name == entryFor(result, 'data/app.so')['entry']
              ? ArchiveFile.noCompress(file.name, bytes.length, [
                  bytes.first ^ 0xff,
                  ...bytes.skip(1),
                ])
              : ArchiveFile.noCompress(file.name, bytes.length, bytes),
        );
      }
      output.writeAsBytesSync(ZipEncoder().encodeBytes(corrupted));

      expect(
        () => applyUpdatePackage(
          package: output,
          root: oldRoot,
          platform: 'windows',
          architecture: 'x64',
        ),
        throwsA(isA<UpdatePackageException>()),
      );
    });
  });

  group('הלוך-ושוב', () {
    test('החלת החבילה על עותק של הישן מייצרת בדיוק את החדש', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      writeTwoBuilds();
      final newManifest = manifestOf(newRoot, tag: '0.9.97+789');
      build(newManifest: newManifest);

      final target = Directory('${tmp.path}/installed')..createSync();
      _copyTree(oldRoot, target);
      // מידע של המשתמש שיושב בתוך ההתקנה — חייב לשרוד את העדכון.
      write(target, 'otzaria_data/settings.json', utf8.encode('{"keep":1}'));

      applyUpdatePackage(
        package: output,
        root: target,
        platform: 'windows',
        architecture: 'x64',
      );

      for (final file in (newManifest['files'] as List).cast<Map>()) {
        final produced = File('${target.path}/${file['path']}');
        expect(produced.existsSync(), isTrue, reason: '${file['path']} חסר');
        expect(
          sha256.convert(produced.readAsBytesSync()).toString(),
          file['sha256'],
          reason: '${file['path']} אינו זהה לבנייה החדשה',
        );
      }
      expect(
        File('${target.path}/legacy_plugin.dll').existsSync(),
        isFalse,
        reason: 'קובץ שהוסר לא נמחק',
      );
      expect(
        File('${target.path}/otzaria_data/settings.json').readAsStringSync(),
        '{"keep":1}',
      );
    });

    test('קובץ מלא בלבד (בלי patch) גם הוא עושה הלוך-ושוב', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      writeTwoBuilds();
      final newManifest = manifestOf(newRoot, tag: '0.9.97+789');
      build(newManifest: newManifest, threshold: 0.0001);

      final target = Directory('${tmp.path}/installed2')..createSync();
      _copyTree(oldRoot, target);
      applyUpdatePackage(
        package: output,
        root: target,
        platform: 'windows',
        architecture: 'x64',
      );

      for (final file in (newManifest['files'] as List).cast<Map>()) {
        expect(
          sha256
              .convert(File('${target.path}/${file['path']}').readAsBytesSync())
              .toString(),
          file['sha256'],
        );
      }
    });
  });

  group('validateUpdatePackageManifest', () {
    setUp(writeTwoBuilds);

    test('הסרה של נתיב שגם נכתב נדחית', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final manifest = Map<String, Object?>.from(build().manifest);
      manifest['removals'] = [
        {'path': 'data/app.so', 'oldSize': 1, 'oldSha256': 'a' * 64},
      ];
      expect(validateUpdatePackageManifest(manifest), isNotEmpty);
    });

    test('נתיב מטפס בהסרה נדחה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final manifest = Map<String, Object?>.from(build().manifest);
      manifest['removals'] = [
        {'path': '../otzaria_data/settings.json', 'oldSha256': 'a' * 64},
      ];
      expect(validateUpdatePackageManifest(manifest), isNotEmpty);
    });

    test('patch בלי oldSha256 נדחה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final manifest = Map<String, Object?>.from(build().manifest);
      final entries = (manifest['entries'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();
      entries.firstWhere((e) => e['method'] == 'patch').remove('oldSha256');
      manifest['entries'] = entries;
      expect(validateUpdatePackageManifest(manifest), isNotEmpty);
    });

    test('גרסת סכמה גבוהה יותר נדחית', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final manifest = Map<String, Object?>.from(build().manifest);
      manifest['schemaVersion'] = 2;
      expect(validateUpdatePackageManifest(manifest), isNotEmpty);
    });
  });

  group('שתי חבילות לכל מעבר', () {
    setUp(writeTwoBuilds);

    test('חבילת ה-patch מצביעה על חבילת הקבצים המלאים שלה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final result = build();
      expect(result.manifest['variant'], 'patch');
      expect(
        result.manifest['fallbackAssetName'],
        updatePackageAssetName(
          platform: 'windows',
          architecture: 'x64',
          fromReleaseTag: '0.9.97+769',
          toReleaseTag: '0.9.97+789',
          variant: UpdatePackageVariant.full,
        ),
      );
      expect(result.assetName, endsWith('-to-0.9.97_789.zip'));
      expect(result.manifest['fallbackAssetName'], endsWith('-files.zip'));
    });

    test('חבילת הקבצים המלאים אינה מכילה patch כלל', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final result = buildUpdatePackage(
        oldManifest: manifestOf(oldRoot, tag: '0.9.97+769'),
        oldRoot: oldRoot,
        newManifest: manifestOf(newRoot, tag: '0.9.97+789'),
        newRoot: newRoot,
        output: output,
        variant: UpdatePackageVariant.full,
      );
      expect(result.patchedFiles, 0);
      expect(result.manifest['variant'], 'full');
      expect(result.manifest.containsKey('fallbackAssetName'), isFalse);
      for (final entry in entriesOf(result)) {
        expect(entry['method'], 'full');
        expect(entry['oldSha256'], isNull);
      }
      expect(validateUpdatePackageManifest(result.manifest), isEmpty);
    });

    test('החבילה המלאה גדולה מה-patch — היא הנסיגה ולא ברירת המחדל', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final patch = build();
      final full = buildUpdatePackage(
        oldManifest: manifestOf(oldRoot, tag: '0.9.97+769'),
        oldRoot: oldRoot,
        newManifest: manifestOf(newRoot, tag: '0.9.97+789'),
        newRoot: newRoot,
        output: File('${tmp.path}/full.zip'),
        variant: UpdatePackageVariant.full,
      );
      expect(full.packageSize, greaterThan(patch.packageSize));
    });

    test('מניפסט בלי variant נדחה', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final manifest = Map<String, Object?>.from(build().manifest);
      manifest.remove('variant');
      expect(validateUpdatePackageManifest(manifest), isNotEmpty);
    });

    test('חבילה מלאה שיש בה ערך patch נדחית', () {
      if (!_zstd.isAvailable) return _skipNoZstd();
      final manifest = Map<String, Object?>.from(build().manifest);
      manifest['variant'] = 'full';
      manifest.remove('fallbackAssetName');
      expect(validateUpdatePackageManifest(manifest), isNotEmpty);
    });
  });
}

void _skipNoZstd() {
  markTestSkipped('zstd אינו מותקן — בדיקת ה-patch אינה רצה במכונה הזאת');
}

void _copyTree(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path
        .substring(from.path.length + 1)
        .replaceAll('\\', '/');
    final target = File('${to.path}/$relative');
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(entity.readAsBytesSync());
  }
}
