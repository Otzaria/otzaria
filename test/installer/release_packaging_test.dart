import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/my_update_widget.dart' show pickWindowsAssetUrl;
import 'package:path/path.dart' as p;

void main() {
  test('ארכיון מפוצל נבנה מחדש ומאומת לפי ה-manifest', () async {
    final temp = Directory.systemTemp.createTempSync('otzaria_release_parts_');
    addTearDown(() => temp.deleteSync(recursive: true));

    final source = File(p.join(temp.path, 'indexed-full.tar.zst'));
    final sourceBytes = List<int>.generate(1025, (index) => index % 251);
    source.writeAsBytesSync(sourceBytes);
    final partsDirectory = Directory(p.join(temp.path, 'parts'));

    final split = await Process.run('bash', [
      'tool/release/split_release_asset.sh',
      source.path,
      partsDirectory.path,
      '128',
    ]);
    expect(split.exitCode, 0, reason: '${split.stdout}\n${split.stderr}');

    final manifestFile = File(
      p.join(partsDirectory.path, 'indexed-full.tar.zst.manifest.json'),
    );
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final parts = manifest['parts'] as List<dynamic>;
    expect(parts, hasLength(9));
    expect(
      parts.every((part) => (part as Map<String, dynamic>)['size'] <= 128),
      isTrue,
    );

    final reassembled = p.join(temp.path, 'reassembled.tar.zst');
    final assemble = await Process.run('bash', [
      'tool/release/assemble_split_asset.sh',
      manifestFile.path,
      reassembled,
    ]);
    expect(
      assemble.exitCode,
      0,
      reason: '${assemble.stdout}\n${assemble.stderr}',
    );
    expect(File(reassembled).readAsBytesSync(), sourceBytes);

    final manifestSummary = p.join(temp.path, 'manifest-summary.txt');
    final parseManifest = await Process.run('pwsh', [
      '-NoLogo',
      '-NoProfile',
      '-File',
      'installer/read_split_manifest.ps1',
      '-ManifestPath',
      manifestFile.path,
      '-OutputPath',
      manifestSummary,
    ]);
    expect(
      parseManifest.exitCode,
      0,
      reason: '${parseManifest.stdout}\n${parseManifest.stderr}',
    );
    final summaryLines = File(manifestSummary).readAsLinesSync();
    expect(summaryLines.first, startsWith('archive|indexed-full.tar.zst|'));
    expect(
      summaryLines.where((line) => line.startsWith('part|')),
      hasLength(9),
    );

    final embeddedManifestDirectory = Directory(
      p.join(temp.path, 'embedded-manifest'),
    )..createSync();
    final embeddedManifest = File(
      p.join(embeddedManifestDirectory.path, 'library.manifest.json'),
    );
    manifestFile.copySync(embeddedManifest.path);
    final powerShellOutput = p.join(temp.path, 'reassembled-pwsh.tar.zst');
    final powerShellAssemble = await Process.run('pwsh', [
      '-NoLogo',
      '-NoProfile',
      '-File',
      'tool/release/assemble_split_asset.ps1',
      embeddedManifest.path,
      powerShellOutput,
      partsDirectory.path,
    ]);
    expect(
      powerShellAssemble.exitCode,
      0,
      reason: '${powerShellAssemble.stdout}\n${powerShellAssemble.stderr}',
    );
    expect(File(powerShellOutput).readAsBytesSync(), sourceBytes);

    final firstPart = File(
      p.join(
        partsDirectory.path,
        (parts.first as Map<String, dynamic>)['name'],
      ),
    );
    firstPart.writeAsBytesSync([0], mode: FileMode.append);
    final rejectedOutput = p.join(temp.path, 'rejected.tar.zst');
    final rejectedAssembly = await Process.run('pwsh', [
      '-NoLogo',
      '-NoProfile',
      '-File',
      'tool/release/assemble_split_asset.ps1',
      embeddedManifest.path,
      rejectedOutput,
      partsDirectory.path,
    ]);
    expect(rejectedAssembly.exitCode, isNot(0));
    expect(File(rejectedOutput).existsSync(), isFalse);
  });

  test('ה-workflow מפריד בין המתקין לחלקי הספרייה שמתחת ל-2 GiB', () {
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync();

    // האינדקס אינו נבנה כאן יותר — הוא מגיע מוכן מ-SeforimLibrary.
    expect(workflow, isNot(contains('build-release-index')));
    expect(workflow, contains('tool/release/fetch_prebuilt_library_index.sh'));
    expect(workflow, contains('otzaria-index-inputs'));
    expect(workflow, contains('otzaria-library-parts'));
    expect(workflow, isNot(contains('library-full-indexed')));
    expect(workflow, contains('1992294400'));
    expect(workflow, contains('split_release_asset.sh'));
    expect(workflow, contains('compression-level: 0'));
    // המתקין הרגיל מטמיע את המניפסט; אין יותר מתקין מאונדקס נפרד.
    expect(workflow, isNot(contains('IndexedSplitFull')));
    expect(workflow, isNot(contains('windows-full-indexed')));
    expect(workflow, contains(r'installer\library.manifest.json'));
    expect(workflow, contains(r'installer\library_index.manifest.json'));
    expect(
      workflow,
      contains(
        'cp -al "\$GITHUB_WORKSPACE/\$BUNDLE_ROOT/אוצריא" '
        '"\$LIBRARY_ROOT/books"',
      ),
    );
  });

  test('אינדקס מאוחסן מותקן רק כשה-DB וסכמת המנוע של הבנייה תואמים', () async {
    final temp = Directory.systemTemp.createTempSync('otzaria_prebuilt_index_');
    addTearDown(() => temp.deleteSync(recursive: true));

    Future<ProcessResult> sh(String script) =>
        Process.run('bash', ['-euo', 'pipefail', '-c', script]);

    Future<String> sha256Of(String path) async {
      final result = await Process.run('sha256sum', [path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return (result.stdout as String).split(RegExp(r'\s+')).first;
    }

    // ספרייה שמדמה אינדקס בנוי, ארוזה ומפוצלת בדיוק כמו בצד SeforimLibrary.
    final sourceIndex = Directory(p.join(temp.path, 'src', 'index'))
      ..createSync(recursive: true);
    File(p.join(sourceIndex.path, 'meta.json')).writeAsStringSync('{"o":1}');
    File(p.join(sourceIndex.path, 'otzaria_index_meta.json')).writeAsStringSync(
      '{"format":"otzaria-search-index","schema_version":4,'
      '"engine_version":"0.8.4"}',
    );
    final dist = Directory(p.join(temp.path, 'dist'))..createSync();
    final archive = p.join(temp.path, 'otzaria-library-index.tar.zst');
    final packed = await sh(
      'tar -C "${p.join(temp.path, 'src')}" -cf - index '
      '| zstd -19 -o "$archive"',
    );
    expect(packed.exitCode, 0, reason: '${packed.stderr}');
    final split = await Process.run('bash', [
      'tool/release/split_release_asset.sh',
      archive,
      dist.path,
      '1992294400',
    ]);
    expect(split.exitCode, 0, reason: '${split.stdout}\n${split.stderr}');

    final database = File(p.join(temp.path, 'seforim.db.zst'))
      ..writeAsBytesSync(List<int>.generate(64, (index) => index));
    // ארכיון תלמוד אמיתי: השער בצד הזה גוזר את קבוצת שמות הכרכים מרשימת
    // הארכיון, ולכן קובץ אקראי לא היה בודק דבר.
    final talmudRoot = p.join(temp.path, 'talmud');
    final talmudSource = Directory(p.join(talmudRoot, 'תלמוד בבלי'))
      ..createSync(recursive: true);
    for (final tractate in ['מסכת ברכות', 'מסכת שבת', 'מסכת עירובין']) {
      File(
        p.join(talmudSource.path, '$tractate.pdf'),
      ).writeAsStringSync('%PDF-1.4 $tractate');
    }
    File(p.join(talmudSource.path, '.version')).writeAsStringSync('deadbeef');
    final talmud = File(p.join(temp.path, 'talmud_bavli_latest.tar.zst'));
    final packedTalmud = await sh(
      'tar -C "$talmudRoot" -cf - "תלמוד בבלי" | zstd -19 -q -o "${talmud.path}"',
    );
    expect(packedTalmud.exitCode, 0, reason: '${packedTalmud.stderr}');

    // השמות כבתים גולמיים, כמו שהצד הבונה מאמת מול הדיסק — לא דרך tar, שבלי
    // locale של UTF-8 מחזיר שמות עבריים כ-escapes אוקטליים.
    final volumesDigest = await sh(
      'find "${talmudSource.path}" -maxdepth 1 -name "*.pdf" -printf "%f\\n" '
      r"| LC_ALL=C sort -u | sha256sum | awk '{print $1}'",
    );
    expect(volumesDigest.exitCode, 0, reason: '${volumesDigest.stderr}');
    final talmudVolumesDigest = (volumesDigest.stdout as String).trim();
    expect(talmudVolumesDigest, hasLength(64));

    final lock = File(p.join(temp.path, 'pubspec.lock'))
      ..writeAsStringSync('''
packages:
  otzaria_search_engine:
    dependency: "direct main"
    source: hosted
    version: "0.8.4"
''');
    // ההשוואה היא מול קבועי המקור של החבילה שנפתרה, דרך package_config.
    final engineSource = File(
      p.join(temp.path, 'engine', 'rust', 'src', 'api', 'search_engine.rs'),
    )..createSync(recursive: true);
    Directory(p.join(temp.path, '.dart_tool')).createSync();
    File(
      p.join(temp.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync(
      jsonEncode({
        'packages': [
          {
            'name': 'otzaria_search_engine',
            'rootUri': 'file://${p.join(temp.path, 'engine')}',
          },
        ],
      }),
    );
    final rebuildTagFile = File(p.join(temp.path, 'rebuild-tag'));

    Future<ProcessResult> fetch({
      required String databaseSha256,
      required String engineVersion,
      required String indexDirectory,
      String? volumesDigest,
      int requiredSchema = 4,
    }) async {
      engineSource.writeAsStringSync(
        'const INDEX_FORMAT: &str = "otzaria-search-index";\n'
        'pub(crate) const INDEX_SCHEMA_VERSION: u32 = $requiredSchema;\n',
      );
      File(
        p.join(dist.path, 'otzaria-library-index.provenance.json'),
      ).writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'libraryReleaseTag': 'v28-20260910220310',
          'seforimDbZstSha256': databaseSha256,
          'indexArchive': 'otzaria-library-index.tar.zst',
          'indexArchiveSha256': await sha256Of(archive),
          'catalogueBooks': 7,
          'talmudBavliSha256': await sha256Of(talmud.path),
          'talmudVolumesDigest': volumesDigest ?? talmudVolumesDigest,
          'talmudVolumes': 3,
          'includesPdfBooks': false,
          'searchEngineVersion': engineVersion,
        }),
      );
      return Process.run(
        'bash',
        [
          'tool/release/fetch_prebuilt_library_index.sh',
          indexDirectory,
          database.path,
          talmud.path,
          lock.path,
        ],
        environment: {
          'PREBUILT_LIBRARY_INDEX_BASE_URL': 'file://${dist.path}',
          'PREBUILT_INDEX_REBUILD_TAG_FILE': rebuildTagFile.path,
          // כמו קונטיינר debian:bookworm-slim של ה-job, שאין בו locale.
          'LC_ALL': 'C',
        },
      );
    }

    final installed = p.join(temp.path, 'installed', 'index');
    final ok = await fetch(
      databaseSha256: await sha256Of(database.path),
      engineVersion: '0.8.4',
      indexDirectory: installed,
    );
    expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
    expect(File(p.join(installed, 'meta.json')).existsSync(), isTrue);

    // אינדקס של DB אחר: החבילה הייתה נשלחת עם אינדקס שאינו תואם לספרים שבה.
    final wrongDatabase = await fetch(
      databaseSha256: 'f' * 64,
      engineVersion: '0.8.4',
      indexDirectory: p.join(temp.path, 'wrong-db', 'index'),
    );
    expect(wrongDatabase.exitCode, isNot(0));
    expect(wrongDatabase.stderr, contains('build-library-index.yml'));

    // גרסת מנוע אחרת באותה סכמה: האפליקציה מקבלת את האינדקס, ולכן גם הבנייה.
    final otherEngineSameSchema = await fetch(
      databaseSha256: await sha256Of(database.path),
      engineVersion: '0.8.3',
      indexDirectory: p.join(temp.path, 'same-schema', 'index'),
    );
    expect(
      otherEngineSameSchema.exitCode,
      0,
      reason:
          '${otherEngineSameSchema.stdout}\n${otherEngineSameSchema.stderr}',
    );

    // סכמה אחרת: האפליקציה הייתה דוחה את האינדקס ובונה אותו מחדש אצל המשתמש.
    final wrongEngine = await fetch(
      databaseSha256: await sha256Of(database.path),
      engineVersion: '0.8.4',
      indexDirectory: p.join(temp.path, 'wrong-engine', 'index'),
      requiredSchema: 5,
    );
    // יציאה 3 + תג ה-release: ה-workflow מפעיל מהם את בניית האינדקס מחדש.
    expect(wrongEngine.exitCode, 3);
    expect(wrongEngine.stderr, contains('otzaria_search_engine requires'));
    expect(rebuildTagFile.readAsStringSync().trim(), 'v28-20260910220310');
    expect(
      Directory(p.join(temp.path, 'wrong-engine', 'index')).existsSync(),
      isFalse,
    );

    // כרכי תלמוד אחרים: catalogueOrder של כמעט כל הספרייה היה זז מול
    // מה שהאפליקציה מחשבת אצל המשתמש, בלי ששום בדיקה הייתה תופסת זאת.
    final wrongTalmud = await fetch(
      databaseSha256: await sha256Of(database.path),
      engineVersion: '0.8.4',
      indexDirectory: p.join(temp.path, 'wrong-talmud', 'index'),
      volumesDigest: 'e' * 64,
    );
    expect(wrongTalmud.exitCode, isNot(0));
    expect(wrongTalmud.stderr, contains('catalogue order'));
  });

  test('ה-workflow שומר את ה-SHA שנבחר ותומך בתיקון חירום', () {
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync();

    expect(workflow, contains('      hotfix:'));
    expect(workflow, contains('default: "0"'));
    expect(workflow, contains("inputs.hotfix != '0'"));
    expect(workflow, contains('HOTFIX: \${{ inputs.hotfix }}'));
    expect(workflow, contains("grep -Eq '^(0|[1-9][0-9]?)\$'"));
    expect(workflow, contains('ref: \${{ github.sha }}'));
    expect(workflow, isNot(contains('ref: \${{ github.ref_name }}')));
    expect(workflow, contains(r'"hotfix": %s'));
    expect(workflow, contains(r'"$NEW_VERSION" "$HOTFIX"'));
  });
  group('מסייע ההורדה ומניפסט ה-release ב-workflow', () {
    // סופי השורות תלויים בהגדרת ה-checkout, ולכן מנורמלים לפני ההשוואה.
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('האשף נבנה עם ה-ISCC הקיים ואינו מפיל את שחרור אוצריא', () {
      expect(
        workflow,
        contains(r'& "$env:ISCC" installer\download_assistant.iss'),
      );
      expect(
        workflow,
        contains(
          '      - name: Build Download Assistant (non-fatal helper tool)\n'
          '        id: download_assistant\n'
          '        continue-on-error: true\n'
          '        timeout-minutes: 15\n',
        ),
      );
      expect(workflow, contains('name: otzaria-download-assistant'));

      // ההתקנה של Inno Setup לא שוכפלה בשביל הכלי החדש.
      expect('Install Inno Setup'.allMatches(workflow).length, 3);
    });

    test('המניפסט נוצר אחרי ארגון הקבצים ונכתב לתוך release-files', () {
      final organize = workflow.indexOf('- name: Organize release files');
      final generate = workflow.indexOf('- name: Generate release manifest');
      final createRelease = workflow.indexOf('- name: Create Release');
      expect(organize, greaterThan(0));
      expect(generate, greaterThan(organize));
      expect(createRelease, greaterThan(generate));

      expect(
        workflow,
        contains('dart run tool/release/generate_release_manifest.dart'),
      );
      expect(workflow, contains('--dir release-files'));
      expect(
        workflow,
        contains('--out release-files/otzaria-release-manifest.json'),
      );

      // נכס עזר אינו מבטל release: כישלון כאן מזהיר, מוחק מניפסט חלקי
      // וממשיך — בדיוק כמו בניית האשף עצמו.
      expect(
        workflow.substring(generate, generate + 300),
        contains('continue-on-error: true'),
      );
      final warn = workflow.indexOf(
        '- name: Warn when the release manifest is missing',
      );
      expect(warn, greaterThan(generate));
      expect(warn, lessThan(createRelease));
      expect(
        workflow.substring(warn, warn + 400),
        contains('rm -f release-files/otzaria-release-manifest.json'),
      );
    });

    test('שם נכס המניפסט הוא זה שהאשף מחפש', () {
      final iss = File('installer/download_assistant.iss').readAsStringSync();
      final suffix = RegExp(
        r"EndsWithText\(Name, '([^']*manifest[^']*)'\)",
      ).firstMatch(iss)!.group(1)!;
      expect('otzaria-release-manifest.json'.endsWith(suffix), isTrue);
    });

    test('חבילות FULL מפוצלות רק מעל 1.9 GiB, דרך סקריפט אחד', () {
      expect(
        workflow,
        contains(
          '- name: Split FULL packages that exceed GitHub\'s asset limit',
        ),
      );
      final step = workflow.substring(
        workflow.indexOf('bash tool/release/split_oversized_assets.sh'),
      );
      for (final pattern in const [
        "'otzaria-*-windows-full.exe'",
        "'otzaria-*-windows_arm64-full.exe'",
        "'otzaria-linux-full.tar.zst'",
        "'otzaria-linux-full-arm64.tar.zst'",
        "'otzaria-macos-full.tar.zst'",
      ]) {
        expect(step.substring(0, 400), contains(pattern));
      }
      // אריזות ה-FULL כבר אינן נכשלות על הגודל; הפיצול בשלב השחרור מטפל בו.
      expect(
        workflow,
        isNot(contains("exceeds GitHub's 2 GiB release-asset limit")),
      );
      final script = File(
        'tool/release/split_oversized_assets.sh',
      ).readAsStringSync();
      expect(script, contains('threshold=\${SPLIT_THRESHOLD:-2040109465}'));
      expect(script, contains('part_size=\${SPLIT_PART_SIZE:-1992294400}'));

      // הגודל של otzaria-0.9.97-windows-full.exe נשאר קובץ אחד.
      const fullInstallerSizeToday = 2012390081;
      expect(fullInstallerSizeToday, lessThanOrEqualTo(2040109465));
    });

    test('ה-DB של הספרייה יורד דרך סקריפט שמחבר חלקים בכל אריזות ה-FULL', () {
      expect(
        'bash tool/release/download_library_db.sh '
                'full_installer/library_db/seforim.db.zst'
            .allMatches(workflow)
            .length,
        2,
        reason: 'Windows ו-Linux; Android אורז את חלקי חבילת הספרייה',
      );
      expect(
        workflow,
        isNot(contains('SeforimLibrary/releases/latest/download/seforim')),
      );
      final ps1 = File(
        'installer/download_full_installer_assets.ps1',
      ).readAsStringSync();
      expect(ps1, contains(r'"$name.manifest.json"'));
      expect(ps1, contains(r'tool\release\assemble_split_asset.ps1'));
      expect(
        workflow,
        contains(
          'bash tool/release/pack_android_full.sh full_installer '
          'otzaria-android-full .',
        ),
      );
      expect(workflow, contains('path: otzaria-android-full*.zip'));
    });

    test('הערות השחרור מציגות את האשף ככלי עזר ואת החלקים אם יופיעו', () {
      // המסווג ממיר לאותיות קטנות לפני ההשוואה, ולכן הענף נשאר קטן.
      expect(workflow, contains('otzaria-download-assistant-*)'));
      expect(
        workflow,
        contains(
          'מסייע הורדה — כלי עזר להורדת אוצריא ולהכנת התקנה למחשב ללא '
          'אינטרנט. זהו אינו קובץ ההתקנה עצמו',
        ),
      );
      final tools = workflow.substring(workflow.indexOf('## כלי עזר'));
      for (final label in const [
        'מסייע הורדה למחשב Windows',
        'מסייע הורדה למק',
        'מסייע הורדה ללינוקס',
        'מסייע הורדה ללינוקס במחשב עם מעבד ARM',
      ]) {
        expect(tools, contains('"$label"'));
      }

      // הסיווג רגיש לסדר: החלקים חייבים להיתפס לפני *windows-full*.exe.
      final parts = workflow.indexOf('*windows-full.exe.part-*)');
      final support = workflow.indexOf('*windows-full.exe.manifest.json)');
      final fullExe = workflow.indexOf('*windows-full*.exe)');
      expect(parts, greaterThan(0));
      expect(support, greaterThan(0));
      expect(fullExe, greaterThan(parts));
      expect(fullExe, greaterThan(support));
    });

    test('ענף המסייעים הוא הראשון ב-case של הערות השחרור', () {
      final caseStart = workflow.indexOf(r'case "$lower" in');
      expect(caseStart, greaterThan(0));
      final firstBranch = RegExp(
        r'^\s+([^\s#][^\n]*\))\s*$',
        multiLine: true,
      ).firstMatch(workflow.substring(caseStart))!;
      expect(
        firstBranch.group(1),
        'otzaria-download-assistant-*)',
        reason:
            'Otzaria-Download-Assistant-macos.zip / linux-*.tar.gz / windows.exe '
            'היו נבלעים בתבניות *macos* / *linux* / *windows*',
      );
    });

    test('Stage Download Assistant מעתיק את ארבעת המסייעים בלי להיכשל', () {
      final start = workflow.indexOf('- name: Stage Download Assistant');
      final step = workflow.substring(
        start,
        workflow.indexOf('\n      - name: ', start + 1),
      );
      for (final path in const [
        'artifacts/otzaria-download-assistant/Otzaria-Download-Assistant-windows.exe',
        'artifacts/otzaria-download-assistant-macos/Otzaria-Download-Assistant-macos.zip',
        'artifacts/otzaria-download-assistant-linux-x64/Otzaria-Download-Assistant-linux-x64.tar.gz',
        'artifacts/otzaria-download-assistant-linux-arm64/Otzaria-Download-Assistant-linux-arm64.tar.gz',
      ]) {
        expect(step, contains(path));
      }
      // כל קובץ חסר מזהיר בנפרד, ואף אחד מהם אינו מפיל את השחרור.
      expect(step, contains('if [ -f "\$assistant" ]; then'));
      expect(step, contains('echo "::warning::Download Assistant'));
      expect(step, isNot(contains('exit 1')));
      expect(step, isNot(contains('continue-on-error: false')));
    });
  });

  group('מתקין FULL ל-ARM64 בשחרור', () {
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    const asset = 'otzaria-0.9.97-windows_arm64-full.exe';

    test('Organize release files מעתיק אותו, וחסרונו רק מזהיר', () {
      final start = workflow.indexOf('- name: Organize release files');
      final step = workflow.substring(
        start,
        workflow.indexOf('\n      - name: ', start + 1),
      );
      expect(
        step,
        contains(
          'cp artifacts/otzaria-windows-arm64-installer-full/*.exe '
          'release-files/ || true',
        ),
      );
      expect(step, contains('::warning::ARM64 FULL installer is missing'));
    });

    test('הסיווג בהערות השחרור קודם לענף של מתקין ה-ARM הרגיל', () {
      final caseStart = workflow.indexOf(r'case "$lower" in');
      final basicArm = workflow.indexOf('*windows_arm64*.exe)', caseStart);
      expect(basicArm, greaterThan(caseStart));
      for (final branch in const [
        '*windows_arm64-full.exe.part-*)',
        '*windows_arm64-full.exe.manifest.json)',
        '*windows_arm64-full*.exe)',
      ]) {
        final at = workflow.indexOf(branch, caseStart);
        expect(at, inExclusiveRange(caseStart, basicArm), reason: branch);
      }
      // תבניות ה-x64 דורשות "windows-full", ולכן אינן בולעות את נכס ה-ARM.
      expect(asset.contains('windows-full'), isFalse);
      expect(
        workflow,
        contains(
          'emit_link_group "חבילה מלאה למחשבי ARM (מעבדי Snapdragon; '
          'במחשב רגיל הורידו את החבילה שמעל)" "\${windows_arm64_full[@]}"',
        ),
      );
      expect(
        workflow,
        contains(
          'emit_link_group "חלק מהחבילה המלאה למחשבי ARM" '
          '"\${windows_arm64_full_parts[@]}"',
        ),
      );
    });

    test('העדכון שבתוך התוכנה לעולם אינו בוחר בו', () {
      Map<String, dynamic> a(String name) => {
        'name': name,
        'browser_download_url': 'https://example.com/$name',
      };
      for (final isArm in const [true, false]) {
        for (final format in const ['exe', 'zip']) {
          expect(
            pickWindowsAssetUrl(
              [a(asset), a('$asset.part-000')],
              preferredFormat: format,
              isArmMachine: isArm,
            ),
            isNull,
            reason: 'isArm=$isArm format=$format',
          );
        }
      }
      expect(
        pickWindowsAssetUrl(
          [a(asset), a('otzaria-0.9.97-windows_arm64.exe')],
          preferredFormat: 'exe',
          isArmMachine: true,
        ),
        'https://example.com/otzaria-0.9.97-windows_arm64.exe',
      );
    });
  });

  group('פיצול דינמי לפי גודל', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('otzaria_split_'));
    tearDown(() => temp.deleteSync(recursive: true));

    Future<ProcessResult> run(
      String script,
      List<String> args, {
      Map<String, String> env = const {},
    }) => Process.run('bash', [script, ...args], environment: env);

    List<int> bytes(int length, int seed) =>
        List<int>.generate(length, (i) => (i * 7 + seed) % 256);

    List<String> namesIn(Directory dir) =>
        dir.listSync().map((e) => p.basename(e.path)).toList()..sort();

    test('רק נכס מעל הסף מוחלף בחלקים, ומצורפים סקריפטי ההרכבה', () async {
      final dir = Directory(p.join(temp.path, 'release'))..createSync();
      final big = bytes(250, 1);
      File(
        p.join(dir.path, 'otzaria-linux-full.tar.zst'),
      ).writeAsBytesSync(big);
      File(
        p.join(dir.path, 'otzaria-macos-full.tar.zst'),
      ).writeAsBytesSync(bytes(100, 2));
      File(p.join(dir.path, 'other.bin')).writeAsBytesSync(bytes(500, 3));

      final result = await run(
        'tool/release/split_oversized_assets.sh',
        [dir.path, 'otzaria-linux-full.tar.zst', 'otzaria-macos-full.tar.zst'],
        env: {'SPLIT_THRESHOLD': '100', 'SPLIT_PART_SIZE': '96'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(namesIn(dir), [
        'assemble_split_asset.ps1',
        'assemble_split_asset.sh',
        'other.bin',
        'otzaria-linux-full.tar.zst.manifest.json',
        'otzaria-linux-full.tar.zst.part-000',
        'otzaria-linux-full.tar.zst.part-001',
        'otzaria-linux-full.tar.zst.part-002',
        'otzaria-macos-full.tar.zst',
      ]);

      final joined = p.join(temp.path, 'joined.tar.zst');
      final assemble = await run('tool/release/assemble_split_asset.sh', [
        p.join(dir.path, 'otzaria-linux-full.tar.zst.manifest.json'),
        joined,
      ]);
      expect(assemble.exitCode, 0, reason: '${assemble.stderr}');
      expect(File(joined).readAsBytesSync(), big);
    });

    test('כשאין נכס גדול לא מצורף דבר', () async {
      final dir = Directory(p.join(temp.path, 'release'))..createSync();
      File(
        p.join(dir.path, 'otzaria-linux-full.tar.zst'),
      ).writeAsBytesSync([1]);
      final result = await run('tool/release/split_oversized_assets.sh', [
        dir.path,
        'otzaria-linux-full.tar.zst',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(namesIn(dir), ['otzaria-linux-full.tar.zst']);
    });

    Directory androidBundle(Map<String, int> files) {
      final root = Directory(
        p.join(temp.path, 'bundle', 'otzaria-android-full'),
      )..createSync(recursive: true);
      var seed = 0;
      files.forEach((name, size) {
        File(p.join(root.path, name))
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes(size, seed++));
      });
      return root;
    }

    Future<Map<String, List<int>>> extractAll(List<File> zips) async {
      final out = Directory(p.join(temp.path, 'extracted'))..createSync();
      for (final zip in zips) {
        final r = await Process.run('unzip', [
          '-q',
          '-o',
          zip.path,
          '-d',
          out.path,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
      }
      final root = Directory(p.join(out.path, 'otzaria-android-full'));
      return {
        for (final f in root.listSync(recursive: true).whereType<File>())
          p.relative(f.path, from: root.path).replaceAll(r'\', '/'): f
              .readAsBytesSync(),
      };
    }

    Map<String, String> volumeEnv(int threshold) => {
      'SPLIT_THRESHOLD': '$threshold',
      'ZIP_OVERHEAD_MARGIN': '0',
    };

    Future<ProcessResult> pack(Directory out, int threshold) =>
        run('tool/release/pack_android_full.sh', [
          p.join(temp.path, 'bundle'),
          'otzaria-android-full',
          out.path,
        ], env: volumeEnv(threshold));

    /// שם → שיטת הדחיסה, מתוך `unzip -Zv`.
    Future<Map<String, String>> entriesOf(File zip) async {
      final r = await Process.run('unzip', ['-Zv', zip.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final entries = <String, String>{};
      String? name;
      for (final line in (r.stdout as String).split('\n')) {
        final header = RegExp(r'^Central directory entry #\d+:').hasMatch(line);
        if (header) name = null;
        final trimmed = line.trim();
        if (name == null &&
            trimmed.startsWith('otzaria-android-full/') &&
            !trimmed.endsWith('/')) {
          name = trimmed;
        }
        final method = RegExp(r'compression method:\s+(\S+)').firstMatch(line);
        if (method != null && name != null) entries[name] = method.group(1)!;
      }
      return entries;
    }

    // חלקים ומניפסטים בשמות שהייבוא באוצריא מזהה, בגודל מוקטן.
    const library = 'otzaria-1.2.3-library.tar.zst';
    const index = 'otzaria-1.2.3-library-index.tar.zst';
    final packageFiles = {
      'otzaria-android.apk': 30,
      'README.txt': 10,
      '$library.manifest.json': 5,
      '$library.part-000': 120,
      '$library.part-001': 40,
      '$index.manifest.json': 5,
      '$index.part-000': 90,
    };

    test('Android מתחת לסף: ZIP אחד ללא דחיסה, הכול בשורש', () async {
      androidBundle(packageFiles);
      final out = Directory(p.join(temp.path, 'out'))..createSync();
      final result = await pack(out, 1000);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(namesIn(out), ['otzaria-android-full.zip']);
      final entries = await entriesOf(
        File(p.join(out.path, 'otzaria-android-full.zip')),
      );
      expect(entries.keys.toSet(), {
        for (final name in packageFiles.keys) 'otzaria-android-full/$name',
      });
      expect(entries.values.toSet(), {'none'}, reason: 'stored');
    });

    test('Android מעל הסף: כרכים ללא דחיסה, כל חלק שלם בכרך אחד', () async {
      final root = androidBundle(packageFiles);
      final original = {
        for (final f in root.listSync(recursive: true).whereType<File>())
          p.relative(f.path, from: root.path).replaceAll(r'\', '/'): f
              .readAsBytesSync(),
      };
      final out = Directory(p.join(temp.path, 'out'))..createSync();
      final result = await pack(out, 150);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final volumes = namesIn(out);
      expect(volumes, [
        'otzaria-android-full-part1.zip',
        'otzaria-android-full-part2.zip',
      ]);

      final seen = <String, int>{};
      for (final (i, volume) in volumes.indexed) {
        final entries = await entriesOf(File(p.join(out.path, volume)));
        expect(entries.values.toSet(), {'none'}, reason: '$volume stored');
        expect(entries.keys, contains('otzaria-android-full/README.txt'));
        if (i == 0) {
          expect(
            entries.keys,
            contains('otzaria-android-full/otzaria-android.apk'),
          );
        }
        for (final name in entries.keys) {
          if (name.endsWith('README.txt')) continue;
          seen.update(name, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      expect(seen.keys.toSet(), {
        for (final name in packageFiles.keys)
          if (name != 'README.txt') 'otzaria-android-full/$name',
      });
      expect(seen.values.toSet(), {1}, reason: 'כל קובץ בכרך אחד בדיוק');
      final extracted = await extractAll(
        volumes.map((v) => File(p.join(out.path, v))).toList(),
      );
      expect(extracted, original, reason: 'החלקים שלמים, בלי פיצול נוסף');
    });

    test('Android: קובץ שאינו נכנס בכרך מפיל את האריזה', () async {
      androidBundle({'otzaria-android.apk': 20, '$library.part-000': 200});
      final out = Directory(p.join(temp.path, 'out'))..createSync();
      final result = await pack(out, 150);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('does not fit in one volume'));
      expect(namesIn(out), isEmpty);
    });

    group('download_library_db.sh', () {
      late Directory releases;
      late Directory tagDir;
      final db = bytes(300, 9);

      setUp(() {
        releases = Directory(p.join(temp.path, 'releases'))..createSync();
        tagDir = Directory(p.join(releases.path, 'download', 'v31'))
          ..createSync(recursive: true);
      });

      Future<ProcessResult> download(String out) => run(
        'tool/release/download_library_db.sh',
        [out],
        env: {
          'SEFORIM_LIBRARY_DOWNLOAD_BASE': Uri.directory(
            releases.path,
          ).toString().replaceAll(RegExp(r'/$'), ''),
          'SEFORIM_LIBRARY_TAG': 'v31',
        },
      );

      Future<void> publishSplit() async {
        final source = File(p.join(temp.path, 'seforim-schema6.db.zst'))
          ..writeAsBytesSync(db);
        final split = await run('tool/release/split_release_asset.sh', [
          source.path,
          tagDir.path,
          '128',
        ]);
        expect(split.exitCode, 0, reason: '${split.stderr}');
      }

      test('נכס יחיד יורד כמות שהוא', () async {
        File(
          p.join(tagDir.path, 'seforim-schema6.db.zst'),
        ).writeAsBytesSync(db);
        final out = p.join(temp.path, 'seforim.db.zst');
        final result = await download(out);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(File(out).readAsBytesSync(), db);
      });

      test('DB מפוצל מחובר ומאומת', () async {
        await publishSplit();
        final out = p.join(temp.path, 'seforim.db.zst');
        final result = await download(out);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(File(out).readAsBytesSync(), db);
        expect(result.stdout, contains('in 3 parts'));
      });

      test('חלק פגום או חסר מכשיל את ההורדה בלי להשאיר DB', () async {
        await publishSplit();
        final part = File(
          p.join(tagDir.path, 'seforim-schema6.db.zst.part-001'),
        );
        part.writeAsBytesSync(List<int>.filled(part.lengthSync(), 0));
        final out = p.join(temp.path, 'seforim.db.zst');
        var result = await download(out);
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('checksum mismatch'));
        expect(File(out).existsSync(), isFalse);

        part.deleteSync();
        result = await download(out);
        expect(result.exitCode, isNot(0));
        expect(File(out).existsSync(), isFalse);
      });

      test('release בלי DB נכשל בהודעה ברורה', () async {
        final result = await download(p.join(temp.path, 'seforim.db.zst'));
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('whole or split'));
      });
    });
  });
}
