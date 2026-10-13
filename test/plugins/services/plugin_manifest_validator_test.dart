import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PluginManifestValidator', () {
    test('accepts current app version with prerelease suffix', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.prerelease',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0-beta',
        ),
        completes,
      );
    });

    test('accepts a declared background entrypoint that exists', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_bg_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');
      await File(
        p.join(tempDir.path, 'background.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.background',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        backgroundEntrypoint: 'background.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        completes,
      );
    });

    test('throws when the plugin name exceeds 14 characters', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_name_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.longname',
        name: 'שם ארוך מאוד מהרשאה',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'שם ארוך מאוד מהרשאה',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(predicate((e) => e.toString().contains('לכל היותר 14 תווים'))),
      );
    });

    test('throws when the short description exceeds 150 characters', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_desc_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.longdesc',
        name: 'Validator',
        version: '1.0.0',
        description: 'א' * 151,
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(predicate((e) => e.toString().contains('לכל היותר 150 תווים'))),
      );
    });

    test('throws when toolTab.title differs from name', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_title_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.title',
        name: 'לוח שנה',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'כותרת אחרת',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(
          predicate((e) => e.toString().contains('השמות חייבים להיות זהים')),
        ),
      );
    });

    test('throws when toolTab.title is an explicit empty string', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_emptytitle_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.emptytitle',
        name: 'לוח שנה',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: '',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(
          predicate((e) => e.toString().contains('השמות חייבים להיות זהים')),
        ),
      );
    });

    test('throws when the declared background entrypoint is missing', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plugin_validator_bg_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      await File(
        p.join(tempDir.path, 'index.html'),
      ).writeAsString('<html></html>');

      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.background.missing',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        backgroundEntrypoint: 'background.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: tempDir.path,
          currentAppVersion: '1.0.0',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('דוחה נתיב או שדה לא מוכר בהצהרת מקור DB', () async {
      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.database',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        permissions: const ['database.read'],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
        databaseSources: const [
          {'id': 'app.library.main', 'path': '/private/library.db'},
        ],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: '/',
          skipAppVersionValidation: true,
          skipFileValidation: true,
        ),
        throwsA(predicate((error) => error.toString().contains('path'))),
      );
    });

    test('דוחה ערך stability לא תקין', () async {
      final manifest = PluginManifest(
        schemaVersion: 1,
        id: 'test.validator.stability',
        name: 'Validator',
        version: '1.0.0',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        stability: 'alpha',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      await expectLater(
        PluginManifestValidator.validateManifest(
          manifest: manifest,
          directoryPath: '/',
          skipAppVersionValidation: true,
          skipFileValidation: true,
        ),
        throwsA(predicate((e) => e.toString().contains('stability'))),
      );
    });

    test('collectManifestErrors אוסף את כל השגיאות בבת אחת', () async {
      final manifest = PluginManifest(
        schemaVersion: 2,
        id: 'INVALID ID',
        name: 'Validator',
        version: 'not-a-version',
        description: '',
        author: '',
        homepage: '',
        entrypoint: 'index.html',
        minAppVersion: '1.0.0',
        sdkVersion: '1.x',
        stability: 'alpha',
        permissions: const [],
        networkEnabled: false,
        networkAllowlist: const [],
        toolTabTitle: 'Validator',
        toolTabOrder: 900,
        defaultPinned: false,
        publishedDataTypes: const [],
      );

      final errors = await PluginManifestValidator.collectManifestErrors(
        manifest: manifest,
        directoryPath: '/',
        skipAppVersionValidation: true,
        skipFileValidation: true,
      );

      // schemaVersion + id + version + stability — כולן מדווחות יחד.
      expect(errors.length, greaterThanOrEqualTo(4));
      expect(errors.any((e) => e.contains('סכמה')), isTrue);
      expect(errors.any((e) => e.contains('מזהה התוסף')), isTrue);
      expect(errors.any((e) => e.contains('SemVer')), isTrue);
      expect(errors.any((e) => e.contains('stability')), isTrue);
    });

    // המזהה מרכיב את נתיב תיקיית הנתונים, ו-`..` היה מוציא את המרחב הפרטי
    // מתיקיית התוסף — ובשחזור גיבוי גם מוחק תיקייה שרירותית.
    test('isValidPluginId דוחה רצף נקודות ותווים אסורים', () {
      for (final bad in [
        '..',
        '.',
        '...',
        'INVALID ID',
        'a/b',
        r'a\b',
        'Upper',
        '',
        'a b',
      ]) {
        expect(
          PluginManifestValidator.isValidPluginId(bad),
          isFalse,
          reason: 'צריך להידחות: "$bad"',
        );
      }
      for (final good in [
        'my.plugin',
        'a-b_c.1',
        'x',
        '.hidden',
        'a..b',
      ]) {
        expect(
          PluginManifestValidator.isValidPluginId(good),
          isTrue,
          reason: 'צריך לעבור: "$good"',
        );
      }
    });

    test('קריאת API ללא הרשאה מקבלת הודעה שמכוונת להסרה', () async {
      final errors = await PluginManifestValidator.collectManifestErrors(
        manifest: _manifest(const ['feedback.report']),
        directoryPath: '/',
        skipAppVersionValidation: true,
        skipFileValidation: true,
      );
      expect(errors, hasLength(1));
      expect(errors.single, contains('אינה דורשת הרשאה'));
      expect(errors.single, contains('הסירו אותה מ-permissions'));
    });

    test('קריאת API עם הרשאה ידועה מקבלת רמז לשם ההרשאה', () async {
      final errors = await PluginManifestValidator.collectManifestErrors(
        manifest: _manifest(const ['network.fetchStream']),
        directoryPath: '/',
        skipAppVersionValidation: true,
        skipFileValidation: true,
      );
      expect(errors, hasLength(1));
      expect(errors.single, contains('האם התכוונת ל-"network.access"?'));
    });

    test('הרשאה שאינה קיימת כלל נשארת עם ההודעה הגנרית', () async {
      final errors = await PluginManifestValidator.collectManifestErrors(
        manifest: _manifest(const ['made.up.permission']),
        directoryPath: '/',
        skipAppVersionValidation: true,
        skipFileValidation: true,
      );
      expect(errors, hasLength(1));
      expect(errors.single, contains('הרשאה לא חוקית שנדרשת על ידי התוסף'));
    });

    group('platforms', () {
      PluginManifest withPlatforms(Object? platforms) =>
          PluginManifest.fromJson({
            'id': 'test.validator.platforms',
            'name': 'Validator',
            'version': '1.0.0',
            'entrypoint': 'index.html',
            'platforms': ?platforms,
          });

      Future<List<String>> errorsFor(
        Object? platforms, {
        String? currentPlatform,
      }) => PluginManifestValidator.collectManifestErrors(
        manifest: withPlatforms(platforms),
        directoryPath: '/',
        currentAppVersion: '9.9.9',
        currentPlatform: currentPlatform,
        skipAppVersionValidation: currentPlatform == null,
        skipFileValidation: true,
      );

      test('שדה חסר — תקין, ולא נשמר ב-toJson', () async {
        expect(await errorsFor(null), isEmpty);
        expect(withPlatforms(null).platforms, isNull);
        expect(withPlatforms(null).toJson().containsKey('platforms'), isFalse);
      });

      test('רשימה תקינה עוברת ונשמרת', () async {
        expect(await errorsFor(['windows', 'linux', 'macos']), isEmpty);
        expect(withPlatforms(['android']).toJson()['platforms'], ['android']);
      });

      test('ערך שאינו מערך נדחה בלי להפיל את הטעינה', () async {
        final errors = await errorsFor('windows');
        expect(errors, hasLength(1));
        expect(errors.single, contains('חייב להיות מערך'));
      });

      test('מערך ריק נדחה', () async {
        final errors = await errorsFor(<String>[]);
        expect(errors.single, contains('ריק'));
      });

      test('ערך לא מוכר וכפילות נדחים', () async {
        final errors = await errorsFor(['windows', 'web', 'windows', 3]);
        expect(errors, hasLength(3));
        expect(errors.where((e) => e.contains('"web"')), hasLength(1));
        expect(errors.where((e) => e.contains('"3"')), hasLength(1));
        expect(errors.where((e) => e.contains('פעמיים')), hasLength(1));
      });

      test('התקנה נדחית בפלטפורמה שלא הוצהרה', () async {
        final errors = await errorsFor([
          'windows',
          'macos',
        ], currentPlatform: 'android');
        expect(errors.single, contains('אינו תומך ב-android'));
        expect(
          await errorsFor(['windows', 'macos'], currentPlatform: 'macos'),
          isEmpty,
        );
        // בלי הצהרה — כל פלטפורמה מתקבלת
        expect(await errorsFor(null, currentPlatform: 'ios'), isEmpty);
      });

      test('הבדיקה מול הפלטפורמה מדולגת יחד עם בדיקת הגרסה', () async {
        final errors = await PluginManifestValidator.collectManifestErrors(
          manifest: withPlatforms(['windows']),
          directoryPath: '/',
          currentPlatform: 'android',
          skipAppVersionValidation: true,
          skipFileValidation: true,
        );
        expect(errors, isEmpty);
      });
    });
  });
}

PluginManifest _manifest(List<String> permissions) => PluginManifest(
  schemaVersion: 1,
  id: 'test.validator.permissions',
  name: 'Validator',
  version: '1.0.0',
  description: '',
  author: '',
  homepage: '',
  entrypoint: 'index.html',
  minAppVersion: '1.0.0',
  sdkVersion: '1.x',
  permissions: permissions,
  networkEnabled: false,
  networkAllowlist: const [],
  toolTabTitle: 'Validator',
  toolTabOrder: 900,
  defaultPinned: false,
  publishedDataTypes: const [],
);
