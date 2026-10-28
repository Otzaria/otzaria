import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _baseManifest({
  List<String> permissions = const [],
  Map<String, dynamic>? network,
  String name = 'Test Plugin',
  String? title,
  String minAppVersion = '0.9.94',
}) => {
  'schemaVersion': 1,
  'id': 'test.extended.plugin',
  'name': name,
  'version': '1.0.0',
  'description': '',
  'author': '',
  'homepage': '',
  'entrypoint': 'index.html',
  'minAppVersion': minAppVersion,
  'sdkVersion': '1.x',
  'permissions': permissions,
  'network': ?network,
  'contributes': {
    'toolTab': {
      'title': title ?? name,
      'order': 900,
      'defaultPinned': true,
    },
    'publishedDataTypes': const [],
  },
};

PluginValidationReport _runOn(
  Directory tempDir, {
  Map<String, dynamic>? manifestOverride,
  Map<String, String> files = const {
    'index.html': '<!doctype html><html lang="he" dir="rtl"></html>',
  },
}) {
  final json = manifestOverride ?? _baseManifest();
  final dir = Directory(p.join(tempDir.path, 'plugin'))..createSync();
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync(jsonEncode(json));
  files.forEach((rel, contents) {
    final file = File(p.join(dir.path, rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  final manifest = PluginManifest.fromJson(json);
  return PluginExtendedValidator.validate(
    manifest: manifest,
    manifestJson: json,
    directoryPath: dir.path,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'otzaria_ext_validator_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('network.allowlist (relaxed — warning only)', () {
    test('no warning when network is not declared', () {
      final report = _runOn(tempDir);
      expect(report.errors, isEmpty);
      expect(report.warnings.any((w) => w.contains('network')), isFalse);
    });

    test('warns when network.access is declared without allowlist entries', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.access'],
        ),
      );
      expect(report.errors, isEmpty);
      expect(
        report.warnings.any((w) => w.contains('network.allowlist')),
        isTrue,
      );
    });

    test('warns about wildcards in allowlist (not an error)', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.access'],
          network: {
            'enabled': true,
            'allowlist': ['https://*.example.com'],
          },
        ),
      );
      expect(report.errors, isEmpty);
      expect(
        report.warnings.any((w) => w.contains('wildcard')),
        isTrue,
      );
    });

    test('no warning for valid explicit URLs', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.access'],
          network: {
            'enabled': true,
            'allowlist': ['https://api.example.com'],
          },
        ),
      );
      expect(report.errors, isEmpty);
      expect(report.warnings.any((w) => w.contains('network')), isFalse);
    });

    test('host חשוף ל-localhost תקין ב-allowlist (network.localhost)', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.localhost'],
          network: {
            'enabled': true,
            'allowlist': ['127.0.0.1', 'localhost'],
          },
        ),
      );
      expect(report.errors, isEmpty);
      expect(
        report.warnings.any((w) => w.contains('כתובת לא תקינה')),
        isFalse,
      );
    });

    group('הפרדת network.localhost / network.access', () {
      PluginValidationReport run(
        String minAppVersion,
        List<String> permissions,
        List<String> allowlist,
      ) => _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          minAppVersion: minAppVersion,
          permissions: permissions,
          network: {'enabled': true, 'allowlist': allowlist},
        ),
      );

      test('כתובת 127.x.x.x כלשהי תקינה עם network.localhost', () {
        final report = run(
          '0.9.98.1',
          const ['network.localhost'],
          const ['127.0.0.9', 'http://127.0.0.9:8080'],
        );
        expect(report.errors, isEmpty);
        expect(
          report.warnings.any((w) => w.contains('כתובת לא תקינה')),
          isFalse,
        );
      });

      test('מ-0.9.98.1 כתובת מקומית עם network.access בלבד היא שגיאה', () {
        final report = run(
          '0.9.98.1',
          const ['network.access'],
          const [
            '127.0.0.9',
          ],
        );
        expect(
          report.errors.any((e) => e.contains('network.localhost')),
          isTrue,
        );
      });

      test('מ-0.9.98.1 כתובת אינטרנט עם network.localhost בלבד היא שגיאה', () {
        final report = run(
          '0.9.98.1',
          const ['network.localhost'],
          const [
            'https://api.example.com',
          ],
        );
        expect(report.errors.any((e) => e.contains('network.access')), isTrue);
      });

      test('מ-0.9.98.1 שתי ההרשאות עם שני סוגי יעדים תקינות', () {
        final report = run(
          '0.9.98.1',
          const ['network.access', 'network.localhost'],
          const ['127.0.0.9', 'https://api.example.com'],
        );
        expect(report.errors, isEmpty);
      });

      test('לפני 0.9.98.1 כתובת מקומית עם network.access היא אזהרה בלבד', () {
        final report = run(
          '0.9.98',
          const ['network.access'],
          const [
            '127.0.0.9',
          ],
        );
        expect(report.errors, isEmpty);
        expect(
          report.warnings.any(
            (w) => w.contains('network.localhost') && w.contains('0.9.98.1'),
          ),
          isTrue,
        );
      });

      test('לפני 0.9.98.1 הצהרה על שתי ההרשאות נקייה מאזהרות הפרדה', () {
        final report = run(
          '0.9.98',
          const ['network.access', 'network.localhost'],
          const ['127.0.0.9'],
        );
        expect(report.errors, isEmpty);
        expect(report.warnings.any((w) => w.contains('0.9.98.1')), isFalse);
      });
    });

    group('הפרדת network.localhost / network.access — מקרי קצה', () {
      PluginValidationReport run(
        String minAppVersion,
        List<String> permissions,
        List<String> allowlist, {
        bool enabled = true,
      }) => _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          minAppVersion: minAppVersion,
          permissions: permissions,
          network: {'enabled': enabled, 'allowlist': allowlist},
        ),
      );

      test('כתובת מקומית לא קנונית אינה נספרת כאינטרנט', () {
        final report = run(
          '0.9.98.1',
          const ['network.localhost'],
          const [
            'http://127.1:11434',
            'http://localhost.:1234',
            'http://127.10.10.1:8080',
          ],
        );
        expect(report.errors, isEmpty);
        expect(
          report.warnings.where((w) => w.contains('אינה מזוהה כמקומית')),
          hasLength(3),
        );
      });

      test('שם מארח רגיל שמתחיל ב-localhost או ב-127 הוא אינטרנט', () {
        final report = run(
          '0.9.98.1',
          const ['network.localhost'],
          const [
            'https://localhost.example.com',
            'https://127.0.0.1.nip.io',
          ],
        );
        expect(
          report.errors.single,
          allOf(
            contains('localhost.example.com'),
            contains('127.0.0.1.nip.io'),
            contains('"network.access"'),
          ),
        );
        expect(
          report.warnings.any((w) => w.contains('אינה מזוהה כמקומית')),
          isFalse,
        );
      });

      test('הודעת השגיאה מציינת את הכתובת שגרמה לה', () {
        final report = run(
          '0.9.98.1',
          const ['network.access'],
          const [
            'http://127.0.0.9:8080',
          ],
        );
        expect(
          report.errors.single,
          allOf(contains('http://127.0.0.9:8080'), contains('0.9.98.1')),
        );
      });

      test('לפני 0.9.98.1 יעד אינטרנט עם network.localhost בלבד הוא אזהרה', () {
        final report = run(
          '0.9.98',
          const ['network.localhost'],
          const [
            'https://api.example.com',
          ],
        );
        expect(report.errors, isEmpty);
        expect(
          report.warnings.any((w) => w.contains('"network.access"')),
          isTrue,
        );
      });

      test('לפני 0.9.98.1 יעד מקומי בלי אף הרשאת רשת הוא אזהרה', () {
        final report = run('0.9.98', const [], const ['127.0.0.9']);
        expect(report.errors, isEmpty);
        expect(
          report.warnings.any((w) => w.contains('"network.localhost"')),
          isTrue,
        );
      });

      test('מ-0.9.98.1 עם network.enabled כבוי אין שגיאת הפרדה', () {
        final report = run(
          '0.9.98.1',
          const ['network.access'],
          const [
            '127.0.0.9',
          ],
          enabled: false,
        );
        expect(report.errors, isEmpty);
      });

      test('כתובת userinfo מטעה נספרת לפי ה-host האמיתי', () {
        final report = run(
          '0.9.98.1',
          const ['network.localhost'],
          const [
            'http://127.0.0.1@evil.example.com',
          ],
        );
        expect(
          report.errors.any((e) => e.contains('"network.access"')),
          isTrue,
        );
      });
    });

    test('network.localhost ללא allowlist מקבל אזהרת allowlist ריק', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.localhost'],
        ),
      );
      expect(
        report.warnings.any((w) => w.contains('network.allowlist')),
        isTrue,
      );
    });
  });

  group('name vs toolTab.title (enforced upstream in validateManifest)', () {
    test('extended validator stays silent — the rule is a blocking error in '
        'validateManifest, so this layer does not re-flag a mismatch', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          name: 'שם התוסף',
          title: 'שם הטאב',
        ),
      );
      expect(report.errors, isEmpty);
      expect(
        report.warnings.any((w) => w.contains('toolTab.title')),
        isFalse,
      );
    });
  });

  group('API/event scanning (warnings)', () {
    test('flags unknown API call', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('totally.fake_method', {});",
        },
      );
      expect(report.errors, isEmpty);
      expect(
        report.warnings.any((w) => w.contains('totally.fake_method')),
        isTrue,
      );
    });

    test('does not flag known network APIs as unknown', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.access'],
          network: const {
            'enabled': true,
            'allowlist': ['https://example.com'],
          },
        ),
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js':
              "Otzaria.call('network.fetchStream', {url: 'x'});"
              "Otzaria.call('network.download', {url: 'y'});",
        },
      );
      // לא מסומנים כ-API לא מוכר, ואין אזהרת הרשאה חסרה (היא הוצהרה).
      expect(
        report.warnings.any((w) => w.contains('network.fetchStream')),
        isFalse,
      );
      expect(
        report.warnings.any((w) => w.contains('network.download')),
        isFalse,
      );
    });

    test('network.localhost מספיקה ל-fetchStream', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.localhost'],
          network: const {
            'enabled': true,
            'allowlist': ['127.0.0.1'],
          },
        ),
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js':
              "Otzaria.call('network.fetchStream', {url: 'http://127.0.0.1:11434/api/tags'});",
        },
      );
      expect(
        report.warnings.any(
          (w) =>
              w.contains('network.fetchStream') && w.contains('network.access'),
        ),
        isFalse,
      );
    });

    test(
      'warns when network.download is used but network.access is missing',
      () {
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': "Otzaria.call('network.download', {url: 'y'});",
          },
        );
        expect(
          report.warnings.any(
            (w) =>
                w.contains('network.download') && w.contains('network.access'),
          ),
          isTrue,
        );
      },
    );

    test(
      'warns when known API is used but its required permission is missing',
      () {
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': "Otzaria.call('library.findBooks', {});",
          },
        );
        expect(
          report.warnings.any((w) => w.contains('library.books.read')),
          isTrue,
        );
      },
    );

    test('does not warn when required permission is declared', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['library.books.read'],
        ),
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('library.findBooks', {});",
        },
      );
      expect(
        report.warnings.any((w) => w.contains('library.books.read')),
        isFalse,
      );
    });

    test('every known API method has a required-permission mapping '
        '(except the runtime-ungated fs ops)', () {
      // שומר מפני רגרסיה: כל API שנוסף ל-knownApiMethods חייב להופיע גם
      // ב-methodRequiredPermissions, אלא אם ה-runtime לא דורש עבורו הרשאה.
      // fs.extractZip/deleteFile מגודרים ע"י ui.pickFolder, לא ע"י manifest.
      // plugin.backgroundDone הוא ניהול-עצמי של מופע הרקע — נטול הרשאה בכוונה.
      // feedback.report מגודר בדיאלוג האישור של המשתמש, לא ע"י manifest.
      // פעולות המרחב הפרטי מגודרות בשורש הפרטי של התוסף, לא ע"י manifest.
      const noManifestPermission = {
        'fs.extractZip',
        'fs.deleteFile',
        'fs.deleteFolder',
        'fs.moveEntry',
        'fs.writeFile',
        'fs.readFile',
        'fs.listDir',
        'fs.makeDir',
        'fs.deleteEntry',
        'fs.stat',
        'plugin.backgroundDone',
        'feedback.report',
        'feedback.hasReporterEmail',
        'ui.print',
        'ui.printFile',
        'ui.exportPdf',
        'ui.setUnsavedChanges',
        'plugin.setRestoreState',
        // הרשאת events.subscribe:<topic> תלויה בנושא ונבדקת באדפטר.
        'events.setOptions',
      };
      final missing = PluginExtendedValidator.knownApiMethods
          .where((m) => !noManifestPermission.contains(m))
          .where(
            (m) => !PluginExtendedValidator.methodRequiredPermissions
                .containsKey(m),
          )
          .toList();
      expect(
        missing,
        isEmpty,
        reason:
            'APIs ללא מיפוי הרשאה — יעברו אריזה אך ייכשלו ב-runtime: '
            '$missing',
      );
    });

    test('warns when library.getTree is used without library.books.read', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('library.getTree', {});",
        },
      );
      expect(
        report.warnings.any(
          (w) =>
              w.contains('library.getTree') && w.contains('library.books.read'),
        ),
        isTrue,
      );
    });

    test('warns when ui.pickFolder is used without fs.folder_access', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('ui.pickFolder', {});",
        },
      );
      expect(
        report.warnings.any(
          (w) => w.contains('ui.pickFolder') && w.contains('fs.folder_access'),
        ),
        isTrue,
      );
    });

    test('legacy ui.feedback declaration covers ui.pickFolder', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(permissions: const ['ui.feedback']),
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('ui.pickFolder', {});",
        },
      );
      expect(
        report.warnings.any((w) => w.contains('ui.pickFolder')),
        isFalse,
      );
    });

    test('baseline APIs need no declaration; declaring one warns', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['plugin.storage.read'],
        ),
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js':
              "Otzaria.call('storage.get', {});"
              "Otzaria.call('ui.showMessage', {});"
              "Otzaria.call('app.getInfo', {});",
        },
      );
      // אין אזהרת הרשאה-חסרה על API של הרשאת בסיס.
      expect(
        report.warnings.any((w) => w.contains('אך לא ביקש')),
        isFalse,
      );
      // הצהרה על הרשאת בסיס — אזהרת דעיכה.
      expect(
        report.warnings.any(
          (w) =>
              w.contains('plugin.storage.read') &&
              w.contains('ניתנת כיום אוטומטית'),
        ),
        isTrue,
      );
    });

    test('fs.folder_access requires minAppVersion 0.9.97', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['fs.folder_access'],
          minAppVersion: '0.9.94',
        ),
        files: {'index.html': '<html lang="he" dir="rtl"></html>'},
      );
      expect(
        report.errors.any(
          (e) => e.contains('fs.folder_access') && e.contains('0.9.97'),
        ),
        isTrue,
      );

      final okReport = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['fs.folder_access'],
          minAppVersion: '0.9.97',
        ),
        files: {'index.html': '<html lang="he" dir="rtl"></html>'},
      );
      expect(
        okReport.errors.any((e) => e.contains('fs.folder_access')),
        isFalse,
      );
    });

    test(
      'warns when personal-file APIs are used without fs.user_files.read',
      () {
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js':
                "Otzaria.call('fs.pickUserFile', {});"
                "Otzaria.call('fs.resolveFileUrl', {});"
                "Otzaria.call('fs.readTextFile', {});"
                "Otzaria.call('fs.revokeFile', {});",
          },
        );
        for (final method in const [
          'fs.pickUserFile',
          'fs.resolveFileUrl',
          'fs.readTextFile',
          'fs.revokeFile',
        ]) {
          expect(
            report.warnings.any(
              (w) => w.contains(method) && w.contains('fs.user_files.read'),
            ),
            isTrue,
            reason: '$method חייב לדרוש את fs.user_files.read',
          );
        }
      },
    );

    test(
      'no warning for personal-file APIs when fs.user_files.read declared',
      () {
        final report = _runOn(
          tempDir,
          manifestOverride: _baseManifest(
            permissions: const ['fs.user_files.read'],
          ),
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': "Otzaria.call('fs.readTextFile', {});",
          },
        );
        expect(
          report.warnings.any((w) => w.contains('fs.user_files.read')),
          isFalse,
        );
      },
    );

    test(
      'shorthand `Otzaria.library.findBooks()` is detected as API usage',
      () {
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': 'Otzaria.library.findBooks();',
          },
        );
        // library.findBooks דורש library.books.read; לא הוכרזה -> warning.
        expect(
          report.warnings.any((w) => w.contains('library.books.read')),
          isTrue,
        );
      },
    );

    test('reserved shorthand fields (.call/.on/.off) are NOT treated as API', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js':
              "Otzaria.on('plugin.boot', () => {}); Otzaria.call('app.getInfo', {});",
        },
      );
      // אסור שיופיע "Otzaria.on" כקריאה ל-API לא מוכר.
      expect(
        report.warnings.any((w) => w.startsWith('קריאה ל-API לא מוכר: on')),
        isFalse,
      );
    });

    test('comments are stripped before scanning', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': '''
            // Otzaria.call('totally.fake_method', {})
            /* Otzaria.call('also.fake', {}) */
          ''',
        },
      );
      expect(
        report.warnings.any((w) => w.contains('totally.fake_method')),
        isFalse,
      );
      expect(
        report.warnings.any((w) => w.contains('also.fake')),
        isFalse,
      );
    });

    test('inline // comments (after real code) are stripped', () {
      // רגרסיה: בעבר רק `//` בתחילת שורה הוסר; inline comment גרם
      // ל-warning שווא.
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': '''
            const x = 1; // Otzaria.call('totally.fake_inline', {});
            doSomething(); // Otzaria.on('fake.event', () => {});
          ''',
        },
      );
      expect(
        report.warnings.any((w) => w.contains('totally.fake_inline')),
        isFalse,
        reason: 'inline // comments must be stripped before scanning',
      );
      expect(
        report.warnings.any((w) => w.contains('fake.event')),
        isFalse,
      );
    });

    test(
      'regex literals containing `//` do not blow away the rest of the line',
      () {
        // רגרסיה: regex literal עם `\/\/` בתוכו (URL pattern). אם המסיר
        // לא מגן על regex literals, הוא יחתוך מ-`//` הראשון שב-regex עד
        // סוף השורה ויבליע את הקריאה האמיתית שאחריו.
        final report = _runOn(
          tempDir,
          manifestOverride: _baseManifest(
            permissions: const ['library.books.read'],
          ),
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': r'''
            const re = /https?:\/\/example/; Otzaria.call('library.findBooks', {});
          ''',
          },
        );
        // הקריאה ל-library.findBooks אמורה להיתפס (לא לקבל warning
        // "API לא מוכר"), והרשאה הוכרזה.
        expect(
          report.warnings.any((w) => w.contains('library.findBooks')),
          isFalse,
        );
      },
    );

    test(
      'regex literal containing `Otzaria.call` is NOT treated as a real call',
      () {
        // רגרסיה הפוכה: regex literal עם הטקסט "Otzaria.call" בתוכו לא
        // צריך להיחשב כקריאה.
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': r'''
            const matcher = /Otzaria\.call\('inside.regex'\)/g;
          ''',
          },
        );
        expect(
          report.warnings.any((w) => w.contains('inside.regex')),
          isFalse,
        );
      },
    );

    test('regex with character class containing `/` is handled', () {
      // `/[a-z\/]+/g` — class פנימי עם `/` ברוח. אסור לסיים את ה-regex
      // ב-`/` שבתוך ה-class.
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['library.books.read'],
        ),
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': r'''
            const re = /[a-z\/]+/g; Otzaria.call('library.findBooks', {});
          ''',
        },
      );
      expect(
        report.warnings.any((w) => w.contains('library.findBooks')),
        isFalse,
      );
    });

    test(
      'unterminated regex literal with many `[...]` scans quickly',
      timeout: const Timeout(Duration(seconds: 10)),
      () {
        // Minified libraries (marked.min.js) made the scan take minutes.
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': 'const r = /${'[a]' * 30}; Otzaria.library.findBooks();',
          },
        );
        expect(
          report.warnings.any((w) => w.contains('library.books.read')),
          isTrue,
        );
      },
    );

    test('division operators are NOT mistaken for regex literals', () {
      // `a / b` הוא חלוקה. אם המסיר חושב שזה תחילת regex, הוא ימשיך
      // עד ה-`/` הבא ויבלע קוד. כאן אין `/` נוסף בשורה, אבל יש בשורה
      // הבאה (כסטרינג). הקריאה ל-getInfo אמורה להישאר.
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'app.js': '''
            const ratio = total / count;
            const url = 'http://example.com/path';
            Otzaria.library.findBooks();
          ''',
        },
      );
      // library.findBooks דורש library.books.read; לא הוכרזה -> warning.
      expect(
        report.warnings.any((w) => w.contains('library.books.read')),
        isTrue,
        reason: 'API call after division/string must still be scanned',
      );
    });

    test(
      'string literals containing `//` (URLs/regex) are not mistakenly cut',
      () {
        // אם _stripCommentsForScan חותך // אגרסיבית מדי, היא תפגע ב-URL
        // וגם תתעלם מקריאה אמיתית אחריו. נוודא שזה לא קורה.
        final report = _runOn(
          tempDir,
          manifestOverride: _baseManifest(
            permissions: const ['library.books.read'],
          ),
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': '''
            const url = "https://example.com/api";
            Otzaria.call('library.findBooks', { src: url });
          ''',
          },
        );
        // הקריאה האמיתית נסרקה -> אין warning של API לא מוכר.
        expect(
          report.warnings.any((w) => w.contains('library.findBooks')),
          isFalse,
        );
        // וגם לא warning של ההרשאה החסרה (היא הוכרזה).
        expect(
          report.warnings.any((w) => w.contains('library.books.read')),
          isFalse,
        );
      },
    );

    test(
      'event subscription without events.subscribe permission -> warning',
      () {
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'app.js': "Otzaria.on('navigation.changed', () => {});",
          },
        );
        expect(
          report.warnings.any(
            (w) => w.contains('events.subscribe:navigation.changed'),
          ),
          isTrue,
        );
      },
    );
  });

  group('design compliance', () {
    test('HTML root must declare dir="rtl" lang="he"', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<!doctype html><html><body></body></html>',
        },
      );
      expect(report.design.compliant, isFalse);
      expect(
        report.design.violations.any((v) => v.contains('dir="rtl"')),
        isTrue,
      );
      expect(
        report.design.violations.any((v) => v.contains('lang="he"')),
        isTrue,
      );
    });

    test(
      ':root CSS variable defaults with hex/rgba/px do NOT trigger false positives',
      () {
        // רגרסיה: DESIGN_GUIDE עצמו ממליץ על #6750A4, rgba(...) ו-18px כברירות
        // מחדל ב-:root. הוולידטור חייב להחריג הגדרות --variable.
        final report = _runOn(
          tempDir,
          files: {
            'index.html': '<html lang="he" dir="rtl"></html>',
            'styles.css': '''
            :root {
              --color-primary: #6750A4;
              --color-on-primary: #FFFFFF;
              --color-primary-subtle: rgba(103, 80, 164, 0.12);
              --font-size-base: 18px;
              --radius-sm: 8px;
            }
            body { color: var(--color-on-primary); background: var(--color-primary); font-size: var(--font-size-base); }
          ''',
          },
        );
        expect(report.design.violations, isEmpty);
        expect(report.design.compliant, isTrue);
      },
    );

    test('font-size ב-px מותר בסלקטור פס הכותרת בלבד', () {
      // DESIGN_GUIDE מחייב גדלים קשיחים ב-px בפס הכותרת (שלא יתנפח עם גופן
      // הקריאה של המשתמש) — ולכן שם px מותר, ובכל שאר הכללים אסור.
      final ok = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'styles.css': '''
            header.topbar { height: 56px; }
            header.topbar .brand { font-size: 16px; }
          ''',
        },
      );
      expect(
        ok.design.violations.any((v) => v.contains('font-size')),
        isFalse,
        reason: ok.design.violations.join(' | '),
      );

      final flagged = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'styles.css': '''
            .topbar { font-size: 16px; }
            .card { font-size: 18px; }
          ''',
        },
      );
      expect(
        flagged.design.violations.any((v) => v.contains('font-size')),
        isTrue,
        reason: 'כלל שאינו פס הכותרת חייב להיפסל',
      );
    });

    test('flags hex colors that are NOT inside CSS variable declarations', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'styles.css': '''
            body { color: #ff0000; background: var(--color-primary); }
          ''',
        },
      );
      expect(
        report.design.violations.any((v) => v.contains('hex')),
        isTrue,
      );
    });

    test('flags named colors in property values', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'styles.css': '''
            body { color: red; background: var(--color-primary); }
          ''',
        },
      );
      expect(
        report.design.violations.any((v) => v.contains('שם צבע')),
        isTrue,
      );
    });

    test('flags hardcoded font-size in px outside variable definition', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'styles.css': '''
            body { font-size: 14px; color: var(--color-on-primary); }
          ''',
        },
      );
      expect(
        report.design.violations.any((v) => v.contains('font-size')),
        isTrue,
      );
    });

    test('requires at least one var(--color-*) usage', () {
      final report = _runOn(
        tempDir,
        files: {
          'index.html': '<html lang="he" dir="rtl"></html>',
          'styles.css': 'body { font-family: serif; }',
        },
      );
      expect(
        report.design.violations.any((v) => v.contains('var(--color-')),
        isTrue,
      );
    });

    test('marks plugins without any HTML/CSS as non-compliant by default', () {
      // אין מה להוכיח לגבי תאימות עיצוב אם אין HTML/CSS.
      final report = _runOn(
        tempDir,
        files: const {'app.js': '/* logic only */'},
      );
      expect(report.design.compliant, isFalse);
    });
  });

  group('minAppVersion vs גרסת ה-API (שגיאה חוסמת)', () {
    test('network.fetchStream דורש minAppVersion 0.9.97', () {
      PluginValidationReport run(String minAppVersion) => _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['network.access'],
          minAppVersion: minAppVersion,
          network: const {
            'enabled': true,
            'allowlist': ['https://example.com'],
          },
        ),
        files: const {
          'index.html': '<!doctype html><html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('network.fetchStream', {url: 'x'});",
        },
      );

      expect(run('0.9.96').errors, contains(contains('0.9.97')));
      expect(run('0.9.97').errors, isEmpty);
    });

    test('שגיאה כשמשתמשים ב-API חדש מ-minAppVersion שהוצהר', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['ui.create_shortcut'],
          minAppVersion: '0.9.90',
        ),
        files: const {
          'index.html': '<!doctype html><html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('shortcut.create', {});",
        },
      );
      expect(
        report.errors.any(
          (e) =>
              e.contains('shortcut.create') &&
              e.contains('0.9.94') &&
              e.contains('0.9.90'),
        ),
        isTrue,
        reason: 'shortcut.create (0.9.94) עם minAppVersion=0.9.90 חייב error',
      );
    });

    test('אין שגיאה כש-minAppVersion מספיק גבוה', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['ui.create_shortcut'],
          minAppVersion: '0.9.94',
        ),
        files: const {
          'index.html': '<!doctype html><html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('shortcut.create', {});",
        },
      );
      expect(report.errors, isEmpty);
    });

    test('מדווח על ה-API הגבוה ביותר כשיש כמה גרסאות', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(
          permissions: const ['library.books.read', 'fs.user_files.read'],
          minAppVersion: '0.9.90',
        ),
        files: const {
          'index.html': '<!doctype html><html lang="he" dir="rtl"></html>',
          'app.js':
              "Otzaria.call('library.findBooks', {});"
              "Otzaria.call('fs.readTextFile', {});",
        },
      );
      // library.findBooks (0.9.90) תקין; fs.readTextFile (0.9.94) חוסם.
      expect(report.errors.any((e) => e.contains('fs.readTextFile')), isTrue);
      expect(
        report.errors.any((e) => e.contains('library.findBooks')),
        isFalse,
      );
    });

    test('API לא מוכר אינו מפעיל בדיקת גרסה (רק אזהרה)', () {
      final report = _runOn(
        tempDir,
        manifestOverride: _baseManifest(minAppVersion: '0.9.90'),
        files: const {
          'index.html': '<!doctype html><html lang="he" dir="rtl"></html>',
          'app.js': "Otzaria.call('totally.fake_method', {});",
        },
      );
      expect(report.errors, isEmpty);
      expect(
        report.warnings.any((w) => w.contains('totally.fake_method')),
        isTrue,
      );
    });
  });

  group('contributes.toolTab.allowMultipleInstances', () {
    Map<String, dynamic> withFlag(
      Object? value, {
      String minAppVersion = '0.9.99',
    }) {
      final json = _baseManifest(minAppVersion: minAppVersion);
      ((json['contributes'] as Map<String, dynamic>)['toolTab']
              as Map<String, dynamic>)['allowMultipleInstances'] =
          value;
      return json;
    }

    bool mentionsFlag(PluginValidationReport report) =>
        report.errors.any((e) => e.contains('allowMultipleInstances'));

    void check(Object? value, String minAppVersion, {required bool rejected}) {
      final report = _runOn(
        tempDir,
        manifestOverride: withFlag(value, minAppVersion: minAppVersion),
      );
      expect(
        mentionsFlag(report),
        rejected,
        reason: '$value / $minAppVersion: ${report.errors}',
      );
      Directory(p.join(tempDir.path, 'plugin')).deleteSync(recursive: true);
    }

    test('ערך שאינו בוליאני נדחה בהודעה ברורה', () {
      for (final value in <Object>['true', 1, <String>[]]) {
        check(value, '0.9.99', rejected: true);
      }
    });

    test('true עם minAppVersion מספיק, ו-false בכל גרסה, תקינים', () {
      check(true, '0.9.99', rejected: false);
      check(false, '0.9.94', rejected: false);
    });

    test('true עם minAppVersion ישן נדחה', () {
      check(true, '0.9.94', rejected: true);
    });
  });

  group('newTab בלחצנים ובתפריט הקשר', () {
    Map<String, dynamic> manifest({
      required bool allowMultiple,
      String field = 'toolbarItems',
      Map<String, dynamic>? item,
    }) {
      final json = _baseManifest(
        minAppVersion: '0.9.99',
        permissions: const [
          'app.startup_contributions',
          'reader.toolbar',
          'reader.context_menu',
        ],
      );
      final contributes = json['contributes'] as Map<String, dynamic>;
      if (allowMultiple) {
        (contributes['toolTab'] as Map<String, dynamic>)['allowMultipleInstances'] =
            true;
      }
      contributes['startup'] = {
        field: [
          item ??
              {
                'id': 'open-new',
                'title': 'פתח',
                'openPlugin': true,
                'newTab': true,
              },
        ],
      };
      return json;
    }

    bool mentionsNewTab(PluginValidationReport report) =>
        report.errors.any((e) => e.contains('newTab'));

    for (final field in ['toolbarItems', 'contextMenuItems']) {
      test('$field: newTab בלי allowMultipleInstances נדחה', () {
        final report = _runOn(
          tempDir,
          manifestOverride: manifest(allowMultiple: false, field: field),
        );
        expect(mentionsNewTab(report), isTrue, reason: '${report.errors}');
      });

      test('$field: newTab עם allowMultipleInstances תקין', () {
        final report = _runOn(
          tempDir,
          manifestOverride: manifest(allowMultiple: true, field: field),
        );
        expect(mentionsNewTab(report), isFalse, reason: '${report.errors}');
      });
    }

    test('newTab בלי openPlugin נדחה גם כשהתוסף מצהיר על מופעים', () {
      final report = _runOn(
        tempDir,
        manifestOverride: manifest(
          allowMultiple: true,
          item: {'id': 'open-new', 'title': 'פתח', 'newTab': true},
        ),
      );
      expect(mentionsNewTab(report), isTrue, reason: '${report.errors}');
    });
  });
}
