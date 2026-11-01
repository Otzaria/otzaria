import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// השחרור נבנה כטיוטה: prepare_release יוצר אותה, כל job מעלה אליה את נכסיו,
/// ו-create_release מאמת ומפרסם בלי להוריד את הנכסים.
void main() {
  final workflow = File(
    '.github/workflows/build-and-announce.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final jobs = (loadYaml(workflow) as YamlMap)['jobs'] as YamlMap;

  YamlMap job(String name) => jobs[name] as YamlMap;
  List<YamlMap> steps(String name) =>
      (job(name)['steps'] as YamlList).cast<YamlMap>();
  YamlMap step(String jobName, String stepName) =>
      steps(jobName).singleWhere((s) => s['name'] == stepName);
  List<String> needs(String name) =>
      (job(name)['needs'] as YamlList).cast<String>();

  const uploaders = [
    'build_library_assets',
    'build_windows',
    'build_windows_arm64',
    'build_linux',
    'build_android',
    'build_android_full',
    'build_macos',
    'build_windows_installer',
  ];

  group('prepare_release', () {
    test('רץ בכל ריצת בנייה, כדי שהבניות התלויות בו לא ידלגו', () {
      expect(needs('prepare_release'), ['bump_version']);
      expect(job('prepare_release')['if'], "github.event_name != 'release'");
      for (final name in uploaders) {
        expect(needs(name), contains('prepare_release'), reason: name);
      }
      // הסימון create_release נבדק בשלבים, לא ב-if של ה-job.
      final gate = job('prepare_release')['env']['CREATE_RELEASE'] as String;
      for (final input in [
        'inputs.create_release',
        'inputs.build_windows',
        'inputs.build_linux',
        'inputs.build_android',
        'inputs.build_macos',
      ]) {
        expect(gate, contains(input));
      }
      for (final s in steps('prepare_release')) {
        expect(s['if'], "env.CREATE_RELEASE == 'true'", reason: s['name']);
      }
    });

    test('כישלונו אינו מדלג על הבניות, אבל חוסם את הפרסום', () {
      // הפריסה לחנויות תלויה ב-build_android, גם כשהשחרור נכשל.
      for (final name in [
        'build_library_assets',
        'build_windows',
        'build_windows_arm64',
        'build_linux',
        'build_android',
        'build_macos',
      ]) {
        final condition = job(name)['if'] as String;
        expect(needs(name), containsAll(['bump_version', 'prepare_release']));
        expect(condition, isNot(contains('needs.prepare_release')));
        for (final prepare in ['success', 'failure', 'skipped']) {
          expect(
            _evaluate(condition, {
              'needs.bump_version.result': 'success',
              'needs.prepare_release.result': prepare,
            }),
            isTrue,
            reason: '$name runs when prepare_release is $prepare',
          );
        }
        expect(
          _evaluate(condition, {'needs.bump_version.result': 'failure'}),
          isFalse,
          reason: '$name waits for bump_version',
        );
      }
      final create = job('create_release')['if'] as String;
      final ready = {
        for (final need in needs('create_release'))
          'needs.$need.result': 'success',
        "needs.prepare_release.outputs.release_id": '42',
      };
      expect(_evaluate(create, ready), isTrue);
      expect(
        _evaluate(create, {
          ...ready,
          'needs.prepare_release.result': 'failure',
        }),
        isFalse,
      );
      final run = step('prepare_release', 'Create the draft release')['run'];
      expect(run, contains('retry read_existing'));
      expect(run, contains(r'retry delete_draft "$id"'));
      expect(run, contains("grep -q 'HTTP 404'"));
      expect(run, contains('for attempt in 1 2 3; do'));
    });

    test('הפרסום מכל הענפים ממתין באותו תור ללא חסימת הבניות', () {
      expect((loadYaml(workflow) as YamlMap)['concurrency'], isNull);
      final concurrency = job('create_release')['concurrency'] as YamlMap;
      expect(concurrency['cancel-in-progress'], isFalse);
      expect(concurrency['group'], 'publish-release');
      expect(concurrency['queue'], 'max');
    });

    test('יוצר טיוטה ב-commit שנבנה, ומסרב לשחרור שכבר פורסם', () {
      final run = step('prepare_release', 'Create the draft release')['run'];
      expect(run, contains('-F draft=true'));
      expect(run, contains(r'-f target_commitish="$BUILD_SHA"'));
      expect(run, contains('-F prerelease=false'));
      expect(run, contains(r'select(.tag_name == \"$RELEASE_TAG\")'));
      // שחרור באותו תג שאינו טיוטה כבר פורסם.
      expect(
        run,
        contains(
          r"if grep -q ' false$' <<<"
          '"\$existing"; then',
        ),
      );
      expect(run, contains('is already published'));
      // טיוטה ישנה באותו תג נמחקת, ולא ממוחזרת.
      expect(
        run,
        contains(
          r"for id in $(awk '{print $1}' <<<"
          '"\$existing"',
        ),
      );
      expect(
        step('prepare_release', 'Get version from pubspec.yaml')['run'],
        contains('bash tool/version/release_tag.sh'),
      );
    });
  });

  group('העלאה מה-jobs', () {
    test('כל job מעלה דרך הסקריפט ורושם ארטיפקט רשומה משלו', () {
      for (final name in uploaders) {
        final upload = step(name, 'Upload release assets');
        expect(
          upload['run'],
          contains('bash tool/release/upload_release_assets.sh "\$RELEASE_ID"'),
          reason: name,
        );
        expect(upload['env']['GH_TOKEN'], r'${{ github.token }}');
        final record = step(name, 'Upload release record');
        expect(record['with']['path'], 'release-record/');
        expect(record['with']['overwrite'], isTrue, reason: name);
        // ההעלאה לטיוטה היא הסוף של ה-job (באנדרואיד — לפני הניקוי).
        final names = steps(name).map((s) => s['name']).toList();
        expect(
          names.indexOf('Upload release record'),
          names.indexOf('Upload release assets') + 1,
          reason: name,
        );
      }
      expect(
        steps('build_android').last['name'],
        'Final cleanup',
        reason: 'הניקוי מוחק את build/, ובו ה-APK',
      );
    });

    test('כל רשומה שה-create_release דורש נכתבת על ידי job', () {
      final verify =
          step('create_release', 'Verify the draft release')['run'] as String;
      final required = <String>[
        ...RegExp(r'required=\(([^)]*)\)').firstMatch(verify)![1]!.split(' '),
        for (final target in ['deb', 'rpm', 'raw', 'full'])
          for (final arch in ['x86_64', 'aarch64']) 'linux-$target-$arch',
        'windows-arm64',
      ];
      expect(verify, contains('for target in deb rpm raw full; do'));
      expect(verify, contains('for arch in x86_64 aarch64; do'));
      expect(verify, contains('required+=(windows-arm64)'));

      final written = <String>{};
      for (final MapEntry(:key, :value) in jobs.entries) {
        for (final s in ((value as YamlMap)['steps'] as YamlList? ?? [])) {
          final name = (s as YamlMap)['with']?['name'];
          if (name is! String || !name.startsWith('otzaria-release-record-')) {
            continue;
          }
          if (key == 'build_linux') {
            for (final target in ['deb', 'rpm', 'raw', 'full']) {
              for (final arch in ['x86_64', 'aarch64']) {
                written.add(
                  name
                      .replaceAll(r'${{ matrix.target }}', target)
                      .replaceAll(r'${{ matrix.arch }}', arch),
                );
              }
            }
          } else {
            written.add(name);
          }
        }
      }
      for (final record in required) {
        expect(written, contains('otzaria-release-record-$record'));
      }
    });

    test(
      'build_linux: השלבים החדשים אחרי חבילת ה-raw, בלי תנאי שאינו מסווג',
      () {
        // extract_app_build_steps.py שב-SeforimLibrary משחזר את build_linux עד
        // "Find and prepare Linux packages" ומסווג את תנאי השלבים שלו.
        final names = steps('build_linux').map((s) => s['name']).toList();
        final raw = names.indexOf('Find and prepare Linux packages');
        for (final added in [
          'Upload release assets',
          'Upload release record',
        ]) {
          expect(names.indexOf(added), greaterThan(raw), reason: added);
          expect(step('build_linux', added)['if'], isNull, reason: added);
        }
        expect(
          step('build_linux', 'Upload release assets')['run'],
          contains('if [ -z "\$RELEASE_ID" ]; then'),
        );
        expect(
          step(
            'build_linux',
            'Upload release record',
          )['with']['if-no-files-found'],
          'ignore',
        );
      },
    );
  });

  group('create_release', () {
    test('אינו מוריד את הנכסים — רק את הרשומות', () {
      final downloads = steps('create_release')
          .where((s) => '${s['uses']}'.startsWith('actions/download-artifact'))
          .toList();
      expect(downloads, hasLength(1));
      expect(downloads.single['with']['pattern'], 'otzaria-release-record-*');
      expect(workflow, isNot(contains('Download all artifacts')));
      expect(workflow, isNot(contains('softprops/action-gh-release')));
    });

    test('מאמת, בונה מניפסט והערות, ורק אז מפרסם', () {
      final names = steps('create_release').map((s) => s['name']).toList();
      final order = [
        'Verify the draft release',
        'Generate release manifest',
        'Upload the release manifest',
        'Generate release notes',
        'Publish the release',
      ].map(names.indexOf).toList();
      expect(order.every((i) => i >= 0), isTrue, reason: '$names');
      for (var i = 1; i < order.length; i++) {
        expect(order[i], greaterThan(order[i - 1]));
      }
      expect(names.last, 'Publish the release');
    });

    // published של GITHUB_TOKEN אינו מפעיל workflow: אחרת ה-release:published
    // של ה-workflow הזה היה שולח הכרזה שנייה.
    test('מפרסם ב-GITHUB_TOKEN, ולכן ההכרזה נשלחת פעם אחת', () {
      final publish = step('create_release', 'Publish the release');
      expect(publish['env']['GH_TOKEN'], r'${{ github.token }}');
      expect(publish['run'], contains('latest_release_policy.py --publish'));
      expect(publish['id'], 'publish');
      expect(
        publish['run'],
        contains(
          r'--title "$RELEASE_TITLE" --body-file release-body.md',
        ),
      );
      expect(needs('announce_release'), contains('create_release'));
      final on = (loadYaml(workflow) as YamlMap)['on'] as YamlMap;
      expect(on['release']['types'], ['published']);
    });

    test('חבילות העדכון אינן תנאי לפרסום', () {
      final condition = job('create_release')['if'] as String;
      expect(
        condition,
        contains("needs.prepare_release.outputs.release_id != ''"),
      );
      for (final name in [
        'update_packages_windows',
        'update_packages_linux',
        'update_packages_macos',
      ]) {
        expect(needs('create_release'), contains(name));
        expect(condition, isNot(contains(name)));
        expect(job(name)['if'], contains('!cancelled()'));
      }
    });
  });
}

/// מעריך תנאי `if` של job בהרצה ידנית שמבקשת את כל הבניות: `!cancelled()` אמת,
/// כל `inputs.*` אמת, ו-[values] נותן את ערכי ה-`needs` (חסר = 'success').
bool _evaluate(String condition, Map<String, String> values) {
  final tokens = RegExp(
    r"\s*(!cancelled\(\)|&&|\|\||==|!=|!|\(|\)|'[^']*'|[A-Za-z_][\w.-]*)",
  ).allMatches(condition).map((m) => m[1]!).toList();
  var at = 0;

  Object? value(String token) {
    if (token == '!cancelled()') return true;
    if (token.startsWith("'")) return token.substring(1, token.length - 1);
    if (token == 'github.event_name') return 'workflow_dispatch';
    if (token.startsWith('inputs.')) return true;
    if (token.startsWith('needs.')) return values[token] ?? 'success';
    throw StateError('unknown token $token in $condition');
  }

  bool truthy(Object? v) => v is bool ? v : (v as String).isNotEmpty;

  late Object? Function() or;
  Object? unary() {
    final token = tokens[at++];
    if (token == '!') return !truthy(unary());
    if (token == '(') {
      final inner = or();
      at++;
      return inner;
    }
    return value(token);
  }

  Object? compare() {
    var left = unary();
    while (at < tokens.length && (tokens[at] == '==' || tokens[at] == '!=')) {
      final equal = tokens[at++] == '==';
      final right = unary();
      left = (left == right) == equal;
    }
    return left;
  }

  Object? and() {
    var left = compare();
    while (at < tokens.length && tokens[at] == '&&') {
      at++;
      final right = compare();
      left = truthy(left) && truthy(right);
    }
    return left;
  }

  or = () {
    var left = and();
    while (at < tokens.length && tokens[at] == '||') {
      at++;
      final right = and();
      left = truthy(left) || truthy(right);
    }
    return left;
  };

  final result = truthy(or());
  expect(at, tokens.length, reason: condition);
  return result;
}
