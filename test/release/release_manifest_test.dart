import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/generate_release_manifest.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('otzaria-release-manifest');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void writeFile(String name, String content) {
    File('${dir.path}/$name').writeAsStringSync(content);
  }

  void writeJson(String name, Object value) {
    writeFile(name, jsonEncode(value));
  }

  String hex(int seed) => seed.toRadixString(16).padLeft(2, '0') * 32;

  /// קבצי release ריאליסטיים בנוסח 0.9.97 (בגודל מוקטן).
  void writeRealisticRelease({bool withFullInstaller = true}) {
    writeFile('otzaria-0.9.97-windows.exe', 'installer');
    writeFile('otzaria-0.9.97-windows_arm64.exe', 'installer-arm');
    writeFile('otzaria-windows.zip', 'portable');
    writeFile('otzaria-windows_arm64.zip', 'portable-arm');
    writeFile('otzaria-0.9.97-windows-full-indexed.exe', 'full-indexed');
    if (withFullInstaller) {
      writeFile('otzaria-0.9.97-windows-full.exe', 'full');
    }

    writeFile('otzaria-0.9.97-library-full-indexed.tar.zst.part-000', 'x' * 30);
    writeFile('otzaria-0.9.97-library-full-indexed.tar.zst.part-001', 'y' * 12);
    writeJson('otzaria-0.9.97-library-full-indexed.tar.zst.manifest.json', {
      'schemaVersion': 1,
      'archive': 'otzaria-0.9.97-library-full-indexed.tar.zst',
      'size': 42,
      'sha256': hex(0xab),
      'partSizeLimit': 1992294400,
      'githubAssetLimit': 2147483648,
      'parts': [
        {
          'name': 'otzaria-0.9.97-library-full-indexed.tar.zst.part-000',
          'size': 30,
          'sha256': hex(0x1a),
        },
        {
          'name': 'otzaria-0.9.97-library-full-indexed.tar.zst.part-001',
          'size': 12,
          'sha256': hex(0x2b),
        },
      ],
    });
  }

  Map<String, Object?> build({
    List<ComponentSpec>? specs,
    List<Map<String, Object?>> external = const [],
    String tag = '0.9.97+789',
    String version = '0.9.97',
  }) => buildReleaseManifest(
    releaseTag: tag,
    releaseVersion: version,
    directory: dir,
    specs: specs ?? kKnownComponents,
    externalComponents: external,
  );

  Map<String, Object?> componentById(
    Map<String, Object?> manifest,
    String id,
  ) => (manifest['components'] as List).cast<Map<String, Object?>>().firstWhere(
    (c) => c['id'] == id,
  );

  group('buildReleaseManifest', () {
    test('a realistic 0.9.97 release produces the expected components', () {
      writeRealisticRelease();
      final manifest = build();

      expect(manifest['schemaVersion'], 1);
      expect(manifest['releaseTag'], '0.9.97+789');
      expect(manifest['releaseVersion'], '0.9.97');
      expect(validateReleaseManifest(manifest), isEmpty);

      final components = (manifest['components'] as List)
          .cast<Map<String, Object?>>();
      expect(
        components.map((c) => c['id']),
        containsAll([
          'otzaria-windows-x64',
          'otzaria-windows-arm64',
          'otzaria-windows-portable-x64',
          'otzaria-windows-portable-arm64',
          'otzaria-windows-full',
          'otzaria-windows-full-indexed',
          'library-full-indexed',
        ]),
      );

      // ממוין לפי installOrder — הצרכן מתקין לפי הסדר במניפסט.
      final orders = components.map((c) => c['installOrder'] as int).toList();
      final sorted = [...orders]..sort();
      expect(orders, sorted);

      final app = componentById(manifest, 'otzaria-windows-x64');
      expect(app['required'], isTrue);
      expect(app['type'], 'application');
      expect(app['platform'], 'windows');
      expect(app['architecture'], 'x64');
      expect(app['origin'], 'built');
      expect(app['downloadSize'], 'installer'.length);

      final asset = (app['assets'] as List).single as Map<String, Object?>;
      expect(asset['kind'], 'single');
      expect(asset['repository'], 'Otzaria/otzaria');
      expect(asset['releaseTag'], '0.9.97+789');
      expect(asset['name'], 'otzaria-0.9.97-windows.exe');
      expect(asset['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(asset.containsKey('parts'), isFalse);
    });

    test('the portable zip carries a type of its own', () {
      writeRealisticRelease();
      final manifest = build();

      final installer = componentById(manifest, 'otzaria-windows-x64');
      for (final id in const [
        'otzaria-windows-portable-x64',
        'otzaria-windows-portable-arm64',
      ]) {
        // צורה חלופית של אותה תוכנה — סוג משותף עם המתקין היה מצרף אותה
        // להצעות של מסייע ההורדה, שנגזרות מ-type.
        expect(componentById(manifest, id)['type'], 'application-portable');
        expect(
          componentById(manifest, id)['type'],
          isNot(installer['type']),
        );
      }
    });

    test('the full installer survives being split into parts', () {
      writeRealisticRelease(withFullInstaller: false);
      writeFile('otzaria-0.9.97-windows-full.exe.part-000', 'a' * 20);
      writeFile('otzaria-0.9.97-windows-full.exe.part-001', 'b' * 5);
      writeJson('otzaria-0.9.97-windows-full.exe.manifest.json', {
        'schemaVersion': 1,
        'archive': 'otzaria-0.9.97-windows-full.exe',
        'size': 25,
        'sha256': hex(0xcd),
        'partSizeLimit': 1992294400,
        'githubAssetLimit': 2147483648,
        'parts': [
          {
            'name': 'otzaria-0.9.97-windows-full.exe.part-000',
            'size': 20,
            'sha256': hex(0x3c),
          },
          {
            'name': 'otzaria-0.9.97-windows-full.exe.part-001',
            'size': 5,
            'sha256': hex(0x4d),
          },
        ],
      });

      final manifest = build();
      expect(validateReleaseManifest(manifest), isEmpty);
      final full = componentById(manifest, 'otzaria-windows-full');
      final asset = (full['assets'] as List).single as Map<String, Object?>;
      expect(asset['kind'], 'split');
      expect(asset['name'], 'otzaria-0.9.97-windows-full.exe');
      expect((asset['parts'] as List), hasLength(2));
      expect(full['downloadSize'], 25);
    });

    test('the download assistant is a tool, never a component', () {
      writeRealisticRelease();
      writeFile('Otzaria-Download-Assistant-windows.exe', 'assistant');
      final manifest = build();
      expect(jsonEncode(manifest), isNot(contains('Download-Assistant')));
    });

    test('the assistants of every platform are tools, never components', () {
      writeRealisticRelease();
      for (final name in const [
        'Otzaria-Download-Assistant-windows.exe',
        'Otzaria-Download-Assistant-macos.zip',
        'Otzaria-Download-Assistant-linux-x64.tar.gz',
        'Otzaria-Download-Assistant-linux-arm64.tar.gz',
      ]) {
        writeFile(name, 'assistant');
      }
      final manifest = build();
      expect(jsonEncode(manifest), isNot(contains('Download-Assistant')));
    });

    test('Linux, macOS and Android assets become filterable components', () {
      writeRealisticRelease();
      writeFile('otzaria-0.9.97+789-linux.deb', 'deb');
      writeFile('otzaria-0.9.97+789-linux-arm64.deb', 'deb-arm');
      writeFile('otzaria-0.9.97+789-789.x86_64.rpm', 'rpm');
      writeFile('otzaria-0.9.97+789-789.aarch64.rpm', 'rpm-arm');
      writeFile('otzaria-linux-full.tar.zst', 'linux-full');
      writeFile('otzaria-linux-full-arm64.tar.zst', 'linux-full-arm');
      writeFile('otzaria-macos.dmg', 'dmg');
      writeFile('otzaria-macos.zip', 'mac-update-zip');
      writeFile('otzaria-macos-full.tar.zst', 'mac-full');
      writeFile('app-release.apk', 'apk');
      writeFile('otzaria-android-full.zip', 'android-full');

      final manifest = build();
      expect(validateReleaseManifest(manifest), isEmpty);

      void expectComponent(
        String id,
        String asset, {
        required String type,
        required String platform,
        String? architecture,
        String? packageFormat,
      }) {
        final component = componentById(manifest, id);
        expect(component['type'], type, reason: id);
        expect(component['platform'], platform, reason: id);
        expect(component['architecture'], architecture, reason: id);
        expect(component['packageFormat'], packageFormat, reason: id);
        expect(
          ((component['assets'] as List).single as Map)['name'],
          asset,
          reason: id,
        );
      }

      expectComponent(
        'otzaria-linux-deb-x64',
        'otzaria-0.9.97+789-linux.deb',
        type: 'application',
        platform: 'linux',
        architecture: 'x64',
        packageFormat: 'deb',
      );
      expectComponent(
        'otzaria-linux-deb-arm64',
        'otzaria-0.9.97+789-linux-arm64.deb',
        type: 'application',
        platform: 'linux',
        architecture: 'arm64',
        packageFormat: 'deb',
      );
      expectComponent(
        'otzaria-linux-rpm-x64',
        'otzaria-0.9.97+789-789.x86_64.rpm',
        type: 'application',
        platform: 'linux',
        architecture: 'x64',
        packageFormat: 'rpm',
      );
      expectComponent(
        'otzaria-linux-rpm-arm64',
        'otzaria-0.9.97+789-789.aarch64.rpm',
        type: 'application',
        platform: 'linux',
        architecture: 'arm64',
        packageFormat: 'rpm',
      );
      expectComponent(
        'otzaria-linux-full-x64',
        'otzaria-linux-full.tar.zst',
        type: 'application-bundle',
        platform: 'linux',
        architecture: 'x64',
      );
      expectComponent(
        'otzaria-linux-full-arm64',
        'otzaria-linux-full-arm64.tar.zst',
        type: 'application-bundle',
        platform: 'linux',
        architecture: 'arm64',
      );
      // Universal Binary ו-APK של כל ה-ABI — ללא ארכיטקטורה.
      expectComponent(
        'otzaria-macos',
        'otzaria-macos.dmg',
        type: 'application',
        platform: 'macos',
      );
      expectComponent(
        'otzaria-macos-full',
        'otzaria-macos-full.tar.zst',
        type: 'application-bundle',
        platform: 'macos',
      );
      expectComponent(
        'otzaria-android',
        'app-release.apk',
        type: 'application',
        platform: 'android',
      );
      expectComponent(
        'otzaria-android-full',
        'otzaria-android-full.zip',
        type: 'application-bundle',
        platform: 'android',
      );

      // המסד לאנדרואיד הוא נכס שני של אותו רכיב, וה-APK מגיע דרך dependsOn.
      writeFile('otzaria-android-library.zdb', 'zdb');
      final withDb = componentById(build(), 'otzaria-android-full');
      expect(
        (withDb['assets'] as List).map((a) => (a as Map)['name']),
        ['otzaria-android-full.zip', 'otzaria-android-library.zdb'],
      );
      expect(withDb['dependsOn'], ['otzaria-android']);

      // ה-zip של macOS הוא ערוץ העדכון הפנימי, לא רכיב להורדה.
      expect(jsonEncode(manifest), isNot(contains('"otzaria-macos.zip"')));
    });

    test('a full bundle of any platform survives being split', () {
      writeRealisticRelease();
      writeFile('otzaria-linux-full.tar.zst.part-000', 'a' * 20);
      writeFile('otzaria-linux-full.tar.zst.part-001', 'b' * 5);
      writeJson('otzaria-linux-full.tar.zst.manifest.json', {
        'schemaVersion': 1,
        'archive': 'otzaria-linux-full.tar.zst',
        'size': 25,
        'sha256': hex(0xcd),
        'partSizeLimit': 1992294400,
        'githubAssetLimit': 2147483648,
        'parts': [
          {
            'name': 'otzaria-linux-full.tar.zst.part-000',
            'size': 20,
            'sha256': hex(0x3c),
          },
          {
            'name': 'otzaria-linux-full.tar.zst.part-001',
            'size': 5,
            'sha256': hex(0x4d),
          },
        ],
      });

      final manifest = build();
      final full = componentById(manifest, 'otzaria-linux-full-x64');
      final asset = (full['assets'] as List).single as Map<String, Object?>;
      expect(asset['kind'], 'split');
      expect(asset['name'], 'otzaria-linux-full.tar.zst');
      // תבנית ה-x64 אינה בולעת את חבילת ה-ARM64.
      expect(
        (manifest['components'] as List).map((c) => (c as Map)['id']),
        isNot(contains('otzaria-linux-full-arm64')),
      );
    });

    test('an absent component is omitted, never a placeholder', () {
      writeRealisticRelease(withFullInstaller: false);
      final manifest = build();
      final ids = (manifest['components'] as List)
          .cast<Map<String, Object?>>()
          .map((c) => c['id'])
          .toList();
      expect(ids, isNot(contains('otzaria-windows-full')));
      expect(ids, contains('otzaria-windows-full-indexed'));
      expect(jsonEncode(manifest), isNot(contains('otzaria-windows-full"')));
    });

    test('a split asset is one component with the parts hidden inside', () {
      writeRealisticRelease();
      final manifest = build();

      final library = componentById(manifest, 'library-full-indexed');
      expect(library['type'], 'library');
      // המתקין המאונדקס הוא היחיד שקורא את החלקים לצדו; המתקין הרגיל לא.
      expect(library['installedBy'], ['otzaria-windows-full-indexed']);
      expect(library['dependsOn'], isEmpty);
      // גודל ההורדה הוא סכום החלקים, לא גודל הארכיון בלבד.
      expect(library['downloadSize'], 42);

      final asset = (library['assets'] as List).single as Map<String, Object?>;
      expect(asset['kind'], 'split');
      expect(asset['name'], 'otzaria-0.9.97-library-full-indexed.tar.zst');
      expect(asset['size'], 42);
      expect(asset['sha256'], hex(0xab));
      expect(
        asset['manifestAsset'],
        'otzaria-0.9.97-library-full-indexed.tar.zst.manifest.json',
      );
      final parts = (asset['parts'] as List).cast<Map<String, Object?>>();
      expect(parts.map((p) => p['name']), [
        'otzaria-0.9.97-library-full-indexed.tar.zst.part-000',
        'otzaria-0.9.97-library-full-indexed.tar.zst.part-001',
      ]);
      expect(parts.map((p) => p['size']), [30, 12]);

      // אף חלק אינו רכיב בפני עצמו.
      final ids = (manifest['components'] as List)
          .cast<Map<String, Object?>>()
          .map((c) => c['id'] as String);
      expect(ids.where((id) => id.contains('part-')), isEmpty);
    });

    test('compatibility metadata is taken from the index provenance', () {
      writeRealisticRelease();
      writeJson('otzaria-library-index.provenance.json', {
        'schemaVersion': 1,
        'libraryReleaseTag': 'v27',
        'seforimDbZstSha256': hex(0x3c),
        'searchEngineVersion': '0.8.4',
        'talmudVolumesDigest': hex(0x4d),
        'catalogueBooks': 1234,
      });

      final library = componentById(build(), 'library-full-indexed');
      expect(library['compatibility'], {
        'libraryReleaseTag': 'v27',
        'seforimDbZstSha256': hex(0x3c),
        'searchEngineVersion': '0.8.4',
        'talmudVolumesDigest': hex(0x4d),
      });
    });

    test('no provenance file means no compatibility key at all', () {
      writeRealisticRelease();
      expect(
        componentById(
          build(),
          'library-full-indexed',
        ).containsKey('compatibility'),
        isFalse,
      );
    });

    test('a future component type round-trips with no consumer change', () {
      writeRealisticRelease();
      writeFile('otzaria-0.9.97-semantic-model.bin', 'model');

      const futureSpec = ComponentSpec(
        id: 'semantic-model',
        name: 'מודל חיפוש סמנטי',
        description: 'מודל להבנת משמעות בחיפוש.',
        type: 'semantic-model',
        required: false,
        installOrder: 40,
        origin: 'imported',
        assets: [AssetSpec(pattern: r'^otzaria-.+-semantic-model\.bin$')],
      );

      final manifest = build(specs: [...kKnownComponents, futureSpec]);
      expect(validateReleaseManifest(manifest), isEmpty);

      final decoded = jsonDecode(jsonEncode(manifest));
      expect(validateReleaseManifest(decoded), isEmpty);
      final model = componentById(
        decoded as Map<String, Object?>,
        'semantic-model',
      );
      expect(model['type'], 'semantic-model');
      expect(model['origin'], 'imported');
      expect(model['installOrder'], 40);
      // נספח אחרון בסדר ההתקנה.
      expect((decoded['components'] as List).last['id'], 'semantic-model');
    });

    test('a component from another Otzaria repository keeps its address', () {
      writeRealisticRelease();
      final manifest = build(
        external: [
          {
            'id': 'seforim-database',
            'name': 'מסד הספרים',
            'description': 'מסד הספרים מהמאגר של SeforimLibrary.',
            'type': 'library',
            'required': false,
            'origin': 'built',
            'installOrder': 35,
            'dependsOn': const <String>[],
            'installedBy': const ['otzaria-windows-full-indexed'],
            'downloadSize': 100,
            'assets': [
              {
                'kind': 'single',
                'repository': 'Otzaria/SeforimLibrary',
                'releaseTag': 'v27',
                'name': 'seforim.db.zst',
                'size': 100,
                'sha256': hex(0x5e),
              },
            ],
          },
        ],
      );
      expect(validateReleaseManifest(manifest), isEmpty);
      final external = componentById(manifest, 'seforim-database');
      final asset = (external['assets'] as List).single as Map<String, Object?>;
      expect(asset['repository'], 'Otzaria/SeforimLibrary');
      expect(asset['releaseTag'], 'v27');
    });
  });

  group('who installs a library (installedBy)', () {
    test('a library whose installer was not built is left out', () {
      writeRealisticRelease();
      File('${dir.path}/otzaria-0.9.97-windows-full-indexed.exe').deleteSync();
      final manifest = build();
      expect(validateReleaseManifest(manifest), isEmpty);
      final ids = (manifest['components'] as List).map((c) => (c as Map)['id']);
      expect(ids, isNot(contains('library-full-indexed')));
    });

    test('the ARM64 FULL installer is its own component', () {
      writeRealisticRelease();
      writeFile('otzaria-0.9.97-windows_arm64-full.exe', 'full-arm');
      final manifest = build();
      String assetOf(String id) =>
          ((componentById(manifest, id)['assets'] as List).single
                  as Map)['name']
              as String;
      expect(
        assetOf('otzaria-windows-full-arm64'),
        'otzaria-0.9.97-windows_arm64-full.exe',
      );
      expect(
        assetOf('otzaria-windows-arm64'),
        'otzaria-0.9.97-windows_arm64.exe',
      );
      expect(
        assetOf('otzaria-windows-full'),
        'otzaria-0.9.97-windows-full.exe',
      );
      final arm = componentById(manifest, 'otzaria-windows-full-arm64');
      expect(arm['type'], 'application-bundle');
      expect(arm['architecture'], 'arm64');
    });

    Map<String, Object?> component(
      String id, {
      String type = 'application',
      Object? installedBy,
    }) => {
      'id': id,
      'name': id,
      'description': id,
      'type': type,
      'required': false,
      'origin': 'built',
      'installOrder': 1,
      'dependsOn': const <String>[],
      'installedBy': ?installedBy,
      'downloadSize': 10,
      'assets': [
        {
          'kind': 'single',
          'repository': 'Otzaria/otzaria',
          'releaseTag': '1',
          'name': '$id.bin',
          'size': 10,
          'sha256': hex(0x11),
        },
      ],
    };

    List<String> errorsOf(List<Map<String, Object?>> components) =>
        validateReleaseManifest({
          'schemaVersion': 1,
          'releaseTag': '1',
          'releaseVersion': '1',
          'components': components,
        });

    test('a library must name who installs it', () {
      expect(errorsOf([component('lib', type: 'library')]), isNotEmpty);
      expect(
        errorsOf([
          component('setup'),
          component('lib', type: 'library', installedBy: const ['setup']),
        ]),
        isEmpty,
      );
    });

    test('installedBy must point at an existing, final installer', () {
      expect(
        errorsOf([
          component('lib', type: 'library', installedBy: const ['missing']),
        ]),
        isNotEmpty,
      );
      expect(
        errorsOf([
          component('lib', type: 'library', installedBy: const ['lib']),
        ]),
        isNotEmpty,
      );
      expect(
        errorsOf([
          component('setup'),
          component('mid', installedBy: const ['setup']),
          component('lib', type: 'library', installedBy: const ['mid']),
        ]),
        isNotEmpty,
        reason: 'שרשרת מתקינים',
      );
      expect(
        errorsOf([
          component('lib', type: 'library', installedBy: const <String>[]),
        ]),
        isNotEmpty,
      );
    });
  });

  group('malformed input is rejected', () {
    test('a split manifest of an unknown schema version', () {
      writeRealisticRelease();
      writeJson('otzaria-0.9.97-library-full-indexed.tar.zst.manifest.json', {
        'schemaVersion': 2,
        'archive': 'otzaria-0.9.97-library-full-indexed.tar.zst',
        'size': 42,
        'sha256': hex(0xab),
        'parts': [
          {'name': 'a.part-000', 'size': 42, 'sha256': hex(0x1a)},
        ],
      });
      expect(build, throwsA(isA<ReleaseManifestException>()));
    });

    test('a part listed in the split manifest but missing from the dir', () {
      writeRealisticRelease();
      File(
        '${dir.path}/otzaria-0.9.97-library-full-indexed.tar.zst.part-001',
      ).deleteSync();
      expect(build, throwsA(isA<ReleaseManifestException>()));
    });

    test('a part whose size on disk differs from the manifest', () {
      writeRealisticRelease();
      writeFile(
        'otzaria-0.9.97-library-full-indexed.tar.zst.part-001',
        'short',
      );
      expect(build, throwsA(isA<ReleaseManifestException>()));
    });

    test('a malformed hash in the split manifest', () {
      writeRealisticRelease();
      writeJson('otzaria-0.9.97-library-full-indexed.tar.zst.manifest.json', {
        'schemaVersion': 1,
        'archive': 'otzaria-0.9.97-library-full-indexed.tar.zst',
        'size': 42,
        'sha256': 'not-a-hash',
        'parts': [
          {'name': 'x.part-000', 'size': 42, 'sha256': hex(0x1a)},
        ],
      });
      expect(build, throwsA(isA<ReleaseManifestException>()));
    });

    test('an unsafe part name never becomes a path', () {
      writeRealisticRelease();
      writeJson('otzaria-0.9.97-library-full-indexed.tar.zst.manifest.json', {
        'schemaVersion': 1,
        'archive': 'otzaria-0.9.97-library-full-indexed.tar.zst',
        'size': 42,
        'sha256': hex(0xab),
        'parts': [
          {'name': '../evil.part-000', 'size': 42, 'sha256': hex(0x1a)},
        ],
      });
      expect(build, throwsA(isA<ReleaseManifestException>()));
    });

    test('an empty release tag or version', () {
      writeRealisticRelease();
      expect(
        () => build(tag: '  '),
        throwsA(isA<ReleaseManifestException>()),
      );
      expect(
        () => build(version: ''),
        throwsA(isA<ReleaseManifestException>()),
      );
    });

    test('a missing release directory', () {
      dir.deleteSync(recursive: true);
      expect(build, throwsA(isA<ReleaseManifestException>()));
    });

    test(
      'an external component addressed outside the Otzaria organization',
      () {
        writeRealisticRelease();
        expect(
          () => build(
            external: [
              {
                'id': 'rogue',
                'name': 'רכיב חיצוני',
                'description': 'מאגר שאינו בארגון.',
                'type': 'dependency',
                'required': false,
                'origin': 'imported',
                'installOrder': 99,
                'dependsOn': const <String>[],
                'downloadSize': 10,
                'assets': [
                  {
                    'kind': 'single',
                    'repository': 'someone-else/tool',
                    'releaseTag': 'v1',
                    'name': 'tool.exe',
                    'size': 10,
                    'sha256': hex(0x6f),
                  },
                ],
              },
            ],
          ),
          throwsA(isA<ReleaseManifestException>()),
        );
      },
    );
  });

  group('validateReleaseManifest', () {
    test('accepts unknown extra fields for forward compatibility', () {
      writeRealisticRelease();
      final manifest = build();
      manifest['futureTopLevelField'] = 'whatever';
      (manifest['components'] as List)
          .cast<Map<String, Object?>>()
          .first['futureComponentField'] = {
        'nested': true,
      };
      expect(validateReleaseManifest(manifest), isEmpty);
    });

    test('rejects a split asset whose parts do not add up', () {
      final errors = validateReleaseManifest({
        'schemaVersion': 1,
        'releaseTag': '0.9.97+789',
        'releaseVersion': '0.9.97',
        'components': [
          {
            'id': 'broken',
            'name': 'שבור',
            'description': 'חלקים שאינם מסתכמים.',
            'type': 'library',
            'required': false,
            'origin': 'built',
            'installOrder': 1,
            'dependsOn': const <String>[],
            'downloadSize': 10,
            'assets': [
              {
                'kind': 'split',
                'repository': 'Otzaria/otzaria',
                'releaseTag': '0.9.97+789',
                'name': 'a.tar.zst',
                'manifestAsset': 'a.tar.zst.manifest.json',
                'size': 100,
                'sha256': hex(0x7a),
                'parts': [
                  {
                    'name': 'a.tar.zst.part-000',
                    'size': 10,
                    'sha256': hex(0x8b),
                  },
                ],
              },
            ],
          },
        ],
      });
      expect(errors, isNotEmpty);
    });

    test('rejects a dependency on a component that is not in the manifest', () {
      final errors = validateReleaseManifest({
        'schemaVersion': 1,
        'releaseTag': '0.9.97+789',
        'releaseVersion': '0.9.97',
        'components': [
          {
            'id': 'lonely',
            'name': 'בודד',
            'description': 'תלוי ברכיב שאינו קיים.',
            'type': 'library',
            'required': false,
            'origin': 'built',
            'installOrder': 1,
            'dependsOn': const ['missing'],
            'downloadSize': 10,
            'assets': [
              {
                'kind': 'single',
                'repository': 'Otzaria/otzaria',
                'releaseTag': '0.9.97+789',
                'name': 'a.exe',
                'size': 10,
                'sha256': hex(0x9c),
              },
            ],
          },
        ],
      });
      expect(errors, isNotEmpty);
    });

    test('rejects an empty or non-string filter field', () {
      writeRealisticRelease();
      final manifest = build();
      final app = componentById(manifest, 'otzaria-windows-x64');
      app['packageFormat'] = '';
      app['architecture'] = 64;
      final errors = validateReleaseManifest(manifest);
      expect(errors, contains(contains('packageFormat')));
      expect(errors, contains(contains('architecture')));
    });

    test('rejects a non-object manifest', () {
      expect(validateReleaseManifest('nope'), isNotEmpty);
      expect(validateReleaseManifest(null), isNotEmpty);
    });
  });

  group('מדידת נכס בזרימה', () {
    test('אותו digest של crypto, על קובץ שגדול ממקטע הקריאה', () {
      final bytes = Uint8List(5 * 1024 * 1024 + 7);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = (i * 31 + 7) & 0xff;
      }
      final file = File('${dir.path}/big.bin')..writeAsBytesSync(bytes);

      final measured = measureAsset(file);

      expect(measured.size, bytes.length);
      expect(measured.sha256, sha256.convert(bytes).toString());
    });

    test('מקטע זעיר אינו משנה את התוצאה — הקריאה באמת חלקית', () {
      final bytes = Uint8List.fromList(List.generate(10007, (i) => i & 0xff));
      final file = File('${dir.path}/small.bin')..writeAsBytesSync(bytes);

      // 64 בתים למקטע: 157 קריאות, כולל אחת חלקית בסוף.
      expect(
        measureAsset(file, chunkSize: 64).sha256,
        sha256.convert(bytes).toString(),
      );
    });

    test('הנכס במניפסט נמדד בלי לקרוא את כולו לזיכרון', () {
      writeRealisticRelease();
      final manifest = buildReleaseManifest(
        releaseTag: '0.9.97+789',
        releaseVersion: '0.9.97',
        directory: dir,
      );
      final component = (manifest['components'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((c) => c['id'] == 'otzaria-windows-x64');
      final asset =
          (component['assets'] as List).single as Map<String, Object?>;
      final file = File('${dir.path}/otzaria-0.9.97-windows.exe');
      expect(asset['size'], file.lengthSync());
      expect(
        asset['sha256'],
        sha256.convert(file.readAsBytesSync()).toString(),
      );
    });
  });

  group('שמות הרכיבים למשתמש', () {
    test('שם מערכת ההפעלה נכתב Windows ולא בתרגום עברי', () {
      for (final spec in kKnownComponents) {
        expect(spec.name, isNot(contains('חלונות')), reason: spec.id);
        expect(spec.description, isNot(contains('חלונות')), reason: spec.id);
        const displayNames = {
          'windows': 'Windows',
          'linux': 'Linux',
          'macos': 'macOS',
          'android': 'Android',
        };
        final displayName = displayNames[spec.platform];
        if (displayName != null) {
          expect(spec.name, contains(displayName), reason: spec.id);
        }
      }
    });

    test('שמות רכיבי Windows', () {
      String nameOf(String id) =>
          kKnownComponents.firstWhere((c) => c.id == id).name;
      expect(nameOf('otzaria-windows-x64'), 'אוצריא ל-Windows');
      expect(nameOf('otzaria-windows-arm64'), 'אוצריא ל-Windows (ARM64)');
      expect(
        nameOf('otzaria-windows-portable-x64'),
        'אוצריא ל-Windows — גרסה ניידת',
      );
      expect(
        nameOf('otzaria-windows-portable-arm64'),
        'אוצריא ל-Windows — גרסה ניידת (ARM64)',
      );
      expect(
        nameOf('otzaria-windows-full'),
        'אוצריא ל-Windows עם ספרייה מלאה',
      );
      expect(
        nameOf('otzaria-windows-full-indexed'),
        'אוצריא ל-Windows עם ספרייה מאונדקסת',
      );
    });
  });
}
