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
      'installer/read_indexed_library_manifest.ps1',
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
      p.join(embeddedManifestDirectory.path, 'indexed_library.manifest.json'),
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
    expect(workflow, contains('otzaria-library-full-indexed'));
    expect(workflow, contains('1992294400'));
    expect(workflow, contains('split_release_asset.sh'));
    expect(workflow, contains('compression-level: 0'));
    expect(workflow, contains('/DIndexedSplitFull=1'));
    expect(workflow, contains('otzaria-windows-installer-full-indexed'));
    expect(workflow, contains('התקנה לא־מקוונת בווינדוס'));
    expect(workflow, contains('indexed_library.manifest.json'));
    expect(
      workflow,
      contains(
        'cp -al "\$GITHUB_WORKSPACE/\$BUNDLE_ROOT/אוצריא" '
        '"\$INDEXED_LIBRARY_ROOT/books"',
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

    // בדיוק הצינור ששני הצדדים מריצים על אותו ארכיון.
    final volumesDigest = await sh(
      'zstd -d -c "${talmud.path}" | tar -tf - | sed "s#.*/##" '
      r"| grep -i '\.pdf$' | LC_ALL=C sort -u | sha256sum | awk '{print $1}'",
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
    File(p.join(temp.path, '.dart_tool', 'package_config.json'))
        .writeAsStringSync(
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
      File(p.join(dist.path, 'otzaria-library-index.provenance.json'))
          .writeAsStringSync(
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
      return Process.run('bash', [
        'tool/release/fetch_prebuilt_library_index.sh',
        indexDirectory,
        database.path,
        talmud.path,
        lock.path,
      ], environment: {
        'PREBUILT_LIBRARY_INDEX_BASE_URL': 'file://${dist.path}',
        'PREBUILT_INDEX_REBUILD_TAG_FILE': rebuildTagFile.path,
      });
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
      reason: '${otherEngineSameSchema.stdout}\n${otherEngineSameSchema.stderr}',
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

    test('פיצול מתקין ה-FULL מותנה במגבלת ה-2 GiB ואינו נדרש היום', () {
      expect(workflow, contains('GITHUB_ASSET_LIMIT=2147483648'));
      expect(
        workflow,
        contains(
          r'for installer in release-files/otzaria-*-windows-full.exe '
          r'release-files/otzaria-*-windows_arm64-full.exe \',
        ),
      );
      expect(
        workflow,
        contains(r'if [ "$size" -lt "$GITHUB_ASSET_LIMIT" ]; then'),
      );
      expect(
        workflow,
        contains(
          r'tool/release/split_release_asset.sh "$installer" '
          r'windows-full-parts "$PART_SIZE"',
        ),
      );

      // הגודל בפועל של otzaria-0.9.97-windows-full.exe — התנאי יוצא שקר,
      // ולכן הנכס של היום נשאר קובץ אחד, בית-בבית.
      const fullInstallerSizeToday = 2012390081;
      const githubAssetLimit = 2147483648;
      expect(fullInstallerSizeToday, lessThan(githubAssetLimit));
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
}
