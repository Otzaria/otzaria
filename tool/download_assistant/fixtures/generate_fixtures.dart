// ignore_for_file: avoid_print
//
// מפיק את קובצי הייחוס של חוזה הבחירה במסייע ההורדה:
//   dart run tool/download_assistant/fixtures/generate_fixtures.dart
// המסייעים (Inno, SwiftUI, GTK) משווים את עצמם לפלט; הבדיקה
// test/release/download_assistant_selection_test.dart נכשלת כשהוא מתיישן.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../release/download_assistant_selection.dart';
import '../../release/generate_release_manifest.dart';

const String kFixtureTag = '0.10.3+143';
const String kFixtureVersion = '0.10.3';
const String kFixtureDir = 'tool/download_assistant/fixtures';

/// גודל כל קובץ ב-release המדומה. היחסים ביניהם הם שקובעים את ההצעות (החבילה
/// הגדולה ביותר נבחרת), ולכן הם משקפים את 0.9.97 בקנה מידה מוקטן.
const Map<String, int> _singleFiles = {
  'otzaria-0.10.3-windows.exe': 39,
  'otzaria-0.10.3-windows_arm64.exe': 38,
  'otzaria-windows.zip': 45,
  'otzaria-windows_arm64.zip': 44,
  'otzaria-0.10.3-windows-full-indexed.exe': 60,
  'otzaria-0.10.3-windows_arm64-full.exe': 1990,
  'otzaria-0.10.3+143-linux.deb': 96,
  'otzaria-0.10.3+143-linux-arm64.deb': 87,
  'otzaria-0.10.3+143-143.x86_64.rpm': 132,
  'otzaria-0.10.3+143-143.aarch64.rpm': 127,
  'otzaria-linux-full-arm64.tar.zst': 1900,
  'otzaria-macos.dmg': 86,
  'otzaria-macos.zip': 86,
  'otzaria-macos-full.tar.zst': 1853,
  'app-release.apk': 96,
  // ה-ZIP בלי המסד, והמסד כקובץ נפרד: בטלפון אין הרכבת חלקים.
  'otzaria-android-full.zip': 560,
  'otzaria-android-library.zdb': 1850,
  // אינם רכיבים — חייבים להיעדר מהמניפסט.
  'Otzaria-Download-Assistant-windows.exe': 5,
  'Otzaria-Download-Assistant-macos.zip': 5,
  'Otzaria-Download-Assistant-linux-x64.tar.gz': 5,
  'Otzaria-Download-Assistant-linux-arm64.tar.gz': 5,
  'otzaria-app-files-windows-x64.json': 5,
  'assemble_split_asset.sh': 5,
};

/// נכסים מפוצלים: שם הקובץ השלם → גודלי החלקים.
const Map<String, List<int>> _splitFiles = {
  'otzaria-0.10.3-windows-full.exe': [1500, 519],
  'otzaria-linux-full.tar.zst': [1500, 427],
  'otzaria-0.10.3-library-full-indexed.tar.zst': [1500, 1500, 215],
};

/// מחשבי היעד שעליהם נבדק החוזה.
const List<AssistantTarget> kFixtureTargets = [
  AssistantTarget(platform: 'windows', architecture: 'x64'),
  AssistantTarget(platform: 'windows', architecture: 'arm64'),
  AssistantTarget(platform: 'macos'),
  AssistantTarget(platform: 'linux', architecture: 'x64', packageFormat: 'deb'),
  AssistantTarget(platform: 'linux', architecture: 'x64', packageFormat: 'rpm'),
  AssistantTarget(
    platform: 'linux',
    architecture: 'x64',
    packageFormat: 'portable',
  ),
  AssistantTarget(
    platform: 'linux',
    architecture: 'arm64',
    packageFormat: 'deb',
  ),
  AssistantTarget(
    platform: 'linux',
    architecture: 'arm64',
    packageFormat: 'rpm',
  ),
  AssistantTarget(
    platform: 'linux',
    architecture: 'arm64',
    packageFormat: 'portable',
  ),
  AssistantTarget(platform: 'android'),
];

/// היעדים של הווריאנט שבו מתקין ה-FULL גדל ל-4 GiB ומעלה.
const List<AssistantTarget> kLargeFullTargets = [
  AssistantTarget(platform: 'windows', architecture: 'x64'),
  AssistantTarget(platform: 'windows', architecture: 'arm64'),
];

/// גודלי החלקים של מתקין FULL בגודל 4 GiB בדיוק — הגודל הראשון ש-Windows
/// מסרב להריץ. כל חלק מתחת למגבלת GitHub.
const List<int> kLargeFullPartSizes = [2000000000, 2000000000, 294967296];

/// דוגמאות os-release (null = המסייע אינו רץ ב-Linux).
const Map<String, String?> kOsReleaseSamples = {
  'ubuntu': 'NAME="Ubuntu"\nID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\n',
  'linuxmint': 'ID=linuxmint\nID_LIKE="ubuntu debian"\n',
  'fedora': 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=40\n',
  'opensuse-tumbleweed': 'ID="opensuse-tumbleweed"\nID_LIKE="opensuse suse"\n',
  'arch': 'NAME="Arch Linux"\nID=arch\n',
  'not-linux': null,
};

Uint8List _bytes(String name, int length) {
  final seed = utf8.encode(name);
  return Uint8List.fromList(
    List<int>.generate(length, (i) => seed[i % seed.length]),
  );
}

/// כותב release מדומה ל-[dir] — אותם שמות קבצים של release אמיתי.
void writeFixtureRelease(Directory dir) {
  _singleFiles.forEach((name, size) {
    File('${dir.path}/$name').writeAsBytesSync(_bytes(name, size));
  });
  _splitFiles.forEach((archive, sizes) {
    final whole = _bytes(archive, sizes.fold(0, (a, b) => a + b));
    final parts = <Map<String, Object>>[];
    var offset = 0;
    for (var i = 0; i < sizes.length; i++) {
      final name = '$archive.part-${i.toString().padLeft(3, '0')}';
      final chunk = Uint8List.sublistView(whole, offset, offset + sizes[i]);
      File('${dir.path}/$name').writeAsBytesSync(chunk);
      parts.add({
        'name': name,
        'size': sizes[i],
        'sha256': sha256.convert(chunk).toString(),
      });
      offset += sizes[i];
    }
    File('${dir.path}/$archive.manifest.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'archive': archive,
        'size': whole.length,
        'sha256': sha256.convert(whole).toString(),
        'partSizeLimit': 1500,
        'githubAssetLimit': kGithubAssetLimit,
        'parts': parts,
      }),
    );
  });
}

Map<String, Object?> buildFixtureManifest() {
  final dir = Directory.systemTemp.createTempSync('otzaria-assistant-fixture');
  try {
    writeFixtureRelease(dir);
    return buildReleaseManifest(
      releaseTag: kFixtureTag,
      releaseVersion: kFixtureVersion,
      directory: dir,
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// המניפסט המדומה, כששני מתקיני ה-FULL (x64 ו-ARM64) מפוצלים וגדולים מכדי
/// לרוץ. הקבצים עצמם אינם נוצרים — רק הגדלים, שהם כל מה שכללי הבחירה קוראים.
Map<String, Object?> buildLargeFullFixtureManifest() {
  final manifest = buildFixtureManifest();
  final total = kLargeFullPartSizes.fold(0, (a, b) => a + b);
  for (final full
      in (manifest['components'] as List).cast<Map<String, Object?>>().where(
        (c) =>
            c['id'] == 'otzaria-windows-full' ||
            c['id'] == 'otzaria-windows-full-arm64',
      )) {
    final asset = (full['assets'] as List).cast<Map<String, Object?>>().single;
    final name = asset['name'] as String;
    asset
      ..['kind'] = 'split'
      ..['size'] = total
      ..['manifestAsset'] = '$name.manifest.json'
      ..['githubAssetLimit'] = kGithubAssetLimit
      ..['parts'] = [
        for (var i = 0; i < kLargeFullPartSizes.length; i++)
          {
            'name': '$name.part-${i.toString().padLeft(3, '0')}',
            'size': kLargeFullPartSizes[i],
            'sha256': asset['sha256'],
          },
      ];
    full['downloadSize'] = total;
  }
  final errors = validateReleaseManifest(manifest);
  if (errors.isNotEmpty) throw StateError(errors.join('; '));
  return manifest;
}

/// התוצאה הצפויה של החוזה על המניפסט — כל מה שמסייע מציג ומפיק.
Map<String, Object?> buildExpectedSelections(
  Map<String, Object?> manifest, {
  List<AssistantTarget> targets = kFixtureTargets,
}) {
  final components = (manifest['components'] as List)
      .cast<Map<String, Object?>>();
  return {
    'platformChoices': platformChoices(manifest),
    'architectureChoices': {
      for (final platform in kAssistantPlatforms)
        platform: architectureChoices(manifest, platform),
    },
    'packageFormatChoices': {
      for (final architecture in architectureChoices(manifest, 'linux'))
        'linux/$architecture': packageFormatChoices(
          manifest,
          'linux',
          architecture,
        ),
    },
    'defaultPackageFormat': {
      for (final entry in kOsReleaseSamples.entries)
        entry.key: defaultPackageFormat(
          entry.value,
          packageFormatChoices(manifest, 'linux', 'x64'),
        ),
    },
    'targets': [
      for (final target in targets)
        {
          'target': target.toJson(),
          'offeredComponents': [
            for (final component in components)
              if (componentIsOffered(manifest, component, target))
                component['id'],
          ],
          'presets': [
            for (final preset in buildPresets(manifest, target))
              () {
                final files = plannedOutputFiles(
                  manifest,
                  preset.members,
                  target,
                );
                return {
                  ...preset.toJson(),
                  'outputFiles': files,
                  'outputSubfolder': plannedOutputSubfolder(
                    files,
                    target.platform,
                  ),
                };
              }(),
          ],
        },
    ],
  };
}

String encodeFixture(Object value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

void main() {
  final manifest = buildFixtureManifest();
  File(
    '$kFixtureDir/release-manifest.json',
  ).writeAsStringSync(encodeFixture(manifest));
  File(
    '$kFixtureDir/expected-selections.json',
  ).writeAsStringSync(encodeFixture(buildExpectedSelections(manifest)));
  final large = buildLargeFullFixtureManifest();
  File(
    '$kFixtureDir/release-manifest-large-full.json',
  ).writeAsStringSync(encodeFixture(large));
  File('$kFixtureDir/expected-selections-large-full.json').writeAsStringSync(
    encodeFixture(buildExpectedSelections(large, targets: kLargeFullTargets)),
  );
  print('Wrote the fixtures to $kFixtureDir');
}
