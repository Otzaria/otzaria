import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_design_rules.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:path/path.dart' as p;

/// כללי העיצוב של בודק התוספים (סעיף 38): מה מותר ב-`font-family`, מה אומרות
/// הודעות הכשל, ושמפרט `spec.json` נושא את אותם כללים בדיוק (כדי שהעותק
/// ב-otzaria-plugin-validator לא יסחף).
PluginValidationReport _runCss(Directory tempDir, String css) {
  final json = <String, dynamic>{
    'schemaVersion': 1,
    'id': 'test.design.rules',
    'name': 'Test',
    'version': '1.0.0',
    'description': '',
    'author': '',
    'homepage': '',
    'entrypoint': 'index.html',
    'minAppVersion': '0.9.94',
    'sdkVersion': '1.x',
    'permissions': <String>[],
    'contributes': {
      'toolTab': {'title': 'Test', 'order': 900, 'defaultPinned': true},
      'publishedDataTypes': <String>[],
    },
  };
  final dir = Directory(p.join(tempDir.path, 'plugin'))..createSync();
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync(jsonEncode(json));
  File(
    p.join(dir.path, 'index.html'),
  ).writeAsStringSync('<html lang="he" dir="rtl"></html>');
  File(p.join(dir.path, 'styles.css')).writeAsStringSync(css);
  return PluginExtendedValidator.validate(
    manifest: PluginManifest.fromJson(json),
    manifestJson: json,
    directoryPath: dir.path,
  );
}

const _colorUse = 'body { color: var(--color-on-primary); }';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otzaria_design_rules_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('font-family', () {
    for (final keyword in const ['inherit', 'initial', 'unset', 'system-ui']) {
      test('הערך $keyword מותר', () {
        final report = _runCss(
          tempDir,
          '$_colorUse\nbutton { font-family: $keyword; }',
        );
        expect(
          report.design.violations.where((v) => v.contains('font-family')),
          isEmpty,
        );
      });
    }

    test('גופן מקודד אחר עדיין נפסל', () {
      final report = _runCss(
        tempDir,
        '$_colorUse\nbody { font-family: serif; }',
      );
      expect(
        report.design.violations.where((v) => v.contains('font-family')),
        hasLength(1),
      );
    });

    test('var(--font-ui) מותר', () {
      final report = _runCss(
        tempDir,
        '$_colorUse\nbody { font-family: var(--font-ui); }',
      );
      expect(
        report.design.violations.where((v) => v.contains('font-family')),
        isEmpty,
      );
    });

    test('font-family בתוך @font-face אינו נבדק (שם הגופן הוא ההגדרה)', () {
      final report = _runCss(tempDir, '''
$_colorUse
@font-face { font-family: "MyFont"; src: url(my.woff2); }
''');
      expect(
        report.design.violations.where((v) => v.contains('font-family')),
        isEmpty,
      );
    });

    test('@font-face לא מכסה כלל אחר באותו קובץ', () {
      final report = _runCss(tempDir, '''
$_colorUse
@font-face { font-family: "MyFont"; src: url(my.woff2); }
.card { font-family: serif; }
''');
      expect(
        report.design.violations.where((v) => v.contains('font-family')),
        hasLength(1),
      );
    });
  });

  group('הודעות כשל מפנות לטוקנים שקיימים במדריך', () {
    test('רדיוס: var(--radius) ואין גלולות, בלי radius-sm/md/lg/pill', () {
      final report = _runCss(
        tempDir,
        '$_colorUse\n.chip { border-radius: 12px; }',
      );
      final message = report.design.violations.singleWhere(
        (v) => v.contains('border-radius'),
      );
      expect(message, contains('var(--radius) (8). אין גלולות'));
      expect(message, isNot(contains('radius-sm')));
      expect(message, isNot(contains('pill')));
    });

    test('גופן: var(--font-ui) לממשק או var(--font-main) לטקסט ספר', () {
      final report = _runCss(
        tempDir,
        '$_colorUse\nbody { font-family: serif; }',
      );
      final message = report.design.violations.singleWhere(
        (v) => v.contains('font-family'),
      );
      expect(
        message,
        contains('var(--font-ui) לממשק, או var(--font-main) לטקסט ספר'),
      );
    });

    test('גודל גופן: var(--text-*), ו-px רק בסרגל העליון', () {
      final report = _runCss(tempDir, '$_colorUse\n.card { font-size: 18px; }');
      final message = report.design.violations.singleWhere(
        (v) => v.contains('font-size'),
      );
      expect(message, contains('var(--text-*)'));
      expect(message, contains('topbar'));
      expect(message, isNot(contains('--font-size-base')));
    });
  });

  group('designRules ב-spec.json', () {
    final spec =
        jsonDecode(
              File(
                '${Directory.current.path}/docs/plugin-sdk/spec.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    test('קיים ושווה לכללים שהבודק באפליקציה משתמש בהם', () {
      final rules = spec['designRules'] as Map<String, dynamic>;
      expect(
        (rules['fontFamilyKeywords'] as List).cast<String>().toSet(),
        pluginDesignFontFamilyKeywords,
      );
      expect(
        (rules['colorKeywords'] as List).cast<String>().toSet(),
        pluginDesignColorKeywords,
      );
      expect(rules['topBarSelectorPattern'], pluginDesignTopBarSelectorPattern);
      expect(
        (rules['skippedAtRules'] as List).cast<String>().toSet(),
        pluginDesignSkippedAtRules,
      );
      expect(rules['hints'], {
        'fontFamily': pluginDesignFontFamilyHint,
        'fontSizePx': pluginDesignFontSizeHint,
        'radiusPx': pluginDesignRadiusHint,
      });
    });
  });
}
