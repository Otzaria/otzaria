import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../test_helpers/memory_cache_provider.dart';
import 'design_gallery_contract_test.dart' show galleryThemeSpecs, payloadFor;
import 'design_guide_support.dart';

/// טבלת הטוקנים ב-`DESIGN_GUIDE.md` היא הרשימה הקנונית של ה-payload ושל
/// משתני ה-CSS. אין לה מקור אחר: שדה שנוסף ל-payload בלי להיכנס לטבלה, או
/// משתנה שנוסף ל-`tokens.css` בלי תיעוד, שוברים את הבדיקות האלה.
const String kGuidePath = '$kSdkDocsDir/DESIGN_GUIDE.md';
const String kThemeJsPath = '$kGalleryDir/js/theme.js';
const String kTokensCssPath = '$kGalleryDir/css/tokens.css';

String _kebab(String key) => key.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '-${m.group(0)!.toLowerCase()}',
);

/// המשתנה ש-applyTheme מציב לכל שדה ב-payload (null: אין משתנה לשדה הזה).
String? expectedVariable(String path) {
  final parts = path.split('.');
  final key = parts.length > 1 ? parts[1] : '';
  switch (parts.first) {
    case 'mode':
      return 'color-scheme';
    case 'radius':
      return '--radius';
    case 'colorScheme':
      return '--color-${_kebab(key)}';
    case 'surfaces':
      return '--surface-${_kebab(key)}';
    case 'spacing':
      return '--space-$key';
    case 'density':
      return switch (key) {
        'topBarHeight' => '--top-bar-height',
        'fieldHeight' => '--field-height',
        _ => null,
      };
    case 'typography':
      return switch (key) {
        'uiFont' || 'uiFontFamily' => '--font-ui',
        'fontFamily' => '--font-main',
        'commentatorsFontFamily' => '--font-commentary',
        'fontSize' => '--font-size-reading',
        'commentatorsFontSize' => '--font-size-commentary',
        'lineHeight' => '--line-height-reading',
        _ => null,
      };
  }
  return null;
}

/// כל נתיבי העלים של ה-payload, כמו `colorScheme.primary`.
Set<String> payloadPaths(Map<String, dynamic> payload) => {
  for (final entry in payload.entries)
    if (entry.value is Map)
      for (final inner in (entry.value as Map).keys) '${entry.key}.$inner'
    else
      entry.key,
};

/// שורות טבלה א': `| משתנה | שדה | שימוש |` כשהשדה הוא נתיב ב-payload.
List<({String variable, String path})> tableARows(String guide) {
  final rows = <({String variable, String path})>[];
  final rowRe = RegExp(r'^\|\s*(`[^`]+`|—)\s*\|\s*`([^`]+)`\s*\|');
  final pathRe = RegExp(
    r'^(mode|radius|(colorScheme|surfaces|spacing|density|typography)\.[\w-]+)$',
  );
  for (final line in guide.split('\n')) {
    final m = rowRe.firstMatch(line);
    if (m == null || !pathRe.hasMatch(m.group(2)!)) continue;
    rows.add((
      variable: m.group(1)!.replaceAll('`', ''),
      path: m.group(2)!,
    ));
  }
  return rows;
}

/// משתנים בטבלה ב': שורות שהעמודה השנייה שלהן אינה נתיב ב-payload.
Set<String> tableBVariables(String guide) {
  final pathRe = RegExp(r'^(mode|radius|\w+\.[\w-]+)$');
  final rowRe = RegExp(r'^\|\s*`(--[\w-]+)`\s*\|\s*([^|]+?)\s*\|\s*$');
  return {
    for (final line in guide.split('\n'))
      if (rowRe.firstMatch(line) case final m?)
        if (!pathRe.hasMatch(m.group(2)!.replaceAll('`', ''))) m.group(1)!,
  };
}

Set<String> definedCustomProperties(String css) => {
  for (final m in RegExp(
    r'^\s*(--[\w-]+)\s*:',
    multiLine: true,
  ).allMatches(css))
    m.group(1)!,
};

String _normalized(String s) => s.replaceAll('\r\n', '\n');

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late String guide;
  late Map<String, dynamic> payload;
  setUp(() {
    guide = _normalized(File(kGuidePath).readAsStringSync());
    payload = payloadFor(galleryThemeSpecs.first);
  });

  group('טבלת הטוקנים', () {
    test('שדות הטבלה שווים לשדות ה-payload של buildThemePayloadFromScheme', () {
      final documented = tableARows(guide).map((r) => r.path).toSet();
      final actual = payloadPaths(payload);
      expect(
        actual.difference(documented),
        isEmpty,
        reason: 'שדות ב-payload שאינם בטבלה',
      );
      expect(
        documented.difference(actual),
        isEmpty,
        reason: 'שדות בטבלה שאינם ב-payload',
      );
    });

    test('שם המשתנה בכל שורה הוא זה ש-applyTheme מציבה לשדה', () {
      final wrong = [
        for (final row in tableARows(guide))
          if (row.variable != (expectedVariable(row.path) ?? '—'))
            '${row.path}: בטבלה ${row.variable}, נדרש ${expectedVariable(row.path)}',
      ];
      expect(wrong, isEmpty, reason: wrong.join('\n'));
    });

    test('המשתנים ב-tokens.css שווים לטבלאות א ו-ב', () {
      final documented = {
        for (final row in tableARows(guide))
          if (row.variable.startsWith('--')) row.variable,
        ...tableBVariables(guide),
      };
      final defined = definedCustomProperties(
        File(kTokensCssPath).readAsStringSync(),
      );
      expect(
        defined.difference(documented),
        isEmpty,
        reason: 'מוגדר ב-tokens.css ולא מתועד',
      );
      expect(
        documented.difference(defined),
        isEmpty,
        reason: 'מתועד ולא מוגדר ב-tokens.css',
      );
    });

    test('השדות שווים להגדרות הטיפוסים ב-otzaria_plugin.d.ts', () {
      final dts = File('$kSdkDocsDir/otzaria_plugin.d.ts').readAsStringSync();
      Set<String> keysOf(String interfaceName) {
        final body = RegExp(
          'export interface $interfaceName \\{([\\s\\S]*?)\\n\\}',
        ).firstMatch(dts)!.group(1)!;
        return {
          for (final line in body.split('\n'))
            if (RegExp(r'''^\s+['"]?([\w-]+)['"]?\??:''').firstMatch(line)
                case final m?)
              m.group(1)!,
        };
      }

      const interfaces = {
        'ColorScheme': 'colorScheme',
        'Typography': 'typography',
        'ThemeSurfaces': 'surfaces',
        'ThemeSpacing': 'spacing',
        'ThemeDensity': 'density',
      };
      interfaces.forEach((name, payloadKey) {
        expect(
          keysOf(name),
          (payload[payloadKey] as Map).keys.toSet(),
          reason: '$name מול payload.$payloadKey',
        );
      });
      expect(
        keysOf('ThemePayload'),
        payload.keys.toSet(),
        reason: 'ThemePayload',
      );
    });
  });

  group('applyTheme', () {
    test('הקוד שבמדריך זהה ל-theme.js של הגלריה, מילה במילה', () {
      final blocks = fencedBlocks(
        kGuidePath,
      ).where((b) => b.body.contains('window.applyTheme = function')).toList();
      expect(blocks, hasLength(1));
      expect(
        _normalized(blocks.single.body).trim(),
        _normalized(File(kThemeJsPath).readAsStringSync()).trim(),
      );
    });

    final hasNode = () {
      try {
        return Process.runSync('node', ['--version']).exitCode == 0;
      } on ProcessException {
        return false;
      }
    }();

    test(
      'מציבה בפועל כל משתנה בטבלה, מתעלמת מ-colorScheme ריק, ומסירה משתנים ישנים',
      () async {
        final dir = Directory.systemTemp.createTempSync('otzaria_apply_theme_');
        addTearDown(() => dir.deleteSync(recursive: true));
        // ל-`regionBorder` יש ערך רק בערכת "לבן" בבהיר, ולכן היא הערכה המלאה.
        final whitePayload = payloadFor(
          galleryThemeSpecs.firstWhere((spec) => spec.id == 'light-white'),
        );
        final scenarios = {
          'full': whitePayload,
          'noRegionBorder': payload,
          'empty': {
            'mode': 'light',
            'colorScheme': <String, dynamic>{},
            'typography': <String, dynamic>{},
          },
          'legacy': payloadFor(galleryThemeSpecs.last),
        };
        File('${dir.path}/scenarios.json').writeAsStringSync(
          jsonEncode(scenarios),
        );
        File('${dir.path}/run.js').writeAsStringSync('''
const fs = require('fs');
const [themePath, scenariosPath] = process.argv.slice(2);
const scenarios = JSON.parse(fs.readFileSync(scenariosPath, 'utf8'));
function freshDom() {
  const props = {};
  const attrs = {};
  const style = {
    setProperty: (k, v) => { props[k] = v; },
    removeProperty: (k) => { delete props[k]; },
  };
  global.window = {};
  global.document = { documentElement: { style, setAttribute: (k, v) => { attrs[k] = v; } } };
  eval(fs.readFileSync(themePath, 'utf8'));
  return { props, attrs, style };
}
const out = {};
let dom = freshDom();
window.applyTheme(scenarios.full);
out.full = { props: { ...dom.props }, colorScheme: dom.style.colorScheme, mode: dom.attrs['data-theme-mode'] };
window.applyTheme(scenarios.noRegionBorder);
out.noRegionBorderAfterFull = { props: { ...dom.props } };
window.applyTheme(scenarios.full);
window.applyTheme(scenarios.legacy);
out.legacyAfterFull = { props: { ...dom.props } };
dom = freshDom();
window.applyTheme(scenarios.empty);
out.empty = { props: { ...dom.props }, colorScheme: dom.style.colorScheme };
console.log(JSON.stringify(out));
''');
        final result = await Process.run('node', [
          '${dir.path}/run.js',
          kThemeJsPath,
          '${dir.path}/scenarios.json',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final out = jsonDecode(result.stdout as String) as Map<String, dynamic>;

        final expectedVars = {
          for (final row in tableARows(guide))
            if (row.variable.startsWith('--')) row.variable,
        };
        final full = (out['full']['props'] as Map).keys.toSet();
        expect(full, expectedVars, reason: 'משתנים שהוצבו מול הטבלה');
        expect(out['full']['colorScheme'], 'light');

        // ערכה בלי קו אזורים (`regionBorder: null`) מסירה את המשתנה, והוא חוזר
        // לערך ה-:root (שקוף) במקום להישאר מהערכה הקודמת.
        final noBorder = (out['noRegionBorderAfterFull']['props'] as Map).keys;
        expect(noBorder, isNot(contains('--surface-region-border')));
        expect(noBorder, contains('--surface-warning'));
        expect(out['full']['mode'], 'light');

        expect(
          (out['empty']['props'] as Map),
          isEmpty,
          reason: 'colorScheme ריק אינו מציב דבר ואינו קורס',
        );

        final legacy = (out['legacyAfterFull']['props'] as Map).keys;
        for (final prefix in ['--surface-', '--space-', '--top-bar-height']) {
          expect(
            legacy.where((k) => k.startsWith(prefix)),
            isEmpty,
            reason: 'מארח ישן אחרי ערכה מלאה: $prefix נשאר מהערכה הקודמת',
          );
        }
        expect(
          (out['legacyAfterFull']['props'] as Map)['--font-ui'],
          "'Rubik', system-ui, sans-serif",
          reason: 'מארח בלי uiFont נופל ל-uiFontFamily',
        );
      },
      skip: hasNode ? false : 'node אינו זמין',
    );
  });

  group('class-ים בדוגמאות CSS של המדריך קיימים בגלריה', () {
    test(
      'כל סלקטור class שבבלוקי ה-css מוגדר ב-components.css או gallery.css',
      () {
        final galleryCss = [
          File('$kGalleryDir/css/components.css').readAsStringSync(),
          File('$kGalleryDir/css/gallery.css').readAsStringSync(),
        ].join('\n');
        final defined = {
          for (final m in RegExp(r'\.([a-z][\w-]*)').allMatches(galleryCss))
            m.group(1)!,
        };
        final missing = <String>{};
        for (final block in fencedBlocks(kGuidePath)) {
          if (block.language != 'css') continue;
          final selectors = block.body
              .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
              .replaceAll(RegExp(r'\{[^{}]*\}'), '{}');
          for (final m in RegExp(r'\.([a-z][\w-]*)').allMatches(selectors)) {
            if (!defined.contains(m.group(1)!)) {
              missing.add('${block.where}: .${m.group(1)}');
            }
          }
        }
        expect(missing, isEmpty, reason: missing.join('\n'));
      },
    );
  });
}
