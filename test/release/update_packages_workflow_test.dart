import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/generate_app_file_manifest.dart';
import '../../tool/release/generate_update_package.dart';

const _bashReleaseTag =
    r'''tag=$(bash tool/version/release_tag.sh "$version" '${{ github.ref }}' '${{ github.run_number }}')''';
const _pwshReleaseTag =
    r"$tag = & ./tool/version/release_tag.ps1 $version '${{ github.ref }}' '${{ github.run_number }}'";

void main() {
  final workflow = File(
    '.github/workflows/build-and-announce.yml',
  ).readAsStringSync();
  final script = File(
    'tool/release/build_update_packages.sh',
  ).readAsStringSync();

  int indexOfStep(String name) {
    final at = workflow.indexOf('- name: $name');
    expect(at, greaterThan(-1), reason: 'השלב "$name" אינו ב-workflow');
    return at;
  }

  group('zstd לעדכון המצומצם', () {
    test('מועתק מההורדה הקיימת לתיקיית הבנייה, בלי הורדה שנייה', () {
      final stage = indexOfStep('Stage zstd for small updates (x64)');
      // הבינארי כבר ירד בשביל המתקין המלא — השלב מעתיק אותו בלבד.
      expect(
        workflow.indexOf('- name: Download library assets for full installer'),
        lessThan(stage),
      );
      expect(
        workflow.substring(stage, stage + 900),
        contains(r'Copy-Item installer\zstd.exe'),
      );
      // מקור ההורדה היחיד הוא הסקריפט המשותף שה-job של x64 מריץ.
      final x64Job = workflow.substring(
        0,
        workflow.indexOf('\n  build_windows_arm64:'),
      );
      expect('zstd-*-win64.zip'.allMatches(x64Job), isEmpty);
      expect(x64Job, contains('download_full_installer_assets.ps1'));
      expect(
        'zstd-*-win64.zip'
            .allMatches(
              File(
                'installer/download_full_installer_assets.ps1',
              ).readAsStringSync(),
            )
            .length,
        1,
        reason: 'ב-job של x64 יש מקור הורדה אחד ל-zstd',
      );
    });

    test('נכנס גם למתקין וגם ל-ZIP, ולכן גם למניפסט', () {
      final stage = indexOfStep('Stage zstd for small updates (x64)');
      final step = workflow.substring(stage, stage + 900);
      expect(step, contains(r'build\windows\x64\runner\Release\zstd.exe'));
      expect(step, contains('Compress-Archive'));
      expect(step, contains('otzaria-windows.zip'));
      // המתקין נבנה אחרי ההעתקה ואורז את אותה תיקייה.
      expect(stage, lessThan(indexOfStep('Build Inno Setup installer')));
      expect(
        stage,
        lessThan(indexOfStep('Generate application file manifest (x64)')),
      );
    });

    test('ARM64 מקבל את אותו בינארי x64, לפני האריזה', () {
      // אין zstd ל-Windows ARM64 בשחרורי facebook/zstd, ו-Windows on ARM
      // מריץ x64 באמולציה — כמה מגה-בתים לעדכון, האטה חסרת משמעות.
      // הגדרת ה-job, לא הקלט שנושא את אותו שם ב-workflow_dispatch.
      final arm64Job = workflow.substring(
        workflow.indexOf('\n  build_windows_arm64:'),
        workflow.indexOf('\n  build_linux:'),
      );
      expect(arm64Job, contains('zstd-*-win64.zip'));
      expect(
        arm64Job,
        contains(r'build\windows\arm64\runner\Release\zstd.exe'),
      );

      final stage = indexOfStep('Stage zstd for small updates (ARM64)');
      expect(stage, lessThan(indexOfStep('Zip Windows ARM64 build')));
      expect(
        stage,
        lessThan(indexOfStep('Build regular installer (ARM64)')),
      );
      expect(
        stage,
        lessThan(indexOfStep('Generate application file manifest (ARM64)')),
      );
    });
  });

  group('חותם השחרור בתיקיית ההתקנה', () {
    test('נכתב לתיקיית הבנייה לפני האריזה, בשתי הארכיטקטורות', () {
      for (final (step, dir, arch) in [
        ('Stamp installed release (x64)', r'build\windows\x64', 'x64'),
        ('Stamp installed release (ARM64)', r'build\windows\arm64', 'arm64'),
      ]) {
        final at = indexOfStep(step);
        final body = workflow.substring(at, at + 900);
        expect(body, contains('generate_app_file_manifest.dart --stamp'));
        expect(body, contains('$dir\\runner\\Release'));
        expect(body, contains('--architecture $arch'));
        // התג בא מהסקריפט המשותף — בדיוק מה שהלקוח מחפש.
        expect(body, contains(_pwshReleaseTag));
        expect(body, contains('continue-on-error: true'), reason: step);
      }
    });

    test('קודם לאריזה, למתקין ולמניפסט — ולכן נכנס לשלושתם', () {
      final x64 = indexOfStep('Stamp installed release (x64)');
      expect(x64, greaterThan(indexOfStep('Build Flutter Windows app')));
      expect(x64, lessThan(indexOfStep('Zip Windows build')));
      expect(x64, lessThan(indexOfStep('Build Inno Setup installer')));
      expect(
        x64,
        lessThan(indexOfStep('Generate application file manifest (x64)')),
      );

      final arm = indexOfStep('Stamp installed release (ARM64)');
      expect(arm, lessThan(indexOfStep('Zip Windows ARM64 build')));
      expect(arm, lessThan(indexOfStep('Build regular installer (ARM64)')));
      expect(
        arm,
        lessThan(indexOfStep('Generate application file manifest (ARM64)')),
      );
    });

    test('התג בחותם הוא בדיוק התג שהשחרור מקבל', () {
      // החותם הוא הבסיס שחבילת העדכון נבנית ממנו; תג אחר = אין חבילה בשם.
      expect(
        workflow,
        contains(
          r'''TAG=$(bash tool/version/release_tag.sh "$VERSION" '${{ github.ref }}' '${{ github.run_number }}')''',
        ),
      );
      expect(
        _pwshReleaseTag.allMatches(workflow).length +
            _bashReleaseTag.allMatches(workflow).length,
        11,
        reason:
            'חותם ומניפסט ב-Windows (שתי ארכיטקטורות), ב-macOS וב-Linux, '
            'ומסייעי ההורדה',
      );
    });

    test('שם החותם זהה לשם שהכלי כותב', () {
      expect(workflow, isNot(contains('otzaria-release-stamp')));
      expect(kInstalledReleaseFileName, 'otzaria-release.json');
    });
  });

  group('חיווט העדכון הדיפרנציאלי ל-CI', () {
    test('מניפסט קובצי ההתקנה נבנה בשני ה-jobs של ווינדוס', () {
      expect(
        workflow,
        contains('tool/release/generate_app_file_manifest.dart'),
      );
      expect(workflow, contains(r'build\windows\x64\runner\Release'));
      expect(workflow, contains(r'build\windows\arm64\runner\Release'));
      expect(workflow, contains('--architecture x64'));
      expect(workflow, contains('--architecture arm64'));
    });

    test('שם הנכס בעבודה זהה לשם שהגנרטור מפיק', () {
      for (final arch in ['x64', 'arm64']) {
        final name = appFileManifestAssetName(
          platform: 'windows',
          architecture: arch,
        );
        expect(workflow, contains(name), reason: arch);
      }
      // הסקריפט מרכיב את השם מהפלטפורמה ומהארכיטקטורה, כמו הגנרטור.
      expect(
        script,
        contains(
          r'manifest_asset="otzaria-app-files-${platform}-${arch}.json"',
        ),
      );
      for (final (platform, arch) in [
        ('macos', 'universal'),
        ('linux', 'x64'),
        ('linux', 'arm64'),
      ]) {
        final name = appFileManifestAssetName(
          platform: platform,
          architecture: arch,
        );
        expect(workflow, contains(name), reason: name);
      }
    });

    test('המניפסטים מוכנסים ל-release-files לפני יצירת השחרור', () {
      final stage = indexOfStep('Stage application file manifests');
      expect(stage, greaterThan(indexOfStep('Organize release files')));
      expect(stage, lessThan(indexOfStep('Generate release manifest')));
      expect(stage, lessThan(indexOfStep('Create Release')));
    });

    test('חבילות העדכון נבנות אחרי יצירת השחרור ואינן יכולות להפיל אותו', () {
      final publish = indexOfStep('Publish differential update packages');
      expect(publish, greaterThan(indexOfStep('Create Release')));
      expect(
        workflow.substring(publish, publish + 400),
        contains('continue-on-error: true'),
      );
    });

    test('כל שלב חדש אינו פטאלי', () {
      for (final name in [
        'Generate application file manifest (x64)',
        'Generate application file manifest (ARM64)',
        'Publish differential update packages',
      ]) {
        final at = indexOfStep(name);
        expect(
          workflow.substring(at, at + 300),
          contains('continue-on-error: true'),
          reason: name,
        );
      }
    });

    test('שלבי ההעלאה של היום לא נגעו', () {
      for (final asset in [
        'otzaria-windows-zip',
        'otzaria-windows_arm64.zip',
        'otzaria-windows-installer',
        'otzaria-windows-arm64-installer',
        'otzaria-download-assistant',
        'otzaria-release-manifest.json',
      ]) {
        expect(workflow, contains(asset), reason: asset);
      }
    });

    test('מאגר היעד ומדיניות זוגות הגרסאות מוצהרים במפורש', () {
      // נכסים באותו release, עם GITHUB_TOKEN בלבד — בלי סוד נוסף.
      expect(workflow, isNot(contains('UPDATE_PACKAGES_TOKEN')));
      expect(workflow, isNot(contains('otzaria-updates')));
      // הארגומנט האחרון לסקריפט הוא מספר הבסיסים.
      expect(
        workflow,
        contains(
          '"\$arch" "\$RELEASE_TAG" "\$manifest" "\$zip" update-packages '
          '$kUpdateBaseReleaseCount',
        ),
      );
      expect(script, contains('base_count=\${6:-2}'));
    });

    test('הסקריפט מאמת כל חבילה לפני ההעלאה', () {
      expect(script, contains('--verify'));
      expect(script, contains('tool/release/generate_update_package.dart'));
    });

    test('הסקריפט מושך רק ממאגר בארגון Otzaria', () {
      expect(script, contains('UPDATE_PACKAGES_SOURCE_REPO:-Otzaria/otzaria'));
      expect(script, isNot(contains('http://')));
    });
  });

  group('בחירת שחרורי הבסיס', () {
    // createdAt נגזר מהקומיט וחוזר בין שחרורים; נצפה בפועל שבחר את הישן
    // מבין שלושה שחרורים בעלי תאריך זהה, במקום את הקודם המיידי.
    test('ממוינים לפי גרסה ולא לפי createdAt', () {
      expect(script, isNot(contains('sort_by(.createdAt)')));
      expect(script, isNot(contains('tagName,isDraft,createdAt')));
      expect(script, contains('sort_by(.key) | reverse'));
    });

    test('ההשוואה מספרית, כך ש-0.10.0 גובר על 0.9.99', () {
      expect(script, contains('map(try tonumber catch 0)'));
    });

    test('ה-build של ערוץ הפיתוח שובר שוויון בין אותה גרסה', () {
      expect(script, contains(r'split("+") as $p'));
      expect(script, contains(r'($p[1] // "0") | try tonumber catch 0'));
    });

    // ב-0.9.91 קדמו שלושה שחרורי dev: בלי זה משתמשי 0.9.88 לא היו מכוסים.
    test('היציב האחרון תמיד בין הבסיסים, גם אחרי כמה שחרורי dev', () {
      expect(script, contains('tagName,isDraft,isPrerelease'));
      expect(
        script,
        contains(
          r'[ "$stable_covered" = false ] && [ "$kind" = stable ] || continue',
        ),
      );
      expect(script, contains(r'[ "$kind" = stable ] && stable_covered=true'));
    });
  });

  group('עדכון עץ: macOS ו-Linux נייד', () {
    String step(String name, [int length = 1400]) {
      final at = indexOfStep(name);
      return workflow.substring(at, at + length);
    }

    test('macOS: zstd וחותם נכנסים ל-bundle לפני החתימה, והמניפסט אחריה', () {
      final zstd = indexOfStep('Build bundled zstd (macOS)');
      final stamp = indexOfStep('Stamp installed release (macOS)');
      final sign = indexOfStep('Re-sign and verify the app bundle');
      final manifest = indexOfStep(
        'Generate application file manifest (macOS)',
      );
      expect(indexOfStep('Bundle plugins into the app bundle'), lessThan(zstd));
      expect(zstd, lessThan(sign));
      expect(stamp, lessThan(sign));
      expect(manifest, greaterThan(sign));
      // ה-DMG, ה-zip וה-FULL נבנים מה-bundle החתום, ולכן כולם נושאים אותם.
      expect(sign, lessThan(indexOfStep('Create DMG installer')));
      expect(sign, lessThan(indexOfStep('Create macOS update zip')));

      expect(
        step('Build bundled zstd (macOS)'),
        contains('Contents/MacOS/zstd" universal'),
      );
      // נתונים בשורש ה-bundle או ב-Contents/MacOS שוברים את החתימה.
      expect(
        step('Stamp installed release (macOS)'),
        contains(
          r'--dir "$APP_PATH/Contents/Resources" --platform macos --architecture universal',
        ),
      );
      expect(
        step('Generate application file manifest (macOS)'),
        contains(
          r'--dir "$APP_PATH" --platform macos --architecture universal',
        ),
      );
    });

    test('macOS: zstd נחתם לפני ה-bundle', () {
      final body = step('Re-sign and verify the app bundle');
      expect(
        body.indexOf(
          r'codesign --force --sign - "$APP_PATH/Contents/MacOS/zstd"',
        ),
        allOf(greaterThan(-1), lessThan(body.indexOf('--entitlements'))),
      );
    });

    test('Linux: zstd וחותם ב-app של חבילת ה-FULL, המניפסט מה-app שנארז', () {
      final zstd = indexOfStep('Build bundled zstd (Linux FULL)');
      final stamp = indexOfStep('Stamp installed release (Linux FULL)');
      final bundle = indexOfStep('Create Linux FULL portable bundle');
      final manifest = indexOfStep(
        'Generate application file manifest (Linux)',
      );
      expect(zstd, lessThan(bundle));
      expect(stamp, lessThan(bundle));
      expect(manifest, greaterThan(bundle));
      expect(manifest, lessThan(indexOfStep('Upload Linux FULL bundle')));
      expect(
        step('Build bundled zstd (Linux FULL)'),
        contains("if: matrix.target == 'full'"),
      );
      expect(
        step('Stamp installed release (Linux FULL)'),
        contains('--dir linux-build --platform linux'),
      );
      expect(
        step('Generate application file manifest (Linux)'),
        contains(
          '--dir full_installer/otzaria-linux-full/app --platform linux',
        ),
      );
    });

    test('כל שלב חדש אינו פטאלי', () {
      for (final name in [
        'Build bundled zstd (macOS)',
        'Stamp installed release (macOS)',
        'Generate application file manifest (macOS)',
        'Upload application file manifest (macOS)',
        'Build bundled zstd (Linux FULL)',
        'Stamp installed release (Linux FULL)',
        'Generate application file manifest (Linux)',
        'Upload application file manifest (Linux)',
        'Publish differential update packages (macOS, Linux)',
      ]) {
        expect(
          step(name, 400),
          contains('continue-on-error: true'),
          reason: name,
        );
      }
    });

    test('חבילות העץ נבנות בשלב נפרד אחרי השחרור, עם מגבלת זמן', () {
      final publish = indexOfStep(
        'Publish differential update packages (macOS, Linux)',
      );
      expect(publish, greaterThan(indexOfStep('Create Release')));
      expect(
        publish,
        greaterThan(indexOfStep('Publish differential update packages')),
      );
      final body = step(
        'Publish differential update packages (macOS, Linux)',
        2400,
      );
      expect(body, contains('timeout-minutes:'));
      expect(body, contains('UPDATE_PACKAGES_PLATFORM=macos'));
      expect(body, contains('UPDATE_PACKAGES_PLATFORM=linux'));
      expect(body, contains('release-files/otzaria-macos.zip'));
      expect(body, contains('otzaria-linux-full-\$arch.tar.zst'));
      expect(body, contains('$kUpdateBaseReleaseCount || true'));
      expect(body, contains('gh release upload'));
    });

    test('המניפסטים של macOS ו-Linux עולים עם השחרור', () {
      final body = step('Stage application file manifests', 1600);
      for (final name in [
        'otzaria-app-files-macos-universal.json',
        'otzaria-app-files-linux-x64.json',
        'otzaria-app-files-linux-arm64.json',
      ]) {
        expect(body, contains(name));
      }
    });

    test('הסקריפט פורס לכל פלטפורמה את העץ הנכון', () {
      expect(
        script,
        contains(r'platform=${UPDATE_PACKAGES_PLATFORM:-windows}'),
      );
      expect(script, contains('base_asset="otzaria-macos.zip"'));
      expect(script, contains('base_asset="otzaria-linux-full.tar.zst"'));
      // bsdtar משחזר symlinks; ב-Linux נפרס app/ בלבד, בזרם.
      expect(script, contains('bsdtar -xf'));
      expect(script, contains('tar -x -C "\$dest" otzaria-linux-full/app'));
      expect(script, contains('--output -'));
    });

    test('zstd נבנה מקוד המקור של facebook/zstd בגרסה נעולה ב-hash', () {
      final build = File('tool/release/build_zstd.sh').readAsStringSync();
      expect(
        build,
        contains(
          'https://github.com/facebook/zstd/releases/download/v\$version/',
        ),
      );
      expect(build, contains(RegExp(r'sha256=[0-9a-f]{64}')));
      expect(build, contains('HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0'));
      expect(build, contains('-arch x86_64 -arch arm64'));
      expect(build, isNot(contains('http://')));
    });

    test('כלי ההחלפה האטומית נארז ונחתם לפני מניפסט העץ', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync();
      expect(workflow, contains('Build atomic updater (Linux FULL)'));
      expect(workflow, contains('Build atomic updater (macOS)'));
      expect(
        workflow,
        contains(
          'codesign --force --sign - "\$APP_PATH/Contents/MacOS/otzaria-atomic-swap"',
        ),
      );
      expect(
        workflow.indexOf('Build atomic updater (macOS)'),
        lessThan(
          workflow.indexOf('Generate application file manifest (macOS)'),
        ),
      );
    });
  });
}
