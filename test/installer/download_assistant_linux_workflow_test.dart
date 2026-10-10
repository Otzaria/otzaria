import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _bashReleaseTag =
    r'''tag=$(bash tool/version/release_tag.sh "$version" '${{ github.ref }}' '${{ github.run_number }}')''';
const _pwshReleaseTag =
    r"$tag = & ./tool/version/release_tag.ps1 $version '${{ github.ref }}' '${{ github.run_number }}'";

/// מסייע ההורדה ל-Linux ב-workflow: נבנה בסוף `build_linux` רק במטריצה `raw`,
/// אינו חוסם שחרור, ושמות הארטיפקט והנכס תואמים לטבלה ב-docs/download_assistant.md.
void main() {
  final workflow = File(
    '.github/workflows/build-and-announce.yml',
  ).readAsStringSync();
  final makefile = File(
    'tool/download_assistant/linux/Makefile',
  ).readAsStringSync();

  const buildName = 'Build Linux Download Assistant (non-fatal helper tool)';
  const uploadName = 'Upload Linux Download Assistant';

  int indexOfStep(String name) {
    final at = workflow.indexOf('      - name: $name\n');
    expect(at, greaterThan(-1), reason: 'השלב "$name" אינו ב-workflow');
    return at;
  }

  /// גוף השלב עד השלב הבא או עד ה-job הבא.
  String step(String name) {
    final start = indexOfStep(name);
    final ends = [
      workflow.indexOf('\n      - name: ', start + 1),
      workflow.indexOf(RegExp(r'\n  [a-z_]+:\n'), start + 1),
    ].where((i) => i > -1);
    return workflow.substring(start, ends.reduce((a, b) => a < b ? a : b));
  }

  String resolveArch(String text, String arch) => text.replaceAll(
    "\${{ matrix.arch == 'aarch64' && 'arm64' || 'x64' }}",
    arch == 'aarch64' ? 'arm64' : 'x64',
  );

  test('השלבים יושבים בסוף build_linux, אחרי העלאת מניפסטי הספרייה', () {
    final job = workflow.indexOf('\n  build_linux:\n');
    final nextJob = workflow.indexOf('\n  build_android:\n');
    final manifestUpload = indexOfStep(
      'Upload library manifests for installer build',
    );
    final build = indexOfStep(buildName);
    final upload = indexOfStep(uploadName);
    expect(job, greaterThan(-1));
    expect(manifestUpload, greaterThan(job));
    expect(build, greaterThan(manifestUpload));
    expect(upload, greaterThan(build));
    expect(nextJob, greaterThan(upload));
    expect(
      workflow.substring(upload + 1, nextJob),
      isNot(contains('\n      - name: ')),
      reason: 'ההעלאה היא השלב האחרון של build_linux',
    );
    // x64 ו-ARM64 מגיעים מאותה מטריצה — לא job נוסף.
    expect(workflow, contains("arch: [x86_64, aarch64]"));
  });

  test('הבנייה רק במטריצה raw, ואינה חוסמת שחרור', () {
    final build = step(buildName);
    expect(build, contains("if: matrix.target == 'raw'\n"));
    expect(build, contains('continue-on-error: true'));
    expect(build, contains('id: download_assistant_linux'));
    // continue-on-error אינו מכסה תקיעה, שהייתה מעכבת את create_release.
    expect(build, contains('timeout-minutes: 15'));
    expect(step(uploadName), contains('timeout-minutes: 15'));

    final upload = step(uploadName);
    expect(
      upload,
      contains(
        "if: matrix.target == 'raw' && "
        "steps.download_assistant_linux.outcome == 'success'",
      ),
    );
    expect(upload, contains('continue-on-error: true'));
  });

  test('בדיקות, בנייה, בדיקת NEEDED, הרצת עשן ואריזה — בסדר הזה', () {
    final build = step(buildName);
    final order = [
      'make test',
      '\n          make\n',
      'make check-needed',
      'xvfb-run -a ./build/Otzaria-Download-Assistant --self-test',
      'make dist DIST_ARCH=',
    ].map(build.indexOf).toList();
    expect(order.every((i) => i > -1), isTrue, reason: build);
    for (var i = 1; i < order.length; i++) {
      expect(order[i], greaterThan(order[i - 1]));
    }
    expect(
      build,
      contains('unset LIBRARY_PATH LD_LIBRARY_PATH PKG_CONFIG_PATH'),
    );
  });

  test('התג מוטבע דרך משתנה סביבה, באותו כלל של מסייע Windows', () {
    final build = step(buildName);
    expect(build, contains(r'export OTZARIA_ASSISTANT_RELEASE_TAG="$tag"'));
    expect(build, contains(_bashReleaseTag));
    expect(build, isNot(contains('make OTZARIA_ASSISTANT_RELEASE_TAG')));

    final windows = step('Build Download Assistant (non-fatal helper tool)');
    expect(windows, contains(_pwshReleaseTag));
  });

  test('שמות הארטיפקט והנכס תואמים לטבלה ולשלב ה-Stage', () {
    final upload = step(uploadName);
    final stage = step('Stage Download Assistant');
    for (final arch in ['x86_64', 'aarch64']) {
      final suffix = arch == 'aarch64' ? 'arm64' : 'x64';
      final resolved = resolveArch(upload, arch);
      expect(
        resolved,
        contains('name: otzaria-download-assistant-linux-$suffix\n'),
      );
      expect(
        resolved,
        contains(
          'path: tool/download_assistant/linux/build/'
          'Otzaria-Download-Assistant-linux-$suffix.tar.gz\n',
        ),
      );
      expect(
        stage,
        contains(
          'artifacts/otzaria-download-assistant-linux-$suffix/'
          'Otzaria-Download-Assistant-linux-$suffix.tar.gz',
        ),
      );
    }
  });

  test('הארכיון מכיל Otzaria-Download-Assistant/Otzaria-Download-Assistant', () {
    expect(
      makefile,
      contains(
        r'$(BUILD)/dist/Otzaria-Download-Assistant/Otzaria-Download-Assistant',
      ),
    );
    expect(
      makefile,
      contains(r'Otzaria-Download-Assistant-linux-$(DIST_ARCH).tar.gz'),
    );
    // רק GTK3 ומה שהוא מושך: אין libcurl, libsoup או json-glib.
    final allowed = RegExp(r'ALLOWED_NEEDED := (.*)').firstMatch(makefile)!;
    for (final forbidden in ['curl', 'soup', 'json-glib', 'ssl', 'crypto']) {
      expect(allowed.group(1), isNot(contains(forbidden)));
    }
  });

  test('סקריפט התג שומר על "+" ודוחה מרכאות', () async {
    final temp = Directory.systemTemp.createTempSync('otzaria_linux_tag_');
    addTearDown(() async {
      // WSL's bash may release the working directory a moment after exiting.
      for (var attempt = 0; attempt < 20 && temp.existsSync(); attempt++) {
        try {
          temp.deleteSync(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    });
    final script = File(
      'tool/download_assistant/linux/gen_build_info.sh',
    ).readAsStringSync();

    // stdin + relative path: on Windows `bash` may be WSL's, which sees neither
    // Windows paths nor the environment unless it is listed in WSLENV.
    Future<int> generate(String tag, String out) async {
      final process = await Process.start(
        'bash',
        ['-s', out],
        workingDirectory: temp.path,
        environment: {
          'OTZARIA_ASSISTANT_RELEASE_TAG': tag,
          'WSLENV': 'OTZARIA_ASSISTANT_RELEASE_TAG',
        },
      );
      process.stdin.write(script);
      await process.stdin.close();
      await process.stdout.drain<void>();
      await process.stderr.drain<void>();
      return process.exitCode;
    }

    expect(await generate('0.10.3+143', 'ok.h'), 0);
    expect(
      File(p.join(temp.path, 'ok.h')).readAsStringSync(),
      contains('#define OTZ_EMBEDDED_RELEASE_TAG "0.10.3+143"'),
    );

    for (final bad in ['0.10.3"x', r'0.10\3', '0.10 3', r'$(id)']) {
      expect(await generate(bad, 'bad.h'), isNot(0), reason: 'accepted: $bad');
    }
  });
}
