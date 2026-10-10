import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _bashReleaseTag =
    r'''tag=$(bash tool/version/release_tag.sh "$version" '${{ github.ref }}' '${{ github.run_number }}')''';
const _pwshReleaseTag =
    r"$tag = & ./tool/version/release_tag.ps1 $version '${{ github.ref }}' '${{ github.run_number }}'";

/// מסייע ההורדה ל-macOS נבנה בסוף `build_macos`, ואינו יכול לחסום שחרור.
void main() {
  final workflow = File(
    '.github/workflows/build-and-announce.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final buildScript = File(
    'tool/download_assistant/macos/build_app.sh',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  const testStep = 'Test macOS Download Assistant (non-fatal helper tool)';
  const buildStep = 'Build macOS Download Assistant (non-fatal helper tool)';
  const uploadStep = 'Upload macOS Download Assistant';

  int indexOfStep(String name) {
    final at = workflow.indexOf('- name: $name');
    expect(at, greaterThan(-1), reason: 'השלב "$name" אינו ב-workflow');
    return at;
  }

  /// גוף השלב — עד השלב הבא או עד ה-job הבא.
  String stepBody(String name) {
    final start = indexOfStep(name);
    final rest = workflow.substring(start + 1);
    final nextStep = rest.indexOf('\n      - name: ');
    final nextJob = RegExp(r'\n  [a-z_]+:\n').firstMatch(rest)?.start ?? -1;
    final ends = [nextStep, nextJob].where((i) => i >= 0);
    final end = ends.isEmpty
        ? rest.length
        : ends.reduce((a, b) => a < b ? a : b);
    return workflow.substring(start, start + 1 + end);
  }

  group('מסייע ההורדה ל-macOS ב-workflow', () {
    test('השלבים יושבים בסוף build_macos, אחרי העלאת חבילת ה-FULL', () {
      final job = workflow.indexOf('\n  build_macos:\n');
      final nextJob = workflow.indexOf('\n  build_windows_installer:\n');
      final fullUpload = indexOfStep('Upload macOS FULL bundle');
      expect(job, greaterThan(-1));
      expect(fullUpload, greaterThan(job));
      expect(indexOfStep(testStep), greaterThan(fullUpload));
      expect(indexOfStep(buildStep), greaterThan(indexOfStep(testStep)));
      expect(indexOfStep(uploadStep), greaterThan(indexOfStep(buildStep)));
      expect(indexOfStep(uploadStep), lessThan(nextJob));
    });

    test('בדיקה, בנייה והעלאה אינן יכולות להפיל את השחרור', () {
      for (final name in [testStep, buildStep, uploadStep]) {
        expect(
          stepBody(name),
          contains('continue-on-error: true'),
          reason: name,
        );
        // continue-on-error אינו מכסה תקיעה: בלי זמן קצוב היא הייתה מעכבת את create_release.
        expect(
          stepBody(name),
          contains('timeout-minutes: 15'),
          reason: name,
        );
      }
      expect(stepBody(testStep), contains('run: swift test'));
      expect(
        stepBody(testStep),
        contains('working-directory: tool/download_assistant/macos'),
      );
      expect(
        stepBody(buildStep),
        contains(
          "if: steps.download_assistant_macos_test.outcome == 'success'",
        ),
      );
      expect(
        stepBody(uploadStep),
        contains("if: steps.download_assistant_macos.outcome == 'success'"),
      );
    });

    test('הארטיפקט ושם הנכס הם אלה של החוזה', () {
      final upload = stepBody(uploadStep);
      expect(upload, contains('name: otzaria-download-assistant-macos\n'));
      expect(upload, contains('Otzaria-Download-Assistant-macos.zip'));
      expect(
        buildScript,
        contains('ZIP_NAME="Otzaria-Download-Assistant-macos.zip"'),
      );
      expect(buildScript, contains('ditto -c -k --keepParent'));
    });

    test('התג מועבר במשתנה סביבה, באותו כלל של מסייע Windows', () {
      final build = stepBody(buildStep);
      expect(build, contains('export OTZARIA_ASSISTANT_RELEASE_TAG="\$tag"'));
      expect(build, contains(_bashReleaseTag));
      expect(
        build,
        contains('bash tool/download_assistant/macos/build_app.sh'),
      );
      expect(
        build,
        isNot(contains('build_app.sh "\$OTZARIA_ASSISTANT_RELEASE_TAG"')),
      );

      final windows = stepBody(
        'Build Download Assistant (non-fatal helper tool)',
      );
      expect(windows, contains(_pwshReleaseTag));
    });
  });

  group('build_app.sh', () {
    test('התג נבדק מול רשימת תווים סגורה לפני שנכתב לקובץ מקור', () {
      final check = buildScript.indexOf(r'=~ ^[0-9A-Za-z.+_-]*$');
      final write = buildScript.indexOf('let embeddedReleaseTag = "\$TAG"');
      expect(check, greaterThan(-1));
      expect(write, greaterThan(check));
      expect(buildScript, contains('OTZARIA_ASSISTANT_RELEASE_TAG'));
    });

    test('Universal, חתימה ad-hoc ורצפת macOS 12', () {
      expect(
        buildScript,
        contains('swift build -c release --arch arm64 --arch x86_64'),
      );
      expect(buildScript, contains('lipo -archs'));
      expect(buildScript, contains('codesign --force --sign -'));
      expect(buildScript, contains('<string>12.0</string>'));
      expect(buildScript, contains('<string>he</string>'));
      expect(buildScript, contains('מסייע הורדה לאוצריא'));
    });

    test('CFBundleVersion כולל את מספר הריצה, ו-CFBundleName קצר', () {
      expect(buildScript, contains(r'BUILD_NUMBER="$VERSION.$RUN"'));
      expect(
        buildScript,
        contains(
          '<key>CFBundleVersion</key>\n  <string>\$BUILD_NUMBER</string>',
        ),
      );
      final name = RegExp(
        r'<key>CFBundleName</key>\n  <string>([^<]*)</string>',
      ).firstMatch(buildScript)!.group(1)!;
      expect(name.length, lessThanOrEqualTo(15));
    });

    test('מוחק רק את מה שהוא יוצר, לא את תיקיית הפלט', () {
      expect(buildScript, isNot(contains('rm -rf "\$OUT_DIR"\n')));
      expect(buildScript, contains(r'rm -rf "$APP" "$OUT_DIR/$ZIP_NAME"'));
      expect(
        buildScript.indexOf(r'OUT_DIR="$(cd "$OUT_DIR" && pwd)"'),
        lessThan(buildScript.indexOf('cd "\$HERE"\n')),
      );
    });

    test('קובץ התג שבמאגר ריק — בנייה מקומית נופלת ל-latest', () {
      final buildInfo = File(
        'tool/download_assistant/macos/Sources/DownloadAssistant/BuildInfo.generated.swift',
      ).readAsStringSync();
      expect(buildInfo, contains('let embeddedReleaseTag = ""'));
    });
  });
}
