import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// כל ה-jobs של build-and-announce נארזים עם המסד של אותו release בדיוק.
void main() {
  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  final workflow = read('.github/workflows/build-and-announce.yml');
  const tagOutput = r'${{ needs.bump_version.outputs.library_tag }}';

  String job(String name, String next) => workflow.substring(
    workflow.indexOf('\n  $name:\n'),
    workflow.indexOf('\n  $next:\n'),
  );

  test('bump_version פותר את ה-release פעם אחת ומייצא אותו', () {
    final bump = job('bump_version', 'check_version');
    expect(
      bump,
      contains(r'library_tag: ${{ steps.library_release.outputs.tag }}'),
    );
    expect(bump, contains('id: library_release'));
    expect(
      bump,
      contains('gh api repos/Otzaria/SeforimLibrary/releases/latest'),
    );
    expect(bump, contains(r'echo "tag=$tag" >> "$GITHUB_OUTPUT"'));
  });

  test('כל job שמוריד את המסד מקבל את התג המוצמד', () {
    for (final (name, next) in const [
      ('build_windows', 'build_windows_arm64'),
      ('build_windows_arm64', 'build_linux'),
      ('build_linux', 'build_android'),
      ('build_macos', 'build_windows_installer'),
    ]) {
      final body = job(name, next);
      expect(
        body,
        contains('LIBRARY_DB_RELEASE_TAG: $tagOutput'),
        reason: name,
      );
      expect(body, contains('needs: [bump_version]'), reason: name);
    }
    expect('LIBRARY_DB_RELEASE_TAG: $tagOutput'.allMatches(workflow).length, 4);
  });

  test('חבילת Android המלאה לוקחת את הספרייה המוצמדת מ-build_linux', () {
    expect(
      job('build_android', 'build_android_full'),
      isNot(contains('LIBRARY')),
    );
    final full = job('build_android_full', 'build_macos');
    expect(full, contains('needs: [bump_version, build_android, build_linux]'));
    expect(full, contains('name: otzaria-library-parts'));
  });

  test('אף הורדה של המסד אינה נשענת על latest', () {
    final latest = RegExp(r'SeforimLibrary/releases/latest[^\s"]*');
    expect(latest.allMatches(workflow).map((m) => m.group(0)).toList(), [
      'SeforimLibrary/releases/latest',
    ], reason: 'רק שלב הפתרון ב-bump_version קורא את latest');
    for (final (name, next) in const [
      ('build_linux', 'build_android'),
      ('build_macos', 'build_windows_installer'),
    ]) {
      expect(job(name, next), contains('SEFORIM_LIBRARY_TAG: $tagOutput'));
      expect(
        job(name, next),
        contains('bash tool/release/download_library_db.sh'),
      );
    }
    expect('SEFORIM_LIBRARY_TAG: $tagOutput'.allMatches(workflow).length, 2);
    final downloader = read('tool/release/download_library_db.sh');
    expect(downloader, contains(r'tag=${SEFORIM_LIBRARY_TAG:-}'));
    expect(downloader, contains(r'download="$base/download/$tag"'));
  });

  test('האינדקס המאוחסן נלקח מאותו release כמו המסד', () {
    expect(
      job('build_linux', 'build_android'),
      contains(
        'PREBUILT_LIBRARY_INDEX_BASE_URL: '
        'https://github.com/Otzaria/SeforimLibrary/releases/download/$tagOutput',
      ),
    );
  });

  test('תג הספרייה נמצא ב-env של שני שלבי ההורדה ב-YAML תקין', () {
    final jobs = (loadYaml(workflow) as YamlMap)['jobs'] as YamlMap;
    for (final name in ['build_linux', 'build_macos']) {
      final steps = (jobs[name] as YamlMap)['steps'] as YamlList;
      final download = steps.cast<YamlMap>().singleWhere(
        (step) => (step['run'] as String? ?? '').contains(
          'bash tool/release/download_library_db.sh',
        ),
      );
      expect(
        (download['env'] as YamlMap)['SEFORIM_LIBRARY_TAG'],
        tagOutput,
        reason: name,
      );
    }
  });

  test('מתקין ה-FULL של Windows מוריד מהתג המוצמד ומוודא אותו', () {
    final script = read('installer/download_full_installer_assets.ps1');
    expect(script, contains(r'$env:LIBRARY_DB_RELEASE_TAG'));
    expect(script, contains(r'"$libraryReleases/tags/$libraryTag"'));
    expect(
      script,
      contains(r'$libraryRelease.tag_name -cne $libraryTag'),
      reason: 'release אחר מהתג המוצמד מכשיל את ההורדה',
    );
    expect(script, isNot(contains('SeforimLibrary/releases/latest')));
    expect(script, isNot(contains(r'$latestRelease')));
    expect(script, contains(r'$partAsset = $libraryRelease.assets'));
    expect(script, contains(r'$dbManifest = $libraryRelease.assets'));
  });
}
