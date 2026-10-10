import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

bool _hasCommand(String name) {
  try {
    return Process.runSync(name, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  final hasPwsh = _hasCommand('pwsh');
  final hasJq = _hasCommand('jq');

  // העותק בתיקייה זמנית קורא את version.json שלצדו, כמו בסקריפט האמיתי.
  Future<ProcessResult> runTag(
    String script,
    Map<String, Object> versionJson,
    List<String> args,
  ) async {
    final dir = Directory.systemTemp.createTempSync('otzaria_release_tag_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'version.json')).writeAsStringSync(
      jsonEncode(versionJson),
    );
    final copy = p.join(dir.path, p.basename(script));
    File(script).copySync(copy);
    return script.endsWith('.ps1')
        ? Process.run('pwsh', ['-NoLogo', '-NoProfile', '-File', copy, ...args])
        : Process.run('bash', [copy, ...args]);
  }

  for (final script in [
    'tool/version/release_tag.sh',
    'tool/version/release_tag.ps1',
  ]) {
    group('$script (issue #1547)', () {
      final skip = script.endsWith('.ps1') && !hasPwsh ? 'pwsh חסר' : false;

      for (final (hotfix, ref, expected) in [
        (0, 'refs/heads/main', '0.9.98'),
        (0, 'refs/heads/dev', '0.9.98+800'),
        (2, 'refs/heads/main', '0.9.98.2'),
        (2, 'refs/heads/dev', '0.9.98.2+800'),
      ]) {
        test('hotfix $hotfix על $ref → $expected', () async {
          final result = await runTag(
            script,
            {'version': '0.9.98', 'hotfix': hotfix},
            ['0.9.98', ref, '800'],
          );
          expect(result.exitCode, 0, reason: '${result.stderr}');
          expect((result.stdout as String).trim(), expected);
        }, skip: skip);
      }

      test('בלי שדה hotfix — פורמט רגיל', () async {
        final result = await runTag(
          script,
          {'version': '0.9.98'},
          ['0.9.98', 'refs/heads/main', '800'],
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect((result.stdout as String).trim(), '0.9.98');
      }, skip: skip);

      test('גרסה שאינה תואמת את version.json נכשלת', () async {
        final result = await runTag(
          script,
          {'version': '0.9.98', 'hotfix': 1},
          ['0.9.97', 'refs/heads/main', '800'],
        );
        expect(result.exitCode, isNot(0));
        expect((result.stdout as String).trim(), isEmpty);
      }, skip: skip);

      test('hotfix מחוץ לטווח נכשל', () async {
        final result = await runTag(
          script,
          {'version': '0.9.98', 'hotfix': 100},
          ['0.9.98', 'refs/heads/main', '800'],
        );
        expect(result.exitCode, isNot(0));
      }, skip: skip);
    });
  }

  test('כל חישובי התג ב-workflow עוברים דרך הסקריפט המשותף (issue #1547)', () {
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync();
    expect(
      RegExp(r'tool/version/release_tag\.(sh|ps1)').allMatches(workflow).length,
      12,
      reason: 'חותם ומניפסט בכל פלטפורמה, מסייעי ההורדה ו-create_release',
    );
    expect(workflow, isNot(contains(r'"$version+${{ github.run_number }}"')));
    expect(
      workflow,
      isNot(contains(r'tag="${version}+${{ github.run_number }}"')),
    );
    expect(workflow, isNot(contains(r'"$version+$env:GITHUB_RUN_NUMBER"')));
    expect(workflow, isNot(contains(r'tag=$VERSION+${{ github.run_number }}')));
  });

  test(
    'מיון שחרורי הבסיס ממקם hotfix בין גרסתו לגרסה הבאה (issue #1547)',
    () async {
      final script = File(
        'tool/release/build_update_packages.sh',
      ).readAsStringSync();
      final start = script.indexOf("--jq '") + "--jq '".length;
      final end = script.indexOf("' |", start);
      final program = script.substring(start, end);
      final releases = [
        for (final (tag, pre) in [
          ('0.9.97+789', true),
          ('0.9.98+800', true),
          ('0.9.97.2+790', true),
          ('0.9.97', false),
          ('0.9.97.2', false),
          ('0.9.96+700', true),
          ('0.10.0', false),
        ])
          {'tagName': tag, 'isDraft': false, 'isPrerelease': pre},
      ];
      final process = await Process.start('jq', ['-r', program]);
      process.stdin.write(jsonEncode(releases));
      await process.stdin.close();
      final out = await process.stdout.transform(utf8.decoder).join();
      expect(await process.exitCode, 0);
      expect(out.trim().split('\n').map((line) => line.split(' ').first), [
        '0.10.0',
        '0.9.98+800',
        '0.9.97.2+790',
        '0.9.97.2',
        '0.9.97+789',
        '0.9.97',
        '0.9.96+700',
      ]);
    },
    skip: hasJq ? false : 'jq חסר',
  );
}
