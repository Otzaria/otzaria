import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path/path.dart' as p;

// מסד הספרייה המלא ב-release: seforim.db.zst עד סכמה 5 ו-`seforim-schema<N>.zdb`
// מסכמה 6. הסקריפטים בוחרים לפי נכסי ה-release, ו-CI חייב לעבוד עם שניהם.

const _script = 'tool/release/library_db_asset.sh';
const _ps1 = 'installer/download_library_db_asset.ps1';
final _readable = DatabaseConstants.readableDbSchemaVersion;

String _url(File file) => Uri.file(file.path).toString();

Future<ProcessResult> _bash(
  List<String> args, [
  Map<String, String>? environment,
]) => Process.run('bash', [_script, ...args], environment: environment);

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

Map<String, Object?> _asset(File file, String name) => {
  'name': name,
  'browser_download_url': _url(file),
  'size': file.lengthSync(),
  'digest': 'sha256:${_sha256(file)}',
};

File _manifest(
  Directory dir,
  File zdb,
  String name, {
  Object? schema,
  Object manifestVersion = 1,
}) => File(p.join(dir.path, '$name.manifest.json'))
  ..writeAsStringSync(
    jsonEncode({
      'manifestVersion': manifestVersion,
      'file': name,
      'size': zdb.lengthSync(),
      'sha256': _sha256(zdb),
      'dbSchemaVersion': schema ?? _readable,
    }),
  );

/// ב-Windows `bash` הוא של WSL, שאינו יורש משתני סביבה: בלי
/// LIBRARY_DB_RELEASE_API הסקריפט היה מוריד את ה-release האמיתי.
final String? _skipBash = Platform.isWindows
    ? 'bash של WSL אינו מקבל את סביבת הבדיקה ויוריד נכסים אמיתיים'
    : null;

List<String> _names(String dir) =>
    Directory(dir).listSync().map((e) => p.basename(e.path)).toList();

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('otzaria_library_db_asset_');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  File release(String name, List<Map<String, Object?>> assets) =>
      File(p.join(temp.path, '$name.json'))
        ..writeAsStringSync(jsonEncode({'tag_name': 'v30', 'assets': assets}));

  group('library_db_asset.sh', skip: _skipBash, () {
    Future<File> zstFixture(List<int> bytes) async {
      final plain = File(p.join(temp.path, 'plain.db'))
        ..writeAsBytesSync(bytes);
      final zst = File(p.join(temp.path, 'seforim.db.zst'));
      final packed = await Process.run('zstd', [
        '-q',
        '-f',
        plain.path,
        '-o',
        zst.path,
      ]);
      expect(packed.exitCode, 0, reason: '${packed.stderr}');
      return zst;
    }

    Future<ProcessResult> download(File json, String dir) => _bash(
      ['download', p.join(temp.path, dir)],
      {'LIBRARY_DB_RELEASE_API': _url(json)},
    );

    test('release של סכמה 5 נותן seforim.db.zst שמחולץ ל-DB רגיל', () async {
      final bytes = List<int>.generate(4096, (i) => i % 7);
      final zst = await zstFixture(bytes);
      final json = release('v29', [_asset(zst, 'seforim.db.zst')]);

      final result = await download(json, 'out');
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final downloaded = (result.stdout as String).trim();
      expect(downloaded, p.join(temp.path, 'out', 'seforim.db.zst'));
      expect(
        _names(p.join(temp.path, 'out')),
        ['seforim.db.zst'],
        reason: 'תיקיית העבודה נמחקת',
      );

      final path = await _bash(['path', p.join(temp.path, 'out')]);
      expect((path.stdout as String).trim(), downloaded);

      final plain = p.join(temp.path, 'expanded', 'seforim.db');
      final expand = await _bash(['expand', downloaded, plain]);
      expect(expand.exitCode, 0, reason: '${expand.stderr}');
      expect(File(plain).readAsBytesSync(), bytes);
    });

    test('zdb נבחר על פני zst, ומאומת מול ה-digest וה-manifest', () async {
      final zst = await zstFixture([1, 2, 3]);
      final name = 'seforim-schema$_readable.zdb';
      final zdb = File(p.join(temp.path, name))
        ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 13));
      _manifest(temp, zdb, name);
      // סכמה שהתוכנה עדיין אינה קוראת: נכס כזה אסור שייארז.
      final future = File(p.join(temp.path, 'future.zdb'))
        ..writeAsBytesSync([9]);

      File releaseWith({String? zdbDigest, bool withManifest = true}) {
        final manifest = File(p.join(temp.path, '$name.manifest.json'));
        return release('v30', [
          _asset(zst, 'seforim.db.zst'),
          {..._asset(zdb, name), 'digest': ?zdbDigest},
          if (withManifest) _asset(manifest, '$name.manifest.json'),
          _asset(future, 'seforim-schema${_readable + 1}.zdb'),
        ]);
      }

      final ok = await download(releaseWith(), 'ok');
      expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
      expect(
        (ok.stdout as String).trim(),
        p.join(temp.path, 'ok', 'seforim.zdb'),
      );
      expect(_names(p.join(temp.path, 'ok')), ['seforim.zdb']);
      expect(
        File(p.join(temp.path, 'ok', 'seforim.zdb')).readAsBytesSync(),
        zdb.readAsBytesSync(),
      );

      final badDigest = await download(
        releaseWith(zdbDigest: 'sha256:${'0' * 64}'),
        'bad-digest',
      );
      expect(badDigest.exitCode, isNot(0));
      expect(badDigest.stderr, contains('the release publishes'));

      final noManifest = await download(
        releaseWith(withManifest: false),
        'no-manifest',
      );
      expect(noManifest.exitCode, isNot(0));
      expect(noManifest.stderr, contains('without $name.manifest.json'));

      _manifest(temp, zdb, name, schema: _readable - 1);
      final wrongSchema = await download(releaseWith(), 'wrong-schema');
      expect(wrongSchema.exitCode, isNot(0));
      expect(wrongSchema.stderr, contains('dbSchemaVersion'));
      expect(
        _names(p.join(temp.path, 'wrong-schema')),
        isEmpty,
        reason: 'נכס שלא אומת אינו נשאר ליד שאר נכסי החבילה',
      );

      // שלמים בלבד, כמו ב-ps1: ב-Python ‏True == 1 ו-6.0 == 6.
      for (final entry in <String, ({Object version, Object schema})>{
        'bool-version': (version: true, schema: _readable),
        'float-schema': (version: 1, schema: _readable.toDouble()),
      }.entries) {
        _manifest(
          temp,
          zdb,
          name,
          manifestVersion: entry.value.version,
          schema: entry.value.schema,
        );
        final loose = await download(releaseWith(), entry.key);
        expect(loose.exitCode, isNot(0), reason: entry.key);
      }
    });

    test('הורדה שנכשלה אינה משאירה מסד ישן בתיקייה', () async {
      final out = Directory(p.join(temp.path, 'out'))..createSync();
      File(p.join(out.path, 'seforim.zdb')).writeAsBytesSync([1]);
      File(p.join(out.path, 'seforim.db.zst')).writeAsBytesSync([2]);
      final future = File(p.join(temp.path, 'future.zdb'))
        ..writeAsBytesSync([9]);
      final json = release('future', [
        _asset(future, 'seforim-schema${_readable + 1}.zdb'),
      ]);

      final result = await download(json, 'out');
      expect(result.exitCode, isNot(0));
      expect(_names(out.path), isEmpty, reason: 'path היה מחזיר קובץ ישן');
    });

    test('release בלי מסד שהתוכנה קוראת מכשיל את ההורדה', () async {
      final future = File(p.join(temp.path, 'future.zdb'))
        ..writeAsBytesSync([9]);
      final json = release('future', [
        _asset(future, 'seforim-schema${_readable + 1}.zdb'),
      ]);

      final result = await download(json, 'out');
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('above schema $_readable'));
    });

    test('תג מוצמד חייב להיות התג של ה-release שנקרא', () async {
      final zst = await zstFixture([1, 2, 3]);
      final json = release('pinned', [_asset(zst, 'seforim.db.zst')]);
      Future<ProcessResult> pinned(String tag, String dir) => _bash(
        ['download', p.join(temp.path, dir)],
        {'LIBRARY_DB_RELEASE_API': _url(json), 'LIBRARY_DB_RELEASE_TAG': tag},
      );

      final ok = await pinned('v30', 'ok');
      expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');

      final other = await pinned('v31', 'other');
      expect(other.exitCode, isNot(0));
      expect(other.stderr, contains('not the pinned v31'));
      expect(_names(p.join(temp.path, 'other')), isEmpty);
    });

    test(
      'zdb מיוצא ל-DB רגיל ב-zvfs_cli שנבנה מהמאגר הזה',
      () async {
        final cli = p.join(temp.path, 'cli', 'zvfs_cli');
        final source = p.join(temp.path, 'source.db');
        final zdb = p.join(temp.path, 'seforim.zdb');
        final fixture = await Process.run('bash', [
          '-euc',
          r'''
sh packages/otzaria_zvfs/tool/build_cli.sh "$0" >/dev/null
python3 - "$1" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("PRAGMA page_size=4096")
db.execute("CREATE TABLE line(id INTEGER PRIMARY KEY, content TEXT)")
db.executemany("INSERT INTO line(content) VALUES(?)", [("שורה %d" % i,) for i in range(3000)])
db.commit()
EOF
"$0" convert "$1" "$2" --dict seforim-v1 --level 3 --uuid-from-content --created-ms 0 >/dev/null
''',
          cli,
          source,
          zdb,
        ]);
        expect(
          fixture.exitCode,
          0,
          reason: '${fixture.stdout}\n${fixture.stderr}',
        );

        // בלי ZVFS_CLI הסקריפט בונה את ה-CLI בעצמו, כמו בכל ריצת CI.
        final out = p.join(temp.path, 'out', 'seforim.db');
        final expand = await _bash(['expand', zdb, out]);
        expect(
          expand.exitCode,
          0,
          reason: '${expand.stdout}\n${expand.stderr}',
        );
        expect(File(out).readAsBytesSync(), File(source).readAsBytesSync());

        final again = await _bash(['expand', zdb, out], {'ZVFS_CLI': cli});
        expect(again.exitCode, isNot(0), reason: 'יעד קיים אינו נדרס');
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test('path דורש בדיוק אחד משני שמות המסד', () async {
      final both = Directory(p.join(temp.path, 'both'))..createSync();
      File(p.join(both.path, 'seforim.zdb')).writeAsBytesSync([1]);
      File(p.join(both.path, 'seforim.db.zst')).writeAsBytesSync([1]);
      expect((await _bash(['path', both.path])).exitCode, isNot(0));

      final empty = Directory(p.join(temp.path, 'empty'))..createSync();
      expect((await _bash(['path', empty.path])).exitCode, isNot(0));
    });
  });

  group('download_library_db_asset.ps1', () {
    Future<ProcessResult> run(File json, String outDir, {String? tag}) =>
        Process.run('pwsh', [
          '-NoLogo',
          '-NoProfile',
          '-File',
          _ps1,
          '-OutDir',
          outDir,
          '-ReleaseApi',
          _url(json),
          if (tag != null) ...['-ReleaseTag', tag],
        ]);

    test('בוחר zdb בסכמה הקריאה, מאמת, ונופל ל-zst ב-release ישן', () async {
      final name = 'seforim-schema$_readable.zdb';
      final zdb = File(p.join(temp.path, name))
        ..writeAsBytesSync(List<int>.generate(1500, (i) => i % 11));
      final zst = File(p.join(temp.path, 'seforim.db.zst'))
        ..writeAsBytesSync([4, 5]);
      final future = File(p.join(temp.path, 'future.zdb'))
        ..writeAsBytesSync([9]);
      File newRelease() => release('v30', [
        _asset(future, 'seforim-schema${_readable + 1}.zdb'),
        _asset(zst, 'seforim.db.zst'),
        _asset(zdb, name),
        _asset(
          File(p.join(temp.path, '$name.manifest.json')),
          '$name.manifest.json',
        ),
      ]);

      _manifest(temp, zdb, name);
      final outDir = p.join(temp.path, 'library_db');
      final ok = await run(newRelease(), outDir);
      expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
      expect(
        (ok.stdout as String).trim().split('\n').last.trim(),
        p.join(outDir, 'seforim.zdb'),
      );
      expect(_names(outDir), ['seforim.zdb']);
      expect(
        File(p.join(outDir, 'seforim.zdb')).readAsBytesSync(),
        zdb.readAsBytesSync(),
      );

      final old = await run(
        release('v29', [_asset(zst, 'seforim.db.zst')]),
        outDir,
      );
      expect(old.exitCode, 0, reason: '${old.stdout}\n${old.stderr}');
      expect(
        _names(outDir),
        ['seforim.db.zst'],
        reason: 'המתקין בוחר לפי הקובץ שב-library_db — אסור ששניים יישארו',
      );

      _manifest(temp, zdb, name, schema: _readable - 1);
      final badDir = p.join(temp.path, 'bad');
      final bad = await run(newRelease(), badDir);
      expect(bad.exitCode, isNot(0));
      expect(bad.stdout, contains('dbSchemaVersion'));
      expect(_names(badDir), isEmpty);

      // גם קובץ שנשאר מריצה קודמת נמחק כשההורדה נכשלת.
      File(p.join(outDir, 'seforim.db.zst')).writeAsBytesSync([7]);
      final failed = await run(newRelease(), outDir);
      expect(failed.exitCode, isNot(0));
      expect(_names(outDir), isEmpty);
    });

    test('תג מוצמד שאינו התג של ה-release נכשל', () async {
      final zst = File(p.join(temp.path, 'seforim.db.zst'))
        ..writeAsBytesSync([4, 5]);
      final json = release('pinned', [_asset(zst, 'seforim.db.zst')]);

      final ok = await run(json, p.join(temp.path, 'ok'), tag: 'v30');
      expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');

      final otherDir = p.join(temp.path, 'other');
      final other = await run(json, otherDir, tag: 'v31');
      expect(other.exitCode, isNot(0));
      expect(other.stdout, contains('not the pinned v31'));
      expect(_names(otherDir), isEmpty);
    });
  });

  group('צרכני המסד המלא ב-workflows', () {
    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('אף צרכן אינו מוריד את המסד בשם קבוע מ-latest/download', () {
      for (final path in [
        '.github/workflows/build-and-announce.yml',
        '.github/workflows/installer-screenshots.yml',
        'installer/download_full_installer_assets.ps1',
      ]) {
        final text = read(path);
        expect(text, isNot(contains('seforim-schema6.db.zst')), reason: path);
        expect(
          text,
          isNot(contains('SeforimLibrary/releases/latest/download/seforim')),
          reason: path,
        );
      }
    });

    test('כל ה-jobs מקבלים את אותו תג ספרייה שנפתר פעם אחת', () {
      final workflow = read('.github/workflows/build-and-announce.yml');
      const output = r'${{ needs.bump_version.outputs.library_tag }}';

      expect(
        workflow,
        contains(r'library_tag: ${{ steps.library_release.outputs.tag }}'),
      );
      expect(
        workflow,
        contains('gh api repos/Otzaria/SeforimLibrary/releases/latest'),
      );
      expect(
        'LIBRARY_DB_RELEASE_TAG: $output'.allMatches(workflow).length,
        5,
        reason: 'Windows x64, Windows ARM64, Linux, Android ו-macOS',
      );
      expect(
        workflow,
        contains(
          'PREBUILT_LIBRARY_INDEX_BASE_URL: '
          'https://github.com/Otzaria/SeforimLibrary/releases/download/$output',
        ),
        reason: 'האינדקס המאוחסן נלקח מאותו release כמו המסד',
      );
    });

    test('חבילות FULL מעל 2 GiB מפוצלות, והחלקים מוצגים ומורכבים', () {
      final workflow = read('.github/workflows/build-and-announce.yml');
      final splitStart = workflow.indexOf('GITHUB_ASSET_LIMIT=2147483648');
      final split = workflow.substring(
        splitStart,
        workflow.indexOf(r'split_release_asset.sh "$installer"', splitStart),
      );
      for (final name in [
        'release-files/otzaria-linux-full.tar.zst',
        'release-files/otzaria-linux-full-arm64.tar.zst',
        'release-files/otzaria-macos-full.tar.zst',
      ]) {
        expect(split, contains(name), reason: 'לולאת הפיצול');
      }
      expect(split, isNot(contains('android')), reason: 'בטלפון אין הרכבה');
      // job שנכשל לא העלה את החבילה שלו, ו-stat עליה היה מפיל את השחרור.
      expect(split, contains(r'if [ ! -f "$installer" ]; then'));
      expect(
        split.indexOf(r'if [ ! -f "$installer" ]; then'),
        lessThan(split.indexOf(r'size=$(stat')),
      );

      // החלקים מסווגים לפני התבנית הכללית, שהייתה מציגה כל חלק כחבילה.
      for (final entry in const {
        '*linux-full*.tar.zst.part-*)': '*linux-full*.tar.*)',
        '*macos-full*.tar.zst.part-*)': '*macos-full*.tar.*)',
      }.entries) {
        final part = workflow.indexOf(entry.key);
        expect(part, greaterThan(0), reason: entry.key);
        expect(workflow.indexOf(entry.value), greaterThan(part));
      }
      expect(
        'bash assemble_split_asset.sh <קובץ ה-manifest>'
            .allMatches(workflow)
            .length,
        2,
      );

      // העדכון הדיפרנציאלי ב-Linux פורס את app/ גם מחבילה מפוצלת.
      final script = read('tool/release/build_update_packages.sh');
      expect(
        script,
        contains(
          r'bash "$assemble" "$new_zip.manifest.json" "$work/new-archive"',
        ),
      );
      expect(script, contains(r'--pattern "$base_asset.part-*"'));
      expect(
        read('tool/release/generate_release_manifest.dart'),
        allOf(
          contains(
            r"pattern: r'^otzaria-linux-full\.tar\.zst\.manifest\.json$'",
          ),
          contains(
            r"pattern: r'^otzaria-macos-full\.tar\.zst\.manifest\.json$'",
          ),
          // אנדרואיד אינו מפוצל, ולכן אין לו תבנית split.
          isNot(contains('otzaria-android-full\\.zip\\.manifest')),
        ),
        reason: 'מסייע ההורדה מקבל את החלקים ממניפסט ה-release',
      );
    });

    test('נכסי אנדרואיד: ZIP בלי מסד ומסד נפרד, כל אחד קובץ יחיד', () {
      final workflow = read('.github/workflows/build-and-announce.yml');
      final start = workflow.indexOf('- name: Create Android FULL bundle');
      final bundle = workflow.substring(
        start,
        workflow.indexOf('\n      - name: ', start + 1),
      );
      // הרשומות בשורש ה-ZIP, בלי APK ובלי מסד; המסד כקובץ נפרד כמו שהוא.
      expect(
        bundle,
        contains(r'(cd "$BUNDLE_ROOT" && LC_ALL=C.UTF-8 zip -r -q'),
      );
      expect(bundle, isNot(contains('app-release.apk')));
      expect(bundle, isNot(contains('library_db/"')));
      expect(
        bundle,
        contains(r'*.zdb) cp "$DB_ASSET" otzaria-android-library.zdb'),
      );
      expect(bundle, contains(r'[ "$size" -lt 2147483648 ]'));
      expect(bundle, isNot(contains('zstd -19')));

      final upload = workflow.substring(
        workflow.indexOf('- name: Upload Android FULL bundle'),
      );
      expect(upload.substring(0, 300), contains('otzaria-android-library.*'));
      expect(
        workflow,
        contains(
          'cp artifacts/otzaria-android-full/otzaria-android-library.* '
          'release-files/',
        ),
      );

      // סדר ההתקנה בהערות השחרור: APK, ואז ה-ZIP, ואז המסד.
      final notes = workflow.substring(
        workflow.indexOf('התקנה במכשיר בלי אינטרנט'),
      );
      final zip = notes.indexOf('מייבאים את קובץ ה־ZIP');
      expect(notes.indexOf('מתקינים את ה־APK'), inInclusiveRange(0, zip));
      expect(notes.indexOf('מייבאים את קובץ מסד הספרים'), greaterThan(zip));
    });

    test('חבילות ה-FULL נשענות על library_db_asset.sh', () {
      final workflow = read('.github/workflows/build-and-announce.yml');
      expect(
        'bash tool/release/library_db_asset.sh download '
                'full_installer/library_db'
            .allMatches(workflow)
            .length,
        3,
        reason: 'Linux, Android ו-macOS',
      );
      // מסכמה 6 אין מסד רגיל על הדיסק של המשתמש: החבילות נושאות את ה-zdb.
      // expand נשאר רק ל-release מסכמה 5 (Linux ו-macOS).
      expect(
        r'library_db_asset.sh expand "$DB_ASSET"'.allMatches(workflow).length,
        2,
      );
      expect(
        workflow,
        contains(r'ln "$DB_ASSET" "$BUNDLE_ROOT/אוצריא/seforim.zdb"'),
      );
      expect(
        workflow,
        contains(r'cp "$DB_ASSET" "$BUNDLE_ROOT/אוצריא/seforim.zdb"'),
      );
      expect(workflow, isNot(contains('zstd -19 -T0 -q "\$RUNNER_TEMP')));
      expect(workflow, isNot(contains('full_installer/library_db/seforim.db')));
      expect(workflow, isNot(contains("exceeds GitHub's 2 GiB")));
      // האינדקס המאוחסן נבנה מה-sha256 של הנכס שהורד בפועל, zst או zdb.
      expect(
        workflow,
        contains(
          '"\$INDEXED_LIBRARY_ROOT/index" \\\n'
          '              "\$DB_ASSET" \\',
        ),
      );

      final screenshots = read('.github/workflows/installer-screenshots.yml');
      expect(
        screenshots,
        contains(r'bash tool/release/library_db_asset.sh download "$dl"'),
      );
      expect(
        screenshots,
        contains(
          r'bash tool/release/library_db_asset.sh expand "$db_asset" '
          r'"$books/seforim.db"',
        ),
      );
    });
  });
}
