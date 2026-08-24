import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_packager.dart';
import 'package:path/path.dart' as p;

/// Manifest מינימלי ותקין לבדיקות. שדות שלא חיוניים יושמטו.
Map<String, dynamic> _minimalManifest({
  String id = 'test.packager.plugin',
  String name = 'Packager Test',
  String version = '1.0.0',
  String entrypoint = 'index.html',
  String? title,
  bool allowOrderBeforeBuiltIns = false,
  List<String> permissions = const [],
  Map<String, dynamic>? network,
}) => {
  'schemaVersion': 1,
  'id': id,
  'name': name,
  'version': version,
  'description': '',
  'author': '',
  'homepage': '',
  'entrypoint': entrypoint,
  'minAppVersion': '0.0.0',
  'sdkVersion': '1.x',
  'permissions': permissions,
  'network': ?network,
  'contributes': {
    'toolTab': {
      'title': title ?? name,
      'order': 900,
      'allowOrderBeforeBuiltIns': allowOrderBeforeBuiltIns,
      'defaultPinned': true,
    },
    'publishedDataTypes': const [],
  },
};

/// יוצר תיקיית תוסף בדיסק עם manifest + index.html. מחזיר נתיב מוחלט.
String _writePluginDir(
  Directory parent, {
  String dirName = 'plugin',
  Map<String, dynamic>? manifestOverride,
  String indexHtml = '<!doctype html><html lang="he" dir="rtl"></html>',
  Map<String, String> extraFiles = const {},
}) {
  final dir = Directory(p.join(parent.path, dirName))..createSync();
  File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsStringSync(jsonEncode(manifestOverride ?? _minimalManifest()));
  File(p.join(dir.path, 'index.html')).writeAsStringSync(indexHtml);
  extraFiles.forEach((rel, contents) {
    final f = File(p.join(dir.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contents);
  });
  return dir.path;
}

void main() {
  group('PluginPackager.packDirectory', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('otzaria_packager_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {
          // ב-Windows יכולה להיות נעילה רגעית — לא חוסם את הטסט.
        }
      }
    });

    test('packs a minimal valid plugin into ‎.otzplugin', () async {
      final pluginDir = _writePluginDir(tempDir);

      final result = await PluginPackager.packDirectory(
        directoryPath: pluginDir,
        outputPath: p.join(tempDir.path, 'out.otzplugin'),
      );

      expect(File(result.outputPath).existsSync(), isTrue);
      expect(result.fileCount, 2); // manifest.json + index.html
      expect(result.bytes, greaterThan(0));
      expect(result.manifest.id, 'test.packager.plugin');
    });

    test('throws when the directory does not exist', () async {
      expect(
        () => PluginPackager.packDirectory(
          directoryPath: p.join(tempDir.path, 'no-such-dir'),
        ),
        throwsA(isA<PluginPackagerException>()),
      );
    });

    test('throws when manifest.json is missing', () async {
      final dir = Directory(p.join(tempDir.path, 'no-manifest'))..createSync();
      File(p.join(dir.path, 'index.html')).writeAsStringSync('x');

      expect(
        () => PluginPackager.packDirectory(directoryPath: dir.path),
        throwsA(isA<PluginPackagerException>()),
      );
    });

    test('throws when manifest.json is not valid JSON', () async {
      final dir = Directory(p.join(tempDir.path, 'bad-json'))..createSync();
      File(p.join(dir.path, 'manifest.json')).writeAsStringSync('{not json');
      File(p.join(dir.path, 'index.html')).writeAsStringSync('x');

      expect(
        () => PluginPackager.packDirectory(directoryPath: dir.path),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            contains('manifest.json'),
          ),
        ),
      );
    });

    test('throws when output exists and force is false', () async {
      final pluginDir = _writePluginDir(tempDir);
      final outPath = p.join(tempDir.path, 'out.otzplugin');
      File(outPath).writeAsStringSync('stale');

      expect(
        () => PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: outPath,
        ),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            contains('--force'),
          ),
        ),
      );
    });

    test('overwrites existing output when force is true', () async {
      final pluginDir = _writePluginDir(tempDir);
      final outPath = p.join(tempDir.path, 'out.otzplugin');
      File(outPath).writeAsStringSync('stale');

      final result = await PluginPackager.packDirectory(
        directoryPath: pluginDir,
        outputPath: outPath,
        force: true,
      );

      expect(result.fileCount, 2);
      // הקובץ נדרס: כעת זה ZIP תקין ולא הטקסט "stale".
      final bytes = File(outPath).readAsBytesSync();
      expect(bytes.length, greaterThan(5));
      // ZIP header אמור להתחיל ב-‎PK
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });

    test(
      'does NOT pack the output .otzplugin into itself when it lives inside the source dir',
      () async {
        // רגרסיה: באג שהמשתמש זיהה. כש--output מצביע לתוך תיקיית התוסף,
        // הקובץ הנוצר היה נסרק ע"י listSync ונכנס לארכיון של עצמו.
        final pluginDir = _writePluginDir(tempDir);
        final outPath = p.join(pluginDir, 'my.otzplugin');

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: outPath,
        );

        // רק 2 קבצים אמורים להיכנס — manifest.json + index.html — לא הקובץ
        // .otzplugin עצמו.
        expect(result.fileCount, 2);

        // ולוודא שהארכיון לא מכיל ערך בשם my.otzplugin
        final bytes = File(outPath).readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);
        final names = archive.files.map((f) => f.name).toList();
        expect(names, isNot(contains('my.otzplugin')));
        expect(names, containsAll(<String>['manifest.json', 'index.html']));
      },
    );

    test(
      'default output path lands in parent dir as {id}-{version}.otzplugin',
      () async {
        final pluginDir = _writePluginDir(tempDir);

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
        );

        expect(
          p.basename(result.outputPath),
          'test.packager.plugin-1.0.0.otzplugin',
        );
        expect(p.dirname(result.outputPath), tempDir.path);
      },
    );

    test('rejects a toolTab.title that differs from name', () async {
      // הכותרת המוצגת בטאב חייבת להיות זהה לשם התוסף (כמו בחנות) — אחרת
      // התוסף יוצג בשם אחד בחנות ובאחר בטאב.
      final manifest = _minimalManifest(name: 'שם התוסף', title: 'שם הטאב');
      final pluginDir = _writePluginDir(tempDir, manifestOverride: manifest);

      await expectLater(
        PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(
          predicate((e) => e.toString().contains('השמות חייבים להיות זהים')),
        ),
      );
    });

    test(
      'packaging preserves allowOrderBeforeBuiltIns from the manifest',
      () async {
        final manifest = _minimalManifest(allowOrderBeforeBuiltIns: true);
        final pluginDir = _writePluginDir(tempDir, manifestOverride: manifest);

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
        );

        expect(
          result.manifest.allowOrderBeforeBuiltIns,
          isTrue,
          reason:
              'the packager must preserve the explicit placement flag from '
              'manifest.json so packaged plugins behave like development ones',
        );
      },
    );

    test(
      'blocks packaging when manifest validator throws (bad permission)',
      () async {
        // הרשאה לא קיימת ברשימה הרשמית => PluginManifestValidator זורק.
        final manifest = _minimalManifest(
          permissions: const ['this.is.not.a.real.permission'],
        );
        final pluginDir = _writePluginDir(tempDir, manifestOverride: manifest);

        expect(
          () => PluginPackager.packDirectory(directoryPath: pluginDir),
          throwsA(isA<PluginPackagerException>()),
        );
      },
    );

    test(
      'packing succeeds despite warnings; warnings are surfaced in report',
      () async {
        // קריאה ל-API לא מוכר -> warning בלבד, האריזה צריכה לעבור.
        final manifest = _minimalManifest();
        final pluginDir = _writePluginDir(
          tempDir,
          manifestOverride: manifest,
          extraFiles: {
            'app.js': '''
            // קריאה ל-API לא מוכר
            Otzaria.call('totally.fake_method', {});
          ''',
          },
        );

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
        );

        expect(result.validation.hasErrors, isFalse);
        expect(result.validation.hasWarnings, isTrue);
        expect(
          result.validation.warnings.any(
            (w) => w.contains('totally.fake_method'),
          ),
          isTrue,
        );
      },
    );

    // ── בדיקות entrypoint בתוך תיקייה מוחרגת ──────────────────────────────

    test('throws when entrypoint is inside node_modules/', () async {
      // רגרסיה: בלי הולידציה, האריזה הייתה עוברת בהצלחה אך ה-.otzplugin
      // יוצא שבור — הקובץ הכניסי מוחרג ולא נכלל בארכיון.
      final manifest = _minimalManifest(
        entrypoint: 'node_modules/some-pkg/index.html',
      );
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        // יוצרים את הקובץ כדי שולידטור המניפסט יעבור את בדיקת הקיום שלו.
        extraFiles: {'node_modules/some-pkg/index.html': '<html></html>'},
      );

      await expectLater(
        () => PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('node_modules'), contains('מוחרגת')),
          ),
        ),
      );
    });

    test('throws when entrypoint is nested inside .git/', () async {
      final manifest = _minimalManifest(entrypoint: '.git/hooks/index.html');
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        extraFiles: {'.git/hooks/index.html': '<html></html>'},
      );

      await expectLater(
        () => PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('.git'), contains('מוחרגת')),
          ),
        ),
      );
    });

    test('throws when entrypoint uses ./ prefix into a skipped dir', () async {
      // וריאנט נתיב עם ./ — normalize+absolute חייב לתפוס גם את זה.
      final manifest = _minimalManifest(
        entrypoint: './node_modules/pkg/index.html',
      );
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        extraFiles: {'node_modules/pkg/index.html': '<html></html>'},
      );

      await expectLater(
        () => PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(isA<PluginPackagerException>()),
      );
    });

    test(
      'files inside skipped dirs are silently excluded; entrypoint is safe',
      () async {
        // תיקיית .git קיימת עם קבצים, אבל ה-entrypoint עצמו בשורש — תקין.
        final pluginDir = _writePluginDir(
          tempDir,
          extraFiles: {
            '.git/config': '[core]',
            '.git/HEAD': 'ref: refs/heads/main',
            'node_modules/lib/util.js': 'export default {}',
          },
        );

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: p.join(tempDir.path, 'out.otzplugin'),
        );

        // רק 2 קבצים — קבצי .git ו-node_modules לא אמורים להיכלל.
        expect(result.fileCount, 2);

        final bytes = File(result.outputPath).readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);
        final names = archive.files.map((f) => f.name).toSet();
        expect(names, containsAll(<String>['manifest.json', 'index.html']));
        expect(names.any((n) => n.startsWith('.git/')), isFalse);
        expect(names.any((n) => n.startsWith('node_modules/')), isFalse);
      },
    );

    test(
      'entrypoint in a normal (non-skipped) subdirectory packs correctly',
      () async {
        final manifest = _minimalManifest(entrypoint: 'src/app/index.html');
        final pluginDir = _writePluginDir(
          tempDir,
          manifestOverride: manifest,
          extraFiles: {'src/app/index.html': '<html></html>'},
        );

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: p.join(tempDir.path, 'out.otzplugin'),
        );

        expect(
          result.fileCount,
          3,
        ); // manifest.json + index.html (root) + src/app/index.html
        final bytes = File(result.outputPath).readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);
        expect(
          archive.files.map((f) => f.name),
          contains('src/app/index.html'),
        );
      },
    );

    // ── החרגה דרך .otzignore ───────────────────────────────────────────────

    test(
      '.otzignore excludes files, dirs, and globs (with ! re-include)',
      () async {
        final pluginDir = _writePluginDir(
          tempDir,
          extraFiles: {
            'app.js': 'x',
            'app.js.map': 'x', // *.map glob
            'notes.txt': 'x', // קובץ בודד מעוגן
            'src/raw.ts': 'x', // גזימת תיקיית src/
            'src/keep.js': 'x', // מוחזר ע"י !
            '.otzignore':
                '# build excludes\n'
                '*.map\n'
                'notes.txt\n'
                'src/\n'
                '!src/keep.js\n',
          },
        );

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: p.join(tempDir.path, 'out.otzplugin'),
        );

        final archive = ZipDecoder().decodeBytes(
          File(result.outputPath).readAsBytesSync(),
        );
        final names = archive.files.map((f) => f.name).toSet();

        expect(
          names,
          containsAll(<String>['manifest.json', 'index.html', 'app.js']),
        );
        expect(names, contains('src/keep.js')); // !src/keep.js הוחזר
        expect(names, isNot(contains('app.js.map')));
        expect(names, isNot(contains('notes.txt')));
        expect(names, isNot(contains('src/raw.ts')));
        expect(names, isNot(contains('.otzignore'))); // הקובץ עצמו לא נארז
        expect(result.excludedCount, 3); // app.js.map, notes.txt, src/raw.ts
      },
    );

    test(
      'no .otzignore => excludedCount is 0 and nothing extra is dropped',
      () async {
        final pluginDir = _writePluginDir(tempDir, extraFiles: {'a.js': 'x'});

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: p.join(tempDir.path, 'out.otzplugin'),
        );

        expect(result.excludedCount, 0);
        expect(result.fileCount, 3); // manifest + index + a.js
      },
    );

    test('throws when .otzignore would exclude the entrypoint', () async {
      final manifest = _minimalManifest(entrypoint: 'app/index.html');
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        extraFiles: {
          'app/index.html': '<html></html>',
          '.otzignore': 'app/\n',
        },
      );

      await expectLater(
        () => PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('app/index.html'), contains('.otzignore')),
          ),
        ),
      );
    });

    // ── כללי החרגת מטא-דאטה (חייבים להישאר זהים ל-zipWriter.js בוולידטור) ──

    test('metadata files and dirs are excluded and reported', () async {
      final pluginDir = _writePluginDir(
        tempDir,
        extraFiles: {
          'readme.md': 'x', // *.md בכל אות רישית
          'HELP.MD': 'x',
          'LICENSE.txt': 'x',
          'licence': 'x',
          'package-lock.json': 'x',
          'yarn.lock': 'x',
          'pnpm-lock.yaml': 'x',
          '.editorconfig': 'x',
          'screenshots/shot.png': 'x',
          '.well-known/keys.json': 'x',
          '.github/workflows/ci.yml': 'x',
          'app.js': 'x', // הקובץ היחיד שאינו מטא-דאטה
        },
      );

      final result = await PluginPackager.packDirectory(
        directoryPath: pluginDir,
        outputPath: p.join(tempDir.path, 'out.otzplugin'),
      );

      final archive = ZipDecoder().decodeBytes(
        File(result.outputPath).readAsBytesSync(),
      );
      final names = archive.files.map((f) => f.name).toSet();

      expect(names, <String>{'manifest.json', 'index.html', 'app.js'});
      // בלי כללי `!` תיקיות המטא-דאטה נגזמות, ולכן אינן נמנות פרטנית.
      expect(
        result.excludedMetadata,
        containsAll(<String>[
          'readme.md',
          'HELP.MD',
          'LICENSE.txt',
          'licence',
          'package-lock.json',
          'yarn.lock',
          'pnpm-lock.yaml',
          '.editorconfig',
        ]),
      );
      expect(result.excludedCount, 0); // החרגת מטא-דאטה נמנית בנפרד
    });

    test(
      'a ! line re-includes a metadata file and a screenshots asset',
      () async {
        final pluginDir = _writePluginDir(
          tempDir,
          extraFiles: {
            'help.md': 'x',
            'CHANGELOG.md': 'x', // לא הוחזר — נשאר מוחרג
            'screenshots/logo.png': 'x',
            'screenshots/store-1.png': 'x', // לא הוחזר
            '.well-known/keys.json': 'x',
          },
        );
        File(p.join(pluginDir, '.otzignore')).writeAsStringSync(
          '!help.md\n'
          '!screenshots/logo.png\n'
          '!.well-known/keys.json\n',
        );

        final result = await PluginPackager.packDirectory(
          directoryPath: pluginDir,
          outputPath: p.join(tempDir.path, 'out.otzplugin'),
        );

        final archive = ZipDecoder().decodeBytes(
          File(result.outputPath).readAsBytesSync(),
        );
        final names = archive.files.map((f) => f.name).toSet();

        expect(
          names,
          containsAll(<String>[
            'help.md',
            'screenshots/logo.png',
            '.well-known/keys.json',
          ]),
        );
        expect(names, isNot(contains('CHANGELOG.md')));
        expect(names, isNot(contains('screenshots/store-1.png')));
        expect(names, isNot(contains('.otzignore')));
        expect(
          result.excludedMetadata,
          containsAll(<String>['CHANGELOG.md', 'screenshots/store-1.png']),
        );
      },
    );

    test('throws when the entrypoint is a metadata file', () async {
      final manifest = _minimalManifest(entrypoint: 'index.md');
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        extraFiles: {'index.md': '<html></html>'},
      );

      await expectLater(
        () => PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('index.md'), contains('מטא-דאטה')),
          ),
        ),
      );
    });

    test('a ! line makes a metadata entrypoint packable again', () async {
      final manifest = _minimalManifest(entrypoint: 'index.md');
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        extraFiles: {'index.md': '<html></html>', '.otzignore': '!index.md\n'},
      );

      final result = await PluginPackager.packDirectory(
        directoryPath: pluginDir,
        outputPath: p.join(tempDir.path, 'out.otzplugin'),
      );

      final archive = ZipDecoder().decodeBytes(
        File(result.outputPath).readAsBytesSync(),
      );
      expect(archive.files.map((f) => f.name), contains('index.md'));
    });

    test('throws when the background entrypoint is excluded', () async {
      final manifest = _minimalManifest();
      (manifest['contributes'] as Map<String, dynamic>)['background'] = {
        'entrypoint': 'bg/worker.html',
      };
      final pluginDir = _writePluginDir(
        tempDir,
        manifestOverride: manifest,
        extraFiles: {
          'bg/worker.html': '<html></html>',
          '.otzignore': 'bg/\n',
        },
      );

      await expectLater(
        () => PluginPackager.packDirectory(directoryPath: pluginDir),
        throwsA(
          isA<PluginPackagerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('bg/worker.html'), contains('.otzignore')),
          ),
        ),
      );
    });
  });
}
