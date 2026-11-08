import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/update/differential/managed_paths.dart';

import '../../tool/release/generate_app_file_manifest.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('otzaria-app-files');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String relative, String content) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  Map<String, Object?> build({
    String tag = '0.9.97+789',
    String version = '0.9.97',
    String architecture = 'x64',
  }) => buildAppFileManifest(
    releaseTag: tag,
    releaseVersion: version,
    platform: 'windows',
    architecture: architecture,
    root: root,
  );

  List<String> pathsOf(Map<String, Object?> manifest) =>
      (manifest['files'] as List)
          .map((f) => (f as Map)['path'] as String)
          .toList();

  group('מניפסט קובצי האפליקציה', () {
    test('סורק את כל העץ ומחזיר נתיבים יחסיים ממוינים עם sha256', () {
      write('otzaria.exe', 'exe');
      write('data/app.so', 'snapshot');
      write('data/flutter_assets/assets/שמור וזכור.png', 'hebrew-name');

      final manifest = build();

      expect(pathsOf(manifest), [
        'data/app.so',
        'data/flutter_assets/assets/שמור וזכור.png',
        'otzaria.exe',
      ]);
      expect(manifest['fileCount'], 3);
      expect(manifest['installedSize'], 3 + 8 + 11);
      expect(validateAppFileManifest(manifest), isEmpty);
      for (final file in (manifest['files'] as List).cast<Map>()) {
        expect(file['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      }
    });

    test('הארכיטקטורה היא חלק מהזהות ומשם הנכס', () {
      write('otzaria.exe', 'exe');

      expect(build(architecture: 'arm64')['architecture'], 'arm64');
      expect(
        appFileManifestAssetName(platform: 'windows', architecture: 'arm64'),
        'otzaria-app-files-windows-arm64.json',
      );
      expect(
        appFileManifestAssetName(platform: 'windows', architecture: 'x64'),
        isNot(
          appFileManifestAssetName(
            platform: 'windows',
            architecture: 'arm64',
          ),
        ),
      );
    });

    test('portable.marker מוחרג — הוא נוסף ל-ZIP ואינו קובץ התקנה', () {
      write('otzaria.exe', 'exe');
      write('portable.marker', '');

      expect(pathsOf(build()), ['otzaria.exe']);
    });

    test('תיקייה ריקה, תג ריק או ארכיטקטורה פסולה נכשלים', () {
      expect(() => build(), throwsA(isA<AppFileManifestException>()));
      write('otzaria.exe', 'exe');
      expect(() => build(tag: '  '), throwsA(isA<AppFileManifestException>()));
      expect(
        () => build(architecture: 'X64'),
        throwsA(isA<AppFileManifestException>()),
      );
    });

    test('requireAppFileManifestTarget דוחה אי-התאמת ארכיטקטורה', () {
      write('otzaria.exe', 'exe');
      final x64 = build();

      expect(
        () => requireAppFileManifestTarget(
          x64,
          platform: 'windows',
          architecture: 'arm64',
        ),
        throwsA(isA<AppFileManifestException>()),
      );
      expect(
        () => requireAppFileManifestTarget(
          x64,
          platform: 'windows',
          architecture: 'x64',
        ),
        returnsNormally,
      );
    });
  });

  group('כללי הנתיב המנוהל', () {
    test('נתיב יחסי עם / בלבד תקין', () {
      expect(managedApplicationPathError('data/app.so'), isNull);
      expect(managedApplicationPathError('otzaria.exe'), isNull);
    });

    test('נתיב מוחלט, מטפס או עם מפריד חלונות נדחה', () {
      expect(managedApplicationPathError(''), isNotNull);
      expect(managedApplicationPathError('/etc/passwd'), isNotNull);
      expect(managedApplicationPathError('C:/Windows/system32.dll'), isNotNull);
      expect(managedApplicationPathError(r'data\app.so'), isNotNull);
      expect(managedApplicationPathError('../outside.dll'), isNotNull);
      expect(managedApplicationPathError('data/../../outside.dll'), isNotNull);
      expect(managedApplicationPathError('data//app.so'), isNotNull);
    });
  });

  group('validateAppFileManifest', () {
    Map<String, Object?> valid() => {
      'schemaVersion': kAppFileManifestSchemaVersion,
      'releaseTag': '0.9.97+789',
      'releaseVersion': '0.9.97',
      'platform': 'windows',
      'architecture': 'x64',
      'fileCount': 2,
      'installedSize': 5,
      'files': [
        {'path': 'a.dll', 'size': 2, 'sha256': 'a' * 64},
        {'path': 'b.dll', 'size': 3, 'sha256': 'b' * 64},
      ],
    };

    test('מניפסט תקין עובר', () {
      expect(validateAppFileManifest(valid()), isEmpty);
    });

    test('גרסת סכמה גבוהה יותר נדחית', () {
      final manifest = valid()..['schemaVersion'] = 2;
      expect(validateAppFileManifest(manifest), isNotEmpty);
    });

    test('סדר, כפילות, סכום וספירה נאכפים', () {
      final unsorted = valid()
        ..['files'] = [
          {'path': 'b.dll', 'size': 3, 'sha256': 'b' * 64},
          {'path': 'a.dll', 'size': 2, 'sha256': 'a' * 64},
        ];
      expect(validateAppFileManifest(unsorted), isNotEmpty);

      final badCount = valid()..['fileCount'] = 3;
      expect(validateAppFileManifest(badCount), isNotEmpty);

      final badSize = valid()..['installedSize'] = 99;
      expect(validateAppFileManifest(badSize), isNotEmpty);
    });

    test('שדות לא מוכרים נסבלים', () {
      final manifest = valid()..['futureField'] = {'anything': true};
      expect(validateAppFileManifest(manifest), isEmpty);
    });
  });

  group('נתוני משתמש נדחים בבנייה', () {
    test('תיקיית נתונים בפלט הבנייה מפילה את הגנרטור ברעש', () {
      write('otzaria.exe', 'binary');
      for (final folder in kUserDataFolderNames) {
        expect(
          managedApplicationPathError('$folder/x.dat'),
          isNotNull,
          reason: folder,
        );
      }
      write('books/seforim.db', 'library');
      expect(
        () => build(),
        throwsA(
          isA<AppFileManifestException>().having(
            (e) => e.message,
            'message',
            contains('user data'),
          ),
        ),
      );
    });

    test('קובץ סימון בשורש נדחה, ותת-נתיב באותו שם אינו נדחה', () {
      expect(managedApplicationPathError('library_path.txt'), isNotNull);
      expect(managedApplicationPathError('data/library_path.txt'), isNull);
    });
  });

  group('מניפסט עץ (macOS, Linux)', () {
    Map<String, Object?> tree() => {
      'schemaVersion': kAppFileTreeManifestSchemaVersion,
      'releaseTag': '0.10.1+5',
      'releaseVersion': '0.10.1',
      'platform': 'macos',
      'architecture': 'universal',
      'fileCount': 1,
      'installedSize': 2,
      'files': [
        {
          'path': 'Contents/Frameworks/A.framework/Versions/A/A',
          'size': 2,
          'sha256': 'a' * 64,
          'mode': 0x1ED,
        },
      ],
      'links': [
        {
          'path': 'Contents/Frameworks/A.framework/A',
          'target': 'Versions/Current/A',
        },
        {
          'path': 'Contents/Frameworks/A.framework/Versions/Current',
          'target': 'A',
        },
      ],
    };

    test('נבנה עם הרשאות, ובסכמה 2 — Windows נשאר בסכמה 1 בלי הרשאות', () {
      write('Contents/MacOS/app', 'exe');
      final manifest = buildAppFileManifest(
        releaseTag: '0.10.1+5',
        releaseVersion: '0.10.1',
        platform: 'macos',
        architecture: 'universal',
        root: root,
        modeOf: (_) => 0x1ED,
      );
      expect(manifest['schemaVersion'], kAppFileTreeManifestSchemaVersion);
      expect((manifest['files'] as List).single, containsPair('mode', 0x1ED));
      expect(manifest['links'], isEmpty);
      expect(
        appFileManifestAssetName(platform: 'macos', architecture: 'universal'),
        'otzaria-app-files-macos-universal.json',
      );

      final windows = build();
      expect(windows['schemaVersion'], kAppFileManifestSchemaVersion);
      expect((windows['files'] as List).single, isNot(contains('mode')));
      expect(windows.containsKey('links'), isFalse);
    });

    test('מניפסט עץ תקין עובר', () {
      expect(validateAppFileManifest(tree()), isEmpty);
    });

    test('קובץ בלי הרשאות, או מניפסט Windows עם הרשאות — נדחים', () {
      final missing = tree();
      ((missing['files'] as List).single as Map).remove('mode');
      expect(validateAppFileManifest(missing), isNotEmpty);

      final windows = tree()
        ..['schemaVersion'] = kAppFileManifestSchemaVersion
        ..['platform'] = 'windows'
        ..remove('links');
      expect(validateAppFileManifest(windows), isNotEmpty);
    });

    test('symlink מוחלט, בורח מהעץ, או שקובץ עובר דרכו — נדחה', () {
      for (final target in ['/Library/x', '../../../../x', r'Versions\A']) {
        final manifest = tree();
        ((manifest['links'] as List).first as Map)['target'] = target;
        expect(validateAppFileManifest(manifest), isNotEmpty, reason: target);
      }
      final through = tree()
        ..['links'] = [
          {'path': 'Contents/Frameworks/A.framework/Versions', 'target': 'X'},
        ];
      expect(validateAppFileManifest(through), isNotEmpty);
    });

    test('symlink ונתיב קובץ זהים — כפילות', () {
      final manifest = tree();
      (manifest['links'] as List).add({
        'path': 'Contents/Frameworks/A.framework/Versions/A/A',
        'target': 'B',
      });
      expect(validateAppFileManifest(manifest), isNotEmpty);
    });

    // symlink יחסי עם `/` אינו נפתח ב-Windows; שם הלוגיקה נבדקת במערכת
    // קבצים מדומה (test/update/tree_update_test.dart).
    test('סריקה אמיתית רושמת symlinks ואינה נכנסת דרכם', () {
      write('Contents/Frameworks/A.framework/Versions/A/A', 'bin');
      Link(
        '${root.path}/Contents/Frameworks/A.framework/Versions/Current',
      ).createSync('A');
      Link(
        '${root.path}/Contents/Frameworks/A.framework/A',
      ).createSync('Versions/Current/A');
      final manifest = buildAppFileManifest(
        releaseTag: '0.10.1+5',
        releaseVersion: '0.10.1',
        platform: 'macos',
        architecture: 'universal',
        root: root,
      );
      expect(pathsOf(manifest), [
        'Contents/Frameworks/A.framework/Versions/A/A',
      ]);
      expect(appFileManifestLinks(manifest), {
        'Contents/Frameworks/A.framework/A': 'Versions/Current/A',
        'Contents/Frameworks/A.framework/Versions/Current': 'A',
      });
    }, skip: Platform.isWindows ? 'symlinks יחסיים — POSIX בלבד' : null);

    test('symlink בבניית Windows מפיל את הגנרטור ברעש', () {
      write('otzaria.exe', 'exe');
      Link('${root.path}/alias').createSync('otzaria.exe');
      expect(() => build(), throwsA(isA<AppFileManifestException>()));
    }, skip: Platform.isWindows ? 'symlinks יחסיים — POSIX בלבד' : null);
  });
}
