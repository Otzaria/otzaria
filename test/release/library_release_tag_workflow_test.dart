import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
      ('build_android', 'build_macos'),
      ('build_macos', 'build_windows_indexed_full'),
    ]) {
      final body = job(name, next);
      expect(
        body,
        contains('LIBRARY_DB_RELEASE_TAG: $tagOutput'),
        reason: name,
      );
      expect(body, contains('needs: [bump_version]'), reason: name);
    }
    expect('LIBRARY_DB_RELEASE_TAG: $tagOutput'.allMatches(workflow).length, 5);
  });

  test('אף הורדה של המסד אינה נשענת על latest', () {
    final latest = RegExp(r'SeforimLibrary/releases/latest[^\s"]*');
    expect(latest.allMatches(workflow).map((m) => m.group(0)).toList(), [
      'SeforimLibrary/releases/latest',
    ], reason: 'רק שלב הפתרון ב-bump_version קורא את latest');
    expect(
      RegExp(r'"\$library_release/seforim(-schema6)?\.db\.zst"')
          .allMatches(workflow)
          .length,
      6,
      reason: 'Linux, Android ו-macOS: seforim-schema6.db.zst ונסיגה ל-seforim.db.zst',
    );
    expect(
      'releases/download/'
              r'${LIBRARY_DB_RELEASE_TAG:?library release tag was not resolved}'
          .allMatches(workflow)
          .length,
      3,
    );
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
  });
}
