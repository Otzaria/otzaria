import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';

import '../../tool/download_assistant/fixtures/generate_fixtures.dart';
import '../../tool/release/download_assistant_selection.dart';
import '../../tool/release/generate_release_manifest.dart';

void main() {
  group('קובצי הייחוס של החוזה', () {
    // שלושת המסייעים נבדקים מול הקבצים האלה; קובץ מיושן היה מאשר מימוש שגוי.
    test('release-manifest.json תואם לגנרטור', () {
      final onDisk = File(
        '$kFixtureDir/release-manifest.json',
      ).readAsStringSync();
      expect(
        onDisk,
        encodeFixture(buildFixtureManifest()),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
    });

    test('expected-selections.json תואם למימוש הייחוס', () {
      final manifest =
          jsonDecode(
                File('$kFixtureDir/release-manifest.json').readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(validateReleaseManifest(manifest), isEmpty);
      final onDisk = File(
        '$kFixtureDir/expected-selections.json',
      ).readAsStringSync();
      expect(
        onDisk,
        encodeFixture(buildExpectedSelections(manifest)),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
    });

    test('הווריאנט של FULL בגודל 4 GiB תואם למימוש הייחוס', () {
      final manifest = buildLargeFullFixtureManifest();
      expect(
        File(
          '$kFixtureDir/release-manifest-large-full.json',
        ).readAsStringSync(),
        encodeFixture(manifest),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
      expect(
        File(
          '$kFixtureDir/expected-selections-large-full.json',
        ).readAsStringSync(),
        encodeFixture(
          buildExpectedSelections(manifest, targets: kLargeFullTargets),
        ),
        reason:
            'run: dart run tool/download_assistant/fixtures/generate_fixtures.dart',
      );
    });

    test(
      'בבחירה האישית החיפוש החכם הוא אפשרות אחת בגודל של שני חלקיו (issue #1869)',
      () {
        Map<String, Object?> read(String name) =>
            jsonDecode(File('$kFixtureDir/$name').readAsStringSync())
                as Map<String, Object?>;
        final manifest = read('release-manifest.json');
        final byId = {
          for (final c
              in (manifest['components'] as List).cast<Map<String, Object?>>())
            c['id']: c,
        };
        final targets = (read('expected-selections.json')['targets'] as List)
            .cast<Map<String, Object?>>();
        for (final platform in const ['windows', 'linux', 'macos']) {
          final model = byId['semantic-model-$platform']!;
          final vectors = byId['semantic-vectors-$platform']!;
          for (final entry in targets.where(
            (t) => (t['target'] as Map)['platform'] == platform,
          )) {
            final label = '${entry['target']}';
            final choices = (entry['customChoices'] as List?)
                ?.cast<Map<String, Object?>>();
            expect(choices, isNotNull, reason: label);
            final semantic = choices!
                .where((c) => (c['id'] as String).startsWith('semantic-'))
                .toList();
            expect(semantic, hasLength(1), reason: label);
            expect(
              byId[semantic.single['id']]!['name'],
              kSemanticSearchModeLabel,
              reason: label,
            );
            expect(
              semantic.single['downloadSize'],
              (model['downloadSize'] as int) + (vectors['downloadSize'] as int),
              reason: label,
            );
          }
        }
      },
    );
  });

  group('כל הצעה ניתנת להתקנה', () {
    List<AssistantTarget> allTargets(Map<String, Object?> manifest) => [
      for (final platform in platformChoices(manifest))
        for (final arch in [
          ...architectureChoices(manifest, platform),
          if (architectureChoices(manifest, platform).isEmpty) '',
        ])
          for (final format in [
            ...packageFormatChoices(manifest, platform, arch),
            if (packageFormatChoices(manifest, platform, arch).isEmpty) '',
          ])
            AssistantTarget(
              platform: platform,
              architecture: arch,
              packageFormat: format,
            ),
    ];

    // חוזה: כל רכיב שמותקן על ידי אחר מגיע עם מי שמתקין אותו, אין בהצעה
    // exe שאי אפשר להריץ, ו"מלאה" מביאה ספרייה (בחבילה או לצד התוכנה).
    for (final entry in {
      'release-manifest.json': buildFixtureManifest,
      'release-manifest-large-full.json': buildLargeFullFixtureManifest,
    }.entries) {
      test(entry.key, () {
        final manifest = entry.value();
        final byId = {
          for (final c
              in (manifest['components'] as List).cast<Map<String, Object?>>())
            c['id']: c,
        };
        for (final target in allTargets(manifest)) {
          for (final preset in buildPresets(manifest, target)) {
            final label = '${target.toJson()} ${preset.id}';
            for (final id in preset.members) {
              final component = byId[id]!;
              expect(
                componentIsOffered(manifest, component, target),
                isTrue,
                reason: '$label: $id',
              );
              final installers =
                  (component['installedBy'] as List?)?.cast<String>() ??
                  const <String>[];
              expect(
                component['type'] != 'library' || installers.isNotEmpty,
                isTrue,
                reason: '$label: הספרייה $id בלי מתקין',
              );
              if (installers.isEmpty) continue;
              expect(
                preset.members.any(installers.contains),
                isTrue,
                reason: '$label: $id בלי המתקין שלו',
              );
            }
            if (preset.id == 'full' || preset.id == 'full-indexed') {
              expect(
                preset.members.any(
                  (id) =>
                      byId[id]!['type'] == 'application-bundle' ||
                      byId[id]!['type'] == 'library',
                ),
                isTrue,
                reason: '$label: "מלאה" בלי ספרייה',
              );
            }
            if (preset.id == 'basic' || preset.id == 'update') {
              expect(
                preset.members.where(
                  (id) => kOfflineDataTypes.contains(byId[id]!['type']),
                ),
                isEmpty,
                reason: '$label: נתוני החיפוש החכם רק בהצעות המלאות',
              );
            }
            if (preset.id == 'full-indexed') {
              expect(
                preset.members.any((id) => byId[id]!['type'] == 'library'),
                isTrue,
                reason: '$label: "מלאה + אינדקס" בלי הספרייה המאונדקסת',
              );
            }
          }
        }
      });
    }
  });

  group('componentFitsTarget', () {
    const linuxDebX64 = AssistantTarget(
      platform: 'linux',
      architecture: 'x64',
      packageFormat: 'deb',
    );

    test('שדה חסר או any מתאים לכל יעד', () {
      expect(componentFitsTarget({'id': 'a'}, linuxDebX64), isTrue);
      expect(
        componentFitsTarget({
          'platform': 'any',
          'architecture': 'any',
          'packageFormat': 'any',
        }, linuxDebX64),
        isTrue,
      );
    });

    test('packageFormat any אינו פורמט לבחירה', () {
      final manifest = {
        'components': [
          {'platform': 'linux', 'type': 'application', 'packageFormat': 'deb'},
          {'platform': 'linux', 'type': 'library', 'packageFormat': 'any'},
        ],
      };
      expect(packageFormatChoices(manifest, 'linux', 'x64'), ['deb']);
    });

    test('פלטפורמה, ארכיטקטורה ופורמט חייבים להתאים', () {
      expect(
        componentFitsTarget({'platform': 'windows'}, linuxDebX64),
        isFalse,
      );
      expect(
        componentFitsTarget({
          'platform': 'linux',
          'architecture': 'arm64',
        }, linuxDebX64),
        isFalse,
      );
      expect(
        componentFitsTarget({
          'platform': 'linux',
          'architecture': 'x64',
          'packageFormat': 'rpm',
        }, linuxDebX64),
        isFalse,
      );
    });

    test('portable מסנן כל חבילה של מנהל חבילות', () {
      const portable = AssistantTarget(
        platform: 'linux',
        architecture: 'x64',
        packageFormat: kPortablePackageFormat,
      );
      expect(
        componentFitsTarget({
          'platform': 'linux',
          'packageFormat': 'deb',
        }, portable),
        isFalse,
      );
      expect(componentFitsTarget({'platform': 'linux'}, portable), isTrue);
    });

    test('פלטפורמה עתידית שאינה מוכרת לעולם אינה נכנסת ליעד מוכר', () {
      for (final platform in kAssistantPlatforms) {
        expect(
          componentFitsTarget({
            'platform': 'ios',
          }, AssistantTarget(platform: platform)),
          isFalse,
        );
      }
    });
  });

  group('shouldAssembleSplitAsset', () {
    Map<String, Object?> asset(String name, int size) => {
      'name': name,
      'size': size,
    };

    test('Windows: exe מתחת ל-4 GiB בלבד', () {
      expect(shouldAssembleSplitAsset(asset('a.exe', 100), 'windows'), isTrue);
      expect(
        shouldAssembleSplitAsset(
          asset('a.exe', kMaxSingleOutputFileSize),
          'windows',
        ),
        isFalse,
      );
      // ארכיון הספרייה נצרך כחלקים על ידי מתקין ה-FULL המאונדקס.
      expect(
        shouldAssembleSplitAsset(asset('lib.tar.zst', 100), 'windows'),
        isFalse,
      );
    });

    test('שאר היעדים: כל נכס מתחת ל-4 GiB, כי המשתמש פורס אותו', () {
      for (final platform in const ['linux', 'macos', 'android']) {
        expect(
          shouldAssembleSplitAsset(asset('full.tar.zst', 100), platform),
          isTrue,
        );
        expect(
          shouldAssembleSplitAsset(
            asset('full.tar.zst', kMaxSingleOutputFileSize),
            platform,
          ),
          isFalse,
          reason: 'FAT32 אינו מחזיק קובץ של 4 GiB',
        );
      }
    });
  });

  group('defaultPackageFormat', () {
    const choices = ['deb', 'rpm', 'portable'];

    test('ID קודם ל-ID_LIKE', () {
      expect(
        defaultPackageFormat('ID=fedora\nID_LIKE=debian\n', choices),
        'rpm',
      );
    });

    test('פורמט שאינו בנמצא נופל לבחירה הראשונה', () {
      expect(defaultPackageFormat('ID=arch\n', const ['deb', 'rpm']), 'deb');
      expect(defaultPackageFormat('ID=fedora\n', const ['deb']), 'deb');
    });

    test('בלי אפשרויות — ריק', () {
      expect(defaultPackageFormat(null, const []), '');
    });
  });

  group('buildPresets', () {
    Map<String, Object?> manifest(List<Map<String, Object?>> components) => {
      'components': components,
    };

    Map<String, Object?> component(
      String id,
      String type, {
      String? platform,
      String? architecture,
      bool required = false,
      int size = 1,
      List<String> dependsOn = const [],
      List<String>? installedBy,
      List<Map<String, Object?>> assets = const [],
    }) => {
      'id': id,
      'type': type,
      'required': required,
      'downloadSize': size,
      'dependsOn': dependsOn,
      'installedBy': ?installedBy,
      'platform': ?platform,
      'architecture': ?architecture,
      'assets': assets,
    };

    const x64 = AssistantTarget(platform: 'windows', architecture: 'x64');
    const arm64 = AssistantTarget(platform: 'windows', architecture: 'arm64');

    List<String> fullOf(List<AssistantPreset> presets) =>
        presets.singleWhere((p) => p.id == 'full').members;

    Map<String, List<String>> byId(List<AssistantPreset> presets) => {
      for (final preset in presets) preset.id: preset.members,
    };

    List<Map<String, Object?>> semanticData() => [
      component('model', 'semantic-model', platform: 'windows'),
      component(
        'vectors',
        'semantic-vectors',
        platform: 'windows',
        dependsOn: ['model'],
      ),
    ];

    List<Map<String, Object?>> windowsWithLibrary({int fullSize = 90}) => [
      component(
        'app-arm',
        'application',
        platform: 'windows',
        architecture: 'arm64',
      ),
      component(
        'app-x64',
        'application',
        platform: 'windows',
        architecture: 'x64',
        required: true,
      ),
      component(
        'full',
        'application-bundle',
        platform: 'windows',
        architecture: 'x64',
        size: fullSize,
        assets: [
          {'kind': 'split', 'name': 'full.exe', 'size': fullSize},
        ],
      ),
      component(
        'indexed',
        'application-bundle',
        platform: 'windows',
        architecture: 'x64',
        size: 5,
      ),
      component(
        'lib',
        'library',
        platform: 'any',
        size: 80,
        installedBy: ['indexed'],
      ),
    ];

    test('תלות שאינה מוצעת ביעד מדולגת', () {
      expect(
        withDependencies(
          manifest([
            component(
              'app-arm',
              'application',
              platform: 'windows',
              architecture: 'arm64',
              dependsOn: ['app-x64'],
            ),
            component(
              'app-x64',
              'application',
              platform: 'windows',
              architecture: 'x64',
            ),
          ]),
          ['app-arm'],
          arm64,
        ),
        ['app-arm'],
      );
    });

    // ספרייה שרק מתקין x64 קורא צורפה פעם למתקין ARM64 הרגיל.
    test('ספרייה שאין לה מתקין ביעד אינה מוצעת ואינה ב"מלאה"', () {
      final m = manifest(windowsWithLibrary());
      final library = (m['components'] as List).last as Map<String, Object?>;
      expect(componentIsOffered(m, library, arm64), isFalse);
      final presets = buildPresets(m, arm64);
      expect(presets.map((p) => p.id), ['basic']);
      expect(presets.single.members, ['app-arm']);
    });

    test('בחירה אישית של הספרייה מביאה את המתקין שקורא אותה', () {
      expect(withDependencies(manifest(windowsWithLibrary()), ['lib'], x64), [
        'indexed',
        'lib',
      ]);
    });

    test('exe של 4 GiB אינו מוצע; "מלאה" עוברת למתקין שקורא את הספרייה', () {
      final m = manifest(
        windowsWithLibrary(fullSize: kMaxSingleOutputFileSize),
      );
      final full = (m['components'] as List).cast<Map<String, Object?>>()[2];
      expect(componentIsOffered(m, full, x64), isFalse);
      // "מלאה" זהה ל"מלאה + אינדקס", ונשאר השם המפורט.
      final presets = buildPresets(m, x64);
      expect(presets.map((p) => p.id), ['basic', 'full-indexed']);
      expect(byId(presets)['full-indexed'], ['indexed', 'lib']);

      final runnable = manifest(
        windowsWithLibrary(fullSize: kMaxSingleOutputFileSize - 1),
      );
      expect(fullOf(buildPresets(runnable, x64)), ['full']);
    });

    test('החבילה הגדולה ביותר נבחרת להצעה המלאה', () {
      final presets = buildPresets(
        manifest([
          component('small', 'application-bundle', platform: 'macos', size: 5),
          component('big', 'application-bundle', platform: 'macos', size: 9),
        ]),
        const AssistantTarget(platform: 'macos'),
      );
      expect(presets.single.members, ['big']);
    });

    test('"מלאה + אינדקס": החבילה המאונדקסת, הספרייה שלה והחיפוש החכם', () {
      final presets = buildPresets(
        manifest([...windowsWithLibrary(), ...semanticData()]),
        x64,
      );
      expect(presets.map((p) => p.id), ['basic', 'full-indexed', 'full']);
      expect(byId(presets)['full-indexed'], [
        'indexed',
        'lib',
        'model',
        'vectors',
      ]);
      expect(byId(presets)['full'], ['full', 'model', 'vectors']);
      expect(byId(presets)['basic'], ['app-x64']);
    });

    test('החבילה המאונדקסת היא הגדולה בסך הכול, עם הספרייה', () {
      final presets = byId(
        buildPresets(
          manifest([
            component('idx-a', 'application-bundle', size: 10),
            component('lib-a', 'library', size: 1, installedBy: ['idx-a']),
            component('idx-b', 'application-bundle', size: 5),
            component('lib-b', 'library', size: 50, installedBy: ['idx-b']),
          ]),
          x64,
        ),
      );
      expect(presets['full-indexed'], ['idx-b', 'lib-b']);
      expect(presets['full'], ['idx-a', 'lib-a'], reason: 'לפי גודל החבילה');
    });

    test('בלי חבילה שמתקינה ספרייה אין "מלאה + אינדקס", חוץ מ-Android', () {
      final fixture = buildFixtureManifest();
      for (final target in kFixtureTargets) {
        if (target.platform == 'android') continue;
        final ids = buildPresets(fixture, target).map((p) => p.id);
        expect(
          ids.contains('full-indexed'),
          false,
          reason: '${target.toJson()}',
        );
      }
    });

    test('Android: ה-APK עם חבילת הספרייה והאינדקס, כמו חבילת ה-FULL', () {
      final presets = byId(
        buildPresets(
          buildFixtureManifest(),
          const AssistantTarget(platform: 'android'),
        ),
      );
      expect(presets['basic'], ['otzaria-android']);
      expect(presets['full-indexed'], [
        'otzaria-android',
        'library-full',
        'library-index',
      ]);
      expect(presets['full'], ['otzaria-android', 'library-full']);
    });

    test('"מלאה" כוללת את החיפוש החכם כמו קודם', () {
      final presets = byId(
        buildPresets(
          manifest([
            component('app', 'application', platform: 'windows'),
            component('lib', 'library', platform: 'windows'),
            ...semanticData(),
          ]),
          x64,
        ),
      );
      expect(presets['full'], ['app', 'lib', 'model', 'vectors']);
      expect(presets['basic'], ['app']);
      expect(presets.keys, isNot(contains('full-indexed')));
    });

    test('סדר ההצגה: בסיסית, מלאה + אינדקס, מלאה, עדכון', () {
      final presets = buildPresets(
        manifest([
          component('app', 'application', platform: 'windows'),
          component(
            'runtime',
            'dependency',
            platform: 'windows',
            required: true,
          ),
          ...windowsWithLibrary().where((c) => c['type'] != 'application'),
        ]),
        x64,
      );
      expect(presets.map((p) => p.id), kPresetDisplayOrder);
      expect(kPresetDisplayOrder, ['basic', 'full-indexed', 'full', 'update']);
      expect(byId(presets)['update'], ['app']);
    });

    test('המסומנת מראש: בסיסית, אחריה מלאה, אחרת הראשונה', () {
      expect(kDefaultPresetId, 'basic');
      final fixture = buildFixtureManifest();
      expect(defaultPresetIdFor(buildPresets(fixture, x64)), 'basic');
      const portable = AssistantTarget(
        platform: 'linux',
        architecture: 'x64',
        packageFormat: kPortablePackageFormat,
      );
      expect(defaultPresetIdFor(buildPresets(fixture, portable)), 'full');

      AssistantPreset only(String id) =>
          AssistantPreset(id: id, caption: '', description: '', members: []);
      expect(
        defaultPresetIdFor([only('full-indexed'), only('full')]),
        'full',
        reason: 'לא הגדולה',
      );
      expect(
        defaultPresetIdFor([only('full-indexed'), only('update')]),
        'full-indexed',
      );
      expect(defaultPresetIdFor(const []), isNull);
    });

    test('יעד בלי רכיבים — אין הצעות, ורק "בחירה אישית" תוצג', () {
      expect(
        buildPresets(
          manifest([component('w', 'application', platform: 'windows')]),
          const AssistantTarget(platform: 'android'),
        ),
        isEmpty,
      );
    });
  });

  group('הטקסט באנגלית', () {
    test('componentText: השדה האנגלי, ובהיעדרו העברי', () {
      const both = {'name': 'אוצריא', 'nameEn': 'Otzaria'};
      expect(componentText(both, 'name', english: true), 'Otzaria');
      expect(componentText(both, 'name', english: false), 'אוצריא');
      expect(
        componentText(const {'name': 'אוצריא'}, 'name', english: true),
        'אוצריא',
        reason: 'release ישן בלי nameEn',
      );
    });

    test('השדות באנגלית אינם משנים שום בחירה', () {
      final manifest = buildFixtureManifest();
      final stripped = jsonDecode(jsonEncode(manifest)) as Map<String, Object?>;
      for (final component
          in (stripped['components'] as List).cast<Map<String, Object?>>()) {
        component
          ..remove('nameEn')
          ..remove('descriptionEn')
          ..remove('outputNoteEn');
      }
      expect(jsonEncode(stripped), isNot(jsonEncode(manifest)));
      expect(
        encodeFixture(buildExpectedSelections(stripped)),
        encodeFixture(buildExpectedSelections(manifest)),
      );
    });
  });

  group('הבחירה האישית', () {
    final manifest = buildFixtureManifest();
    final large = buildLargeFullFixtureManifest();
    final components = (manifest['components'] as List)
        .cast<Map<String, Object?>>();
    String typeOf(String id) =>
        components.firstWhere((c) => c['id'] == id)['type'] as String;
    String describe(CustomChoice c) =>
        '${c.id}${c.locked ? ':locked' : ''}'
        '${c.group.isEmpty ? '' : ':${c.group}'}';

    test('גרסה ניידת אינה מוצגת בשום יעד', () {
      for (final target in [...kFixtureTargets, ...kLargeFullTargets]) {
        for (final m in [manifest, large]) {
          expect(
            customChoices(m, target).map((c) => typeOf(c.id)),
            isNot(contains('application-portable')),
            reason: '${target.toJson()}',
          );
        }
      }
    });

    test('Windows: מתקין נעול, ספרייה, אינדקס וחיפוש חכם — בלי FULL', () {
      for (final (target, installer) in [
        (kFixtureTargets[0], 'otzaria-windows-x64'),
        (kFixtureTargets[1], 'otzaria-windows-arm64'),
      ]) {
        for (final m in [manifest, large]) {
          expect(customChoices(m, target).map(describe), [
            '$installer:locked',
            'library-full',
            'library-index',
            'semantic-vectors-windows',
          ], reason: '${target.toJson()}');
        }
      }
    });

    test('Linux ו-macOS: המתקין והחבילה המלאה הם בחירה אחת', () {
      final expected = {
        3: ['otzaria-linux-deb-x64', 'otzaria-linux-full-x64'],
        4: ['otzaria-linux-rpm-x64', 'otzaria-linux-full-x64'],
        6: ['otzaria-linux-deb-arm64', 'otzaria-linux-full-arm64'],
        2: ['otzaria-macos', 'otzaria-macos-full'],
      };
      for (final MapEntry(key: index, value: ids) in expected.entries) {
        final choices = customChoices(manifest, kFixtureTargets[index]);
        expect(
          choices.where((c) => c.group.isNotEmpty).map((c) => c.id),
          ids,
          reason: '${kFixtureTargets[index].toJson()}',
        );
        expect(choices.any((c) => c.locked), isFalse);
        expect(
          choices.map((c) => typeOf(c.id)),
          isNot(anyOf(contains('library'), contains('library-index'))),
        );
      }
    });

    test('Linux בלי מנהל חבילות: החבילה המלאה לבדה, נעולה', () {
      expect(customChoices(manifest, kFixtureTargets[5]).map(describe), [
        'otzaria-linux-full-x64:locked',
        'semantic-vectors-linux',
      ]);
    });

    test('האינדקס גורר את הספרייה ואת המתקין', () {
      for (final target in kLargeFullTargets) {
        expect(withDependencies(manifest, ['library-index'], target), [
          target.architecture == 'x64'
              ? 'otzaria-windows-x64'
              : 'otzaria-windows-arm64',
          'library-full',
          'library-index',
        ]);
      }
    });

    test('"מלאה" לעולם אינה כוללת את האינדקס', () {
      for (final (m, targets) in [
        (manifest, kFixtureTargets),
        (large, kLargeFullTargets),
      ]) {
        for (final target in targets) {
          for (final preset in buildPresets(m, target)) {
            if (preset.id == 'full-indexed') continue;
            expect(
              preset.members,
              isNot(contains('library-index')),
              reason: '${target.toJson()} ${preset.id}',
            );
          }
        }
      }
    });

    test('FULL של 4 GiB: "מלאה" היא המתקין הרגיל והספרייה בלבד', () {
      for (final target in kLargeFullTargets) {
        final installer = target.architecture == 'x64'
            ? 'otzaria-windows-x64'
            : 'otzaria-windows-arm64';
        expect(
          buildPresets(large, target).firstWhere((p) => p.id == 'full').members,
          [
            installer,
            'library-full',
            'semantic-model-windows',
            'semantic-vectors-windows',
          ],
        );
      }
    });
  });

  test('שם תת-התיקייה נושא את שם הפלטפורמה', () {
    expect(outputSubfolderName('windows'), 'אוצריא להתקנה ל-Windows');
    expect(outputSubfolderName('linux'), 'אוצריא להתקנה ל-Linux');
    expect(plannedOutputSubfolder(const ['a'], 'linux'), '');
    expect(
      plannedOutputSubfolder(const ['a', 'b'], 'macos'),
      'אוצריא להתקנה ל-macOS',
    );
  });
}
