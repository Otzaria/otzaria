import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/differential_update_service.dart';
import 'package:otzaria/update/differential/update_package.dart';
import 'package:otzaria/update/differential/zstd_runner.dart';
import 'package:otzaria/update/my_update_widget.dart';
import 'package:path/path.dart' as p;
import 'package:updat/updat.dart';

import '../../tool/release/generate_app_file_manifest.dart';
import '../../tool/release/generate_update_package.dart' as builder;

const _oldTag = '0.9.97';
const _newTag = '0.9.98';

/// שתי בניות סינתטיות ושתי החבילות שביניהן, כמו ב-release אמיתי.
class _Release {
  _Release(this.root);

  final Directory root;

  Directory get oldRoot => Directory(p.join(root.path, 'old'));
  Directory get newRoot => Directory(p.join(root.path, 'new'));
  Directory get assetsDir => Directory(p.join(root.path, 'assets'));

  late String patchAssetName;
  late String fullAssetName;

  void build() {
    final body = List.generate(3000, (i) => 'line $i of otzaria\n').join();
    _write(oldRoot, 'otzaria.exe', utf8.encode('$body old'));
    _write(newRoot, 'otzaria.exe', utf8.encode('$body new'));
    _write(oldRoot, 'config.bin', _randomBytes(4096, 1));
    _write(newRoot, 'config.bin', _randomBytes(4096, 2));

    final oldManifest = buildAppFileManifest(
      releaseTag: _oldTag,
      releaseVersion: '0.9.97',
      platform: 'windows',
      architecture: 'x64',
      root: oldRoot,
    );
    final newManifest = buildAppFileManifest(
      releaseTag: _newTag,
      releaseVersion: '0.9.98',
      platform: 'windows',
      architecture: 'x64',
      root: newRoot,
    );
    assetsDir.createSync(recursive: true);
    for (final variant in builder.UpdatePackageVariant.values) {
      final name = builder.updatePackageAssetName(
        platform: 'windows',
        architecture: 'x64',
        fromReleaseTag: _oldTag,
        toReleaseTag: _newTag,
        variant: variant,
      );
      builder.buildUpdatePackage(
        oldManifest: oldManifest,
        oldRoot: oldRoot,
        newManifest: newManifest,
        newRoot: newRoot,
        output: File(p.join(assetsDir.path, name)),
        variant: variant,
      );
      if (variant == builder.UpdatePackageVariant.patch) {
        patchAssetName = name;
      } else {
        fullAssetName = name;
      }
    }
  }

  Directory install(String name) {
    final copy = Directory(p.join(root.path, name));
    for (final entity in oldRoot.listSync(recursive: true)) {
      if (entity is! File) continue;
      final target = File(
        p.join(copy.path, p.relative(entity.path, from: oldRoot.path)),
      );
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
    return copy;
  }

  List<UpdatePackageAsset> get assets => [
    for (final entity in assetsDir.listSync())
      if (entity is File)
        UpdatePackageAsset(
          name: p.basename(entity.path),
          url: 'file://${entity.path}',
          size: entity.lengthSync(),
        ),
  ];

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

void main() {
  late Directory temp;
  late _Release release;
  final hasZstd = const builder.Zstd().isAvailable;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('otzaria-update-service');
    release = _Release(temp);
    if (hasZstd) release.build();
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('שמות הנכסים', () {
    test('הלקוח והבונה מרכיבים את אותו שם בדיוק', () {
      for (final tag in const ['0.9.97', '0.9.98+789', 'v1.0.0']) {
        expect(
          updatePackageAssetNameFor(
            platform: 'windows',
            architecture: 'x64',
            fromReleaseTag: tag,
            toReleaseTag: '0.9.99+1',
          ),
          builder.updatePackageAssetName(
            platform: 'windows',
            architecture: 'x64',
            fromReleaseTag: tag,
            toReleaseTag: '0.9.99+1',
          ),
        );
        expect(
          updatePackageAssetNameFor(
            platform: 'windows',
            architecture: 'arm64',
            fromReleaseTag: tag,
            toReleaseTag: '0.9.99+1',
            kind: UpdatePackageKind.full,
          ),
          builder.updatePackageAssetName(
            platform: 'windows',
            architecture: 'arm64',
            fromReleaseTag: tag,
            toReleaseTag: '0.9.99+1',
            variant: builder.UpdatePackageVariant.full,
          ),
        );
      }
    });

    test('שתי החבילות נבדלות בשם', () {
      expect(
        updatePackageAssetNameFor(
          platform: 'windows',
          architecture: 'x64',
          fromReleaseTag: 'a',
          toReleaseTag: 'b',
        ),
        isNot(
          updatePackageAssetNameFor(
            platform: 'windows',
            architecture: 'x64',
            fromReleaseTag: 'a',
            toReleaseTag: 'b',
            kind: UpdatePackageKind.full,
          ),
        ),
      );
    });

    test('נכס שאינו קיים ברשימה אינו מנוחש', () {
      const assets = [
        UpdatePackageAsset(name: 'other.zip', url: 'u', size: 1),
      ];
      expect(findUpdatePackageAsset(assets, 'wanted.zip'), isNull);
      expect(findUpdatePackageAsset(assets, 'other.zip')?.url, 'u');
    });
  });

  group('זמינות המסלול', () {
    test('כל תנאי חסר מבטל את המסלול', () {
      bool supported({
        bool windows = true,
        bool writable = true,
        bool zstd = true,
        bool helper = true,
      }) => differentialUpdateSupported(
        isWindows: windows,
        installRootWritable: writable,
        zstdAvailable: zstd,
        hasUpdaterHelper: helper,
      );

      expect(supported(), isTrue);
      expect(supported(windows: false), isFalse);
      expect(supported(writable: false), isFalse);
      expect(supported(zstd: false), isFalse);
      expect(supported(helper: false), isFalse);
    });

    test('ארכיטקטורת ההתקנה נקבעת לפי התהליך ולא לפי המעבד', () {
      expect(
        installedWindowsArchitecture(
          isWindowsOnArm: true,
          isEmulatedOnArm: false,
        ),
        'arm64',
      );
      // בנייית x64 שרצה באמולציה על מחשב ARM היא עדיין התקנת x64.
      expect(
        installedWindowsArchitecture(
          isWindowsOnArm: true,
          isEmulatedOnArm: true,
        ),
        'x64',
      );
      expect(
        installedWindowsArchitecture(
          isWindowsOnArm: false,
          isEmulatedOnArm: false,
        ),
        'x64',
      );
    });
  });

  group('המסלול מקצה לקצה', () {
    DifferentialUpdateService service(
      Directory install,
      List<String> downloads,
    ) => DifferentialUpdateService(
      installRoot: install,
      workRoot: Directory(p.join(temp.path, 'work')),
      architecture: 'x64',
      installedReleaseTag: _oldTag,
      zstd: const ZstdRunner(),
      fetchAssets: (_) async => release.assets,
      download: (url, target, {int? expectedSize}) async {
        downloads.add(p.basename(url));
        File(url.replaceFirst('file://', '')).copySync(target.path);
        return target;
      },
    );

    test('כל ה-patch מוחל — חבילת הקבצים המלאים אינה יורדת', () async {
      final install = release.install('install');
      final downloads = <String>[];

      final prepared = await service(install, downloads).prepare(_newTag);

      expect(downloads, [release.patchAssetName]);
      expect(prepared.staged.files, isNotEmpty);
      expect(prepared.downloadedBytes, greaterThan(0));
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('קובץ מקומי שונה — הערך מושלם מחבילת הקבצים המלאים', () async {
      final install = release.install('install');
      File(p.join(install.path, 'otzaria.exe')).writeAsStringSync('modified');
      final downloads = <String>[];

      final prepared = await service(install, downloads).prepare(_newTag);

      expect(downloads, [release.patchAssetName, release.fullAssetName]);
      final staged = File(
        p.join(prepared.staged.stagingRoot.path, 'otzaria.exe'),
      );
      expect(
        staged.readAsBytesSync(),
        File(p.join(release.newRoot.path, 'otzaria.exe')).readAsBytesSync(),
      );
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);

    test('אין חבילה לגרסה הזאת — אין מסלול מצומצם', () async {
      final install = release.install('install');
      final downloads = <String>[];
      final withoutAssets = DifferentialUpdateService(
        installRoot: install,
        workRoot: Directory(p.join(temp.path, 'work')),
        architecture: 'x64',
        installedReleaseTag: _oldTag,
        zstd: const ZstdRunner(),
        fetchAssets: (_) async => const [],
        download: (url, target, {int? expectedSize}) async => target,
      );

      await expectLater(
        withoutAssets.prepare(_newTag),
        throwsA(isA<DifferentialUpdateUnavailable>()),
      );
      expect(downloads, isEmpty);
    }, skip: !hasZstd ? 'zstd is not on PATH' : null);
  });

  group('חיווט הממשק', () {
    test('כשל במסלול המצומצם נבלע ומחזיר null', () async {
      expect(
        await tryPrepareDifferentialUpdate(
          () async => throw const SocketException('offline'),
        ),
        isNull,
      );
      expect(
        await tryPrepareDifferentialUpdate(
          () async => throw DifferentialUpdateUnavailable(
            UpdateAbortReason.environment,
            'no zstd',
          ),
        ),
        isNull,
      );
    });

    test('מסלול שאינו זמין מחזיר null בלי חריגה', () async {
      expect(await tryPrepareDifferentialUpdate(() async => null), isNull);
    });

    test('עדכון מצומצם מוכן מותקן ביציאה כמו מתקין שהורד', () {
      // `hasInstallerFile` מקבל גם עדכון מצומצם מוכן — אחרת סגירת החלון
      // הייתה מדלגת עליו והעדכון לא היה מותקן לעולם.
      expect(
        shouldLaunchInstallerOnExit(
          status: UpdatStatus.readyToInstall,
          hasInstallerFile: true,
        ),
        isTrue,
      );
      expect(
        shouldLaunchInstallerOnExit(
          status: UpdatStatus.readyToInstall,
          hasInstallerFile: false,
        ),
        isFalse,
      );
    });
  });
}
