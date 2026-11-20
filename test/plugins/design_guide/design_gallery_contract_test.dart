import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/utils/plugin_icon_resolver.dart';
import 'package:otzaria/plugins/utils/plugin_theme_changed_payload.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_seed_colors.dart';

import '../../test_helpers/memory_cache_provider.dart';
import 'design_guide_support.dart';

/// חוזה תוסף הדוגמה `design-gallery`: ה-manifest תקין מול הסכימה האמיתית,
/// הוולידטור של החנות מקבל אותו בלי שגיאות ואזהרות, כל קריאת API קיימת
/// ב-spec.json (ובגרסה שה-manifest מצהיר), והערכות שבגלריה נגזרות מה-payload
/// האמיתי של האפליקציה ולא נערכות ביד.
const String kFixturesPath = '$kGalleryDir/js/fixtures.js';

const bool kUpdateFixtures = bool.fromEnvironment('update_gallery_fixtures');

const String kRegenerateFixtures =
    'flutter test test/plugins/design_guide/design_gallery_contract_test.dart '
    '--dart-define=update_gallery_fixtures=true';

typedef GalleryThemeSpec = ({
  String id,
  String label,
  Color seed,
  Brightness brightness,
  bool compact,
  bool legacyHost,
});

const List<GalleryThemeSpec> galleryThemeSpecs = [
  (
    id: 'light-default',
    label: 'בהיר, ברירת מחדל',
    seed: AppSeedColors.defaultLight,
    brightness: Brightness.light,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'dark-default',
    label: 'כהה, ברירת מחדל',
    seed: AppSeedColors.defaultDark,
    brightness: Brightness.dark,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'light-white',
    label: 'בהיר, לבן',
    seed: AppSeedColors.white,
    brightness: Brightness.light,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'light-parchment',
    label: 'בהיר, פרגמנט',
    seed: AppSeedColors.parchment,
    brightness: Brightness.light,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'light-blue',
    label: 'בהיר, כחול',
    seed: AppSeedColors.blue,
    brightness: Brightness.light,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'dark-blue',
    label: 'כהה, כחול',
    seed: AppSeedColors.blue,
    brightness: Brightness.dark,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'light-grey',
    label: 'בהיר, אפור',
    seed: AppSeedColors.grey,
    brightness: Brightness.light,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'dark-grey',
    label: 'כהה, אפור',
    seed: AppSeedColors.grey,
    brightness: Brightness.dark,
    compact: false,
    legacyHost: false,
  ),
  (
    id: 'light-compact',
    label: 'בהיר, צפיפות מצומצמת',
    seed: AppSeedColors.defaultLight,
    brightness: Brightness.light,
    compact: true,
    legacyHost: false,
  ),
  (
    id: 'legacy-host',
    label: 'מארח ישן (לפני 0.9.99)',
    seed: AppSeedColors.defaultLight,
    brightness: Brightness.light,
    compact: false,
    legacyHost: true,
  ),
];

/// ה-payload שאוצריא שולחת, כפי ש-`theme.changed` בונה אותו. גופן הממשק תלוי
/// בפלטפורמה, ולכן מקבעים Windows כדי שהקובץ לא ישתנה בין מכונות.
Map<String, dynamic> payloadFor(GalleryThemeSpec spec) {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    final payload = buildThemeChangedPayload(
      seed: spec.seed,
      brightness: spec.brightness,
      density: AppDensity(isCompact: spec.compact),
    );
    final json = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    if (spec.legacyHost) {
      // מארח לפני 0.9.99 אינו שולח את השדות שנוספו.
      for (final key in ['surfaces', 'radius', 'spacing', 'density']) {
        json.remove(key);
      }
      (json['typography'] as Map).remove('uiFont');
    }
    return json;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

String buildFixturesJs() {
  final themes = [
    for (final spec in galleryThemeSpecs)
      {'id': spec.id, 'label': spec.label, 'theme': payloadFor(spec)},
  ];
  return '// נוצר אוטומטית מ-buildThemePayloadFromScheme. אין לערוך ידנית.\n'
      '// לרענון: $kRegenerateFixtures\n'
      'window.GALLERY_THEMES = '
      '${const JsonEncoder.withIndent('  ').convert(themes)};\n';
}

String _normalized(String s) => s.replaceAll('\r\n', '\n');

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late Map<String, dynamic> manifestJson;
  late PluginManifest manifest;
  late Map<String, dynamic> spec;

  setUp(() {
    manifestJson =
        jsonDecode(File('$kGalleryDir/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    manifest = PluginManifest.fromJson(manifestJson);
    spec = loadSpec();
  });

  group('manifest', () {
    test('תקין מול הסכימה האמיתית, כולל גרסת המינימום', () async {
      final errors = await PluginManifestValidator.collectManifestErrors(
        manifest: manifest,
        directoryPath: kGalleryDir,
        currentAppVersion: manifest.minAppVersion,
      );
      expect(errors, isEmpty, reason: errors.join('\n'));
    });

    test('הוולידטור המורחב של החנות: אין שגיאות, אזהרות או הפרות עיצוב', () {
      final report = PluginExtendedValidator.validate(
        manifest: manifest,
        manifestJson: manifestJson,
        directoryPath: kGalleryDir,
      );
      expect(report.errors, isEmpty, reason: report.errors.join('\n'));
      expect(report.warnings, isEmpty, reason: report.warnings.join('\n'));
      expect(
        report.design.violations,
        isEmpty,
        reason: report.design.violations.join('\n'),
      );
      expect(report.design.compliant, isTrue);
    });

    test('אין הצהרה על הרשאות בסיס (הוולידטור מזהיר עליהן)', () {
      final baseline = (spec['baselinePermissions'] as List).cast<String>();
      expect(
        manifest.permissions.where(baseline.contains),
        isEmpty,
      );
    });

    test('אייקון הלשונית נפתר באחת הספריות', () {
      final name = manifest.toolTabIconName;
      expect(name, isNotNull);
      expect(pluginIconFromName(name), isNotNull, reason: name);
    });
  });

  group('API שבשימוש', () {
    late String source;
    setUp(() {
      source = [
        for (final file in Directory(kGalleryDir).listSync(recursive: true))
          if (file is File &&
              (file.path.endsWith('.js') || file.path.endsWith('.html')) &&
              !file.path.endsWith('fixtures.js'))
            file.readAsStringSync(),
      ].join('\n');
    });

    test('כל Otzaria.call קיים ב-spec.json ובגרסה שה-manifest מצהיר', () {
      final methods = calledMethods(source);
      expect(methods, isNotEmpty);
      final known = knownApiMethods(spec);
      final minVersions = (spec['methodMinVersions'] as Map)
          .cast<String, String>();
      final problems = <String>[];
      for (final method in methods) {
        if (!known.contains(method)) {
          problems.add('$method: אינו קיים');
          continue;
        }
        final since = minVersions[method];
        if (since != null &&
            PluginVersionUtils.compareCoreVersions(
                  since,
                  manifest.minAppVersion,
                ) >
                0) {
          problems.add(
            '$method: מגרסה $since, minAppVersion=${manifest.minAppVersion}',
          );
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('כל קריאה מכוסה בהרשאת בסיס, או בהרשאה שהוצהרה', () {
      final baseline = (spec['baselinePermissions'] as List).cast<String>();
      final required = (spec['methodPermissions'] as Map)
          .cast<String, String?>();
      final problems = [
        for (final method in calledMethods(source))
          if (required[method] != null &&
              !baseline.contains(required[method]) &&
              !manifest.permissions.contains(required[method]))
            '$method דורש ${required[method]}',
      ];
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('כל Otzaria.on קיים ב-spec.json', () {
      final events = (spec['events'] as List).cast<String>().toSet();
      final subscribed = subscribedEvents(source);
      expect(subscribed, isNotEmpty);
      expect(subscribed.difference(events), isEmpty);
    });
  });

  group('אייקונים', () {
    test('כל סמל ב-sprite בשימוש, וכל שימוש מוגדר', () {
      final html = File('$kGalleryDir/index.html').readAsStringSync();
      final js = File('$kGalleryDir/js/gallery.js').readAsStringSync();
      final defined = {
        for (final m in RegExp(r'<symbol id="i-([\w-]+)"').allMatches(html))
          m.group(1)!,
      };
      final used = {
        for (final m in RegExp(r'href="#i-([\w-]+)"').allMatches(html))
          m.group(1)!,
        for (final m in RegExp(r"icon\('([\w-]+)'").allMatches(js)) m.group(1)!,
      };
      expect(used.difference(defined), isEmpty, reason: 'שימוש בלי הגדרה');
      expect(defined.difference(used), isEmpty, reason: 'סמל שאינו בשימוש');
    });
  });

  group('ערכות הנושא של הגלריה', () {
    test('fixtures.js נגזר מ-buildThemePayloadFromScheme (לא נערך ביד)', () {
      final expected = buildFixturesJs();
      final file = File(kFixturesPath);
      if (kUpdateFixtures) {
        file.writeAsStringSync(expected);
        return;
      }
      expect(
        _normalized(file.readAsStringSync()),
        _normalized(expected),
        reason: 'הרצה מחדש: $kRegenerateFixtures',
      );
    });

    test(
      'לכל ערכה קיימים שדות ה-colorScheme, וערכת מארח ישן ללא השדות החדשים',
      () {
        final themes = galleryThemeSpecs.map(payloadFor).toList();
        for (final theme in themes) {
          expect((theme['colorScheme'] as Map), isNotEmpty);
        }
        final legacy = payloadFor(galleryThemeSpecs.last);
        expect(legacy.containsKey('surfaces'), isFalse);
        expect(legacy.containsKey('density'), isFalse);
        expect((legacy['typography'] as Map).containsKey('uiFont'), isFalse);
        expect(
          (legacy['typography'] as Map).containsKey('uiFontFamily'),
          isTrue,
        );
      },
    );
  });

  group('כללי CSS של הגלריה (ממצאים 04, 05, 08, 09, 11 בביקורת)', () {
    late String components;
    late String tokens;
    setUp(() {
      components = File('$kGalleryDir/css/components.css').readAsStringSync();
      tokens = File('$kGalleryDir/css/tokens.css').readAsStringSync();
    });

    test('גבהי פס, כפתור ושדה מהטוקנים ולא ממספרים קשיחים', () {
      expect(components, contains('height: var(--top-bar-height)'));
      expect(components, contains('min-height: var(--tap-target)'));
      expect(components, contains('min-height: var(--field-height)'));
      expect(components, isNot(matches(RegExp(r'height:\s*(44|56)px'))));
    });

    test(
      'רקע הדף מ-surfaces.panel, פס מ-surfaces.topBar, כרטיס מ-outlineVariant',
      () {
        expect(
          RegExp(
            r'body\s*\{[^}]*background:\s*var\(--surface-panel\)',
          ).hasMatch(components),
          isTrue,
        );
        expect(components, contains('background: var(--surface-top-bar)'));
        expect(
          RegExp(
            r'\.card\s*\{[^}]*border:\s*1px solid var\(--color-outline-variant\)',
          ).hasMatch(components),
          isTrue,
        );
      },
    );

    test('כותרת הפס 18px, וגופן הקריאה אינו קובע את גודל הממשק', () {
      expect(
        RegExp(r'\.topbar h1\s*\{[^}]*font-size:\s*18px').hasMatch(components),
        isTrue,
      );
      expect(components, isNot(contains('--font-size-reading')));
    });

    test('ריווח רק מהסולם: אין px ב-padding/margin/gap', () {
      final offenders = [
        for (final file in ['components.css', 'gallery.css'])
          for (final line in File('$kGalleryDir/css/$file').readAsLinesSync())
            if (RegExp(
                  r'^\s*(padding|margin|gap|row-gap|column-gap)[\w-]*:',
                ).hasMatch(line) &&
                RegExp(r'\d+px').hasMatch(line))
              '$file: ${line.trim()}',
      ];
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('בלי prefers-color-scheme: המצב נקבע לפי הגדרת האפליקציה', () {
      expect(components, isNot(contains('prefers-color-scheme')));
      expect(tokens, isNot(contains('prefers-color-scheme')));
    });

    test('רספונסיביות לפי המכל (@container), לא לפי החלון', () {
      expect(components, contains('@container'));
      expect(components, isNot(contains('@media (max-width')));
    });

    test('יעד מגע 48 לפי pointer: coarse', () {
      expect(tokens, contains('@media (pointer: coarse)'));
      expect(
        RegExp(
          r'pointer: coarse\)\s*\{\s*:root\s*\{\s*--tap-target:\s*48px',
        ).hasMatch(tokens),
        isTrue,
      );
    });
  });
}
