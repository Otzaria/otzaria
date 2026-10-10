import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/release/download_assistant_selection.dart';
import '../../tool/release/generate_release_manifest.dart';

/// ההצעות של מסייע ההורדה נגזרות מ-`type` ומ-`required` של הרכיבים. הכללים
/// מוגדרים ב-[buildPresets] (מימוש הייחוס), ו-`download_assistant.iss` חייב
/// לשקף אותם. כאן נבדק ששני הצדדים מסכימים, ושהכללים מופעלים על טבלת
/// [kKnownComponents] אינם מכניסים צורה חלופית של התוכנה להצעה ברירת מחדל.

const _assistant = 'installer/download_assistant.iss';

String _script() =>
    File(_assistant).readAsStringSync().replaceAll('\r\n', '\n');

String _routine(String script, String signature) {
  final start = script.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'לא נמצאה השגרה $signature');
  return script.substring(start, script.indexOf('\nend;', start));
}

/// מניפסט מינימלי מטבלת הרכיבים — רק השדות שכללי הבחירה קוראים.
Map<String, Object?> _manifest(List<ComponentSpec> specs) => {
  'components': [
    for (final spec in specs)
      {
        'id': spec.id,
        'type': spec.type,
        'required': spec.required,
        'platform': ?spec.platform,
        'architecture': ?spec.architecture,
        'packageFormat': ?spec.packageFormat,
        'dependsOn': spec.dependsOn,
        if (spec.installedBy.isNotEmpty) 'installedBy': spec.installedBy,
        'downloadSize': 1,
        'assets': const <Object>[],
      },
  ],
};

Map<String, List<String>> _presets(
  List<ComponentSpec> specs,
  AssistantTarget target,
) => {
  for (final preset in buildPresets(_manifest(specs), target))
    preset.id: preset.members,
};

const _windowsTargets = [
  AssistantTarget(platform: 'windows', architecture: 'x64'),
  AssistantTarget(platform: 'windows', architecture: 'arm64'),
];

const _portableIds = [
  'otzaria-windows-portable-x64',
  'otzaria-windows-portable-arm64',
];

ComponentSpec _spec(String id) =>
    kKnownComponents.firstWhere((s) => s.id == id);

void main() {
  group('הסקריפט משקף את מימוש הייחוס', () {
    test('BuildPresets: אותם סוגים, אותו סדר ואותו כלל חבילה', () {
      final body = _routine(_script(), 'procedure BuildPresets();');
      final bundle = _routine(_script(), 'function FullPresetBundle(');
      final indexed = _routine(_script(), 'function IndexedPresetBundle(');

      expect(body, contains('Bundle := FullPresetBundle();'));
      expect(body, contains('Bundle := IndexedPresetBundle();'));
      for (final routine in [bundle, indexed]) {
        expect(
          routine,
          contains("(CompType[I] = 'application-bundle')"),
          reason: 'החבילות הן מסוג application-bundle',
        );
        expect(routine, contains('ComponentIsOffered(I)'));
      }
      expect(
        bundle,
        contains('(CompDownloadSize[I] > CompDownloadSize[Result])'),
        reason: '"מלאה": החבילה הגדולה ביותר, כמו ב-buildPresets',
      );
      expect(
        indexed.replaceAll(RegExp(r'\s+'), ' '),
        allOf(
          contains('InstallsLibrary(I)'),
          contains(
            '(MembersSize(WithInstalled(I)) > MembersSize(WithInstalled(Result)))',
          ),
        ),
        reason:
            '"מלאה + אינדקס": מתקינה ספרייה, הגדולה ביותר עם מה שהיא מתקינה',
      );
      expect(
        _routine(_script(), 'function InstallsLibrary('),
        allOf(
          contains("(CompType[I] = 'library')"),
          contains('MembersContain(CompInstalledBy[I], CompId[Bundle])'),
          contains('ComponentIsOffered(I)'),
        ),
      );
      expect(
        _routine(_script(), 'function WithInstalled('),
        contains('MembersContain(CompInstalledBy[I], CompId[Bundle])'),
        reason: 'החבילה מגיעה עם מה שהיא מתקינה, כמו ב-buildPresets',
      );
      expect(
        body + bundle + indexed,
        isNot(contains('ComponentFitsTarget(')),
        reason: 'ההצעות בנויות רק ממה שמוצע ביעד (ComponentIsOffered)',
      );
      final calls = RegExp(
        r"CollectByTypes\('([^']*)',\s*(False|True)\)",
      ).allMatches(body).map((m) => '${m.group(1)}|${m.group(2)}').toList();
      expect(
        calls,
        [
          'library,|False',
          'application,library,dependency,|False',
          'library-index,|False',
          'application,library,dependency,|False',
          'library,|False',
          'application,|False',
          '|True',
          'application,|False',
        ],
        reason:
            'הרשימות חייבות להתאים ל-buildPresets — מלאה + אינדקס ב-Android, '
            'מלאה (ורק עם ספרייה), בסיסית, עדכון',
      );
      expect(
        body.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          "else if (TargetPlatform = 'android') and (FullPresetBundle() < 0)",
        ),
        reason: 'בלי חבילה, "מלאה + אינדקס" רק ב-Android',
      );
      // סדר ההוספה הוא סדר ההערכה של buildPresets: הוא קובע איזו כפולה מושמטת.
      final ids = RegExp(
        r"AddPreset\('([a-z-]+)'",
      ).allMatches(body).map((m) => m.group(1)).toList();
      expect(ids, ['full-indexed', 'full-indexed', 'full', 'basic', 'update']);

      // נתוני החיפוש החכם בשתי ההצעות המלאות, בכל הענפים.
      expect(
        body,
        contains('Offline := CollectByTypes(OfflineDataTypes, False);'),
      );
      expect('+ Offline'.allMatches(body), hasLength(4));
      final declared = RegExp(
        r"OfflineDataTypes = '([^']*)';",
      ).firstMatch(_script())!.group(1)!;
      expect(
        declared.split(',').where((t) => t.isNotEmpty).toSet(),
        kOfflineDataTypes,
      );
    });

    test('ההצעות נשמרות בסדר ההצגה של מימוש הייחוס', () {
      final declared = RegExp(
        r"PresetDisplayOrder = '([^']*)';",
      ).firstMatch(_script())!.group(1)!;
      expect(
        declared.split(',').where((t) => t.isNotEmpty).toList(),
        kPresetDisplayOrder,
      );
      expect(
        _routine(_script(), 'procedure AddPreset('),
        contains('DisplayRank(PresetId[I - 1]) > DisplayRank(Id)'),
        reason: 'כל הצעה נכנסת למקומה בסדר ההצגה, ו"בחירה אישית" אחריהן',
      );
      expect(
        _routine(_script(), 'procedure BuildPresets();'),
        contains('CustomPresetIndex := GetArrayLength(PresetLabel);'),
      );
    });

    test('שלושת המסייעים: אותם טקסטים ואותה הצעה מסומנת מראש', () {
      final presets = buildPresets(
        _manifest(kKnownComponents),
        _windowsTargets.first,
      );
      expect(presets.map((p) => p.id), containsAll(['full', 'basic']));
      final sources = {
        for (final path in const [
          _assistant,
          'tool/download_assistant/macos/Sources/AssistantCore/Selection.swift',
          'tool/download_assistant/linux/selection.c',
        ])
          // רווח קשיח במסייע אחד הוא תיקון תצוגה, לא נוסח אחר.
          path: File(path).readAsStringSync().replaceAll('\u00A0', ' '),
      };
      for (final MapEntry(key: path, value: source) in sources.entries) {
        for (final preset in presets) {
          expect(source, contains(preset.caption), reason: path);
          expect(source, contains(preset.description), reason: path);
        }
      }
      // בלי "בסיסית" — "מלאה", כמו defaultPresetIdFor; בלי שתיהן — הראשונה.
      final refresh = _routine(_script(), 'procedure RefreshPresetPage(');
      expect(
        refresh,
        contains("I := ListIndex(PresetId, '$kDefaultPresetId');"),
      );
      expect(refresh, contains("I := DefaultIndex(PresetId, 'full');"));
      expect(
        sources.values.elementAt(1),
        contains('defaultPresetId = "$kDefaultPresetId"'),
      );
      expect(
        File('tool/download_assistant/linux/selection.h').readAsStringSync(),
        contains('OTZ_DEFAULT_PRESET_ID "$kDefaultPresetId"'),
      );
    });

    test('ComponentFitsTarget בודק את שלושת השדות', () {
      final fits = _routine(_script(), 'function ComponentFitsTarget(');
      for (final pair in const [
        ('CompPlatform', 'TargetPlatform'),
        ('CompArch', 'TargetArchitecture'),
        ('CompFormat', 'TargetFormat'),
      ]) {
        expect(fits, contains('not IsWildcard(${pair.$1}[Index])'));
        expect(fits, contains('(${pair.$1}[Index] <> ${pair.$2})'));
      }
      expect(
        _routine(_script(), 'function IsWildcard('),
        contains("(Value = '') or (Value = 'any')"),
      );
    });

    test('רכיב מוצע: מתאים, ניתן להרצה, ויש מי שמתקין אותו', () {
      final offered = _routine(_script(), 'function ComponentIsOffered(');
      expect(offered, contains('ComponentFitsTarget(Index)'));
      expect(offered, contains('ComponentIsRunnable(Index)'));
      expect(offered, contains('InstallerFor(Index) >= 0'));
      expect(
        _routine(_script(), 'function ComponentIsRunnable('),
        contains('(AssetSize[A] >= MaxSingleOutputFileSize)'),
      );
      expect(
        _routine(_script(), 'function CollectByTypes('),
        contains('ComponentIsOffered(I)'),
      );
      expect(
        _routine(_script(), 'function IsCustomChoice('),
        contains('ComponentIsOffered(Index)'),
      );
    });

    test('בבחירה האישית חלק (partOf) הוא חלק מהשורה של השלם (issue #1869)', () {
      expect(
        _routine(_script(), 'function IsCustomChoice('),
        contains("(CompPartOf[Index] = '')"),
      );
      expect(
        _routine(_script(), 'function CustomChoiceSize('),
        contains('(CompPartOf[J] = CompId[Index]) and ComponentIsOffered(J)'),
      );
      final page = _routine(_script(), 'procedure RefreshCustomPage();');
      expect(page, contains('if not IsCustomChoice(I, TakesLibrary) then'));
      expect(page, contains('HumanSize(CustomChoiceSize(I))'));
      final ui = File(
        'installer/download_assistant_ui.iss',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        _routine(ui, 'procedure UiBuildCards('),
        contains('Card.Side := HumanSize(CustomChoiceSize(C));'),
        reason: 'הכרטיסים מציגים את גודל השורה, לא של השלם לבדו',
      );
    });

    test('הבחירה האישית: אותן שורות, נעילה ורדיו כמו customChoices', () {
      final choice = _routine(_script(), 'function IsCustomChoice(');
      expect(choice, contains("(CompType[Index] <> 'application-portable')"));
      expect(
        choice,
        contains(
          "not (TakesLibrary and (CompType[Index] = 'application-bundle'))",
        ),
      );
      expect(
        _routine(_script(), 'function InstallerTakesLibrary('),
        contains("(CompType[Idx] = 'application')"),
      );
      expect(
        _routine(_script(), 'function CustomInstallersAreRadio('),
        contains('Result := N > 1;'),
      );
      final page = _routine(_script(), 'procedure RefreshCustomPage();');
      expect(page, contains('IsCustomChoice(I, TakesLibrary)'));
      expect(page, contains('CheckListBox.AddRadioButton('));
      expect(page, contains('Locked, not Locked, False, False, nil)'));
      expect(
        _routine(_script(), 'procedure CustomChoiceClicked('),
        contains('MembersContain(CompDependsOn[CustomIndex[Row]]'),
      );
      expect(kApplicationChoiceGroup, 'application');
    });

    test('בחירה אישית נסגרת כמו ההצעות', () {
      final next = _routine(_script(), 'function NextButtonClick(');
      expect(next, contains('Members := WithDependencies(Members);'));
    });

    test('סגירת התלויות: dependsOn שמוצע, והמתקין של מה שנבחר', () {
      final closure = _routine(_script(), 'function WithDependencies(');
      expect(closure, contains('ComponentIsOffered(Idx)'));
      expect(closure, contains('Idx := InstallerFor(I);'));
      expect(
        _routine(_script(), 'function CanonicalMembers('),
        contains('MembersContain(Members, CompId[I])'),
        reason: 'סדר המניפסט, כמו withDependencies',
      );
    });
  });

  group('הגרסה הניידת אינה רכיב נוסף של אותה התקנה', () {
    test('הסוג שלה נפרד מסוג המתקין', () {
      final installer = _spec('otzaria-windows-x64').type;
      for (final id in _portableIds) {
        expect(
          _spec(id).type,
          isNot(installer),
          reason: 'סוג משותף עם המתקין מחזיר את צירוף שתי הצורות להצעה',
        );
      }
      expect(
        _portableIds.map((id) => _spec(id).type).toSet(),
        {'application-portable'},
        reason: 'שתי הגרסאות הניידות חולקות סוג אחד',
      );
      expect(
        _spec('otzaria-windows-portable-arm64').architecture,
        'arm64',
        reason: 'הניידת של ARM אינה מוצעת למחשב x64',
      );
    });

    test('אינה נכנסת לאף הצעה שאינה "בחירה אישית"', () {
      for (final target in _windowsTargets) {
        _presets(kKnownComponents, target).forEach((name, members) {
          for (final id in _portableIds) {
            expect(
              members,
              isNot(contains(id)),
              reason:
                  'ההצעה "$name" ביעד ${target.architecture} מורידה גם את הגרסה הניידת',
            );
          }
        });
      }
    });
  });

  group('כל הצעה נשארת בעלת תוכן', () {
    test('"מלאה" היא המתקין המלא של אותה ארכיטקטורה', () {
      final x64 = _presets(kKnownComponents, _windowsTargets[0]);
      final arm64 = _presets(kKnownComponents, _windowsTargets[1]);

      expect(x64['full'], hasLength(1));
      expect(x64['basic'], contains('otzaria-windows-x64'));
      expect(arm64['full'], ['otzaria-windows-full-arm64']);
      expect(arm64['basic'], contains('otzaria-windows-arm64'));
    });

    test('בלי מתקין מלא ל-ARM64 — "מלאה" היא המתקין הרגיל עם הספרייה', () {
      final arm64 = _presets(
        kKnownComponents
            .where((s) => s.id != 'otzaria-windows-full-arm64')
            .toList(),
        _windowsTargets[1],
      );
      expect(arm64['full'], ['otzaria-windows-arm64', 'library-full']);
      expect(arm64['basic'], ['otzaria-windows-arm64']);
    });

    test('"בסיסית" ו"עדכון" מתלכדות כשאין רכיב required נוסף', () {
      final presets = _presets(kKnownComponents, _windowsTargets[0]);
      expect(
        presets.keys,
        isNot(contains('update')),
        reason: 'איחוד ההצעות הזהות הוא מה שמשאיר שתי שורות בלבד במסך',
      );
    });

    test('כל פלטפורמה ביעד מקבלת לפחות הצעה אחת', () {
      final manifest = _manifest(kKnownComponents);
      for (final platform in platformChoices(manifest)) {
        final archs = architectureChoices(manifest, platform);
        for (final arch in archs.isEmpty ? [''] : archs) {
          final formats = packageFormatChoices(manifest, platform, arch);
          for (final format in formats.isEmpty ? [''] : formats) {
            final target = AssistantTarget(
              platform: platform,
              architecture: arch,
              packageFormat: format,
            );
            expect(
              buildPresets(manifest, target),
              isNotEmpty,
              reason: '$platform/$arch/$format',
            );
          }
        }
      }
    });
  });

  group('"מלאה + אינדקס חיפוש" במניפסט ישן', () {
    const legacyIndexed = [
      ComponentSpec(
        id: 'otzaria-windows-full-indexed',
        name: 'מתקין',
        description: 'מתקין.',
        type: 'application-bundle',
        required: false,
        platform: 'windows',
        architecture: 'x64',
        installOrder: 1,
        assets: [],
      ),
      ComponentSpec(
        id: 'library-full-indexed',
        name: 'ספרייה',
        description: 'ספרייה.',
        type: 'library',
        required: false,
        platform: 'any',
        installOrder: 30,
        installedBy: ['otzaria-windows-full-indexed'],
        assets: [],
      ),
    ];
    const model = ComponentSpec(
      id: 'semantic-model-windows',
      name: 'מודל',
      description: 'מודל.',
      type: 'semantic-model',
      required: false,
      installOrder: 90,
      platform: 'windows',
      assets: [AssetSpec(pattern: r'^model\.bin$')],
    );
    const vectors = ComponentSpec(
      id: 'semantic-vectors-windows',
      name: 'נתונים',
      description: 'נתונים.',
      type: 'semantic-vectors',
      required: false,
      installOrder: 91,
      platform: 'windows',
      dependsOn: ['semantic-model-windows'],
      assets: [AssetSpec(pattern: r'^vectors\.bin$')],
    );

    test('ב-x64: החבילה המאונדקסת עם הספרייה שלה, מעל "מלאה"', () {
      final x64 = _presets([
        ...kKnownComponents,
        ...legacyIndexed,
      ], _windowsTargets[0]);
      expect(x64.keys, ['basic', 'full-indexed', 'full']);
      expect(x64['full-indexed'], [
        'otzaria-windows-full-indexed',
        'library-full-indexed',
      ]);
      expect(x64['full'], isNot(contains('library-full-indexed')));
    });

    test('נתוני החיפוש החכם בשתי ההצעות המלאות בלבד', () {
      final x64 = _presets([
        ...kKnownComponents,
        ...legacyIndexed,
        model,
        vectors,
      ], _windowsTargets[0]);
      for (final id in const ['full-indexed', 'full']) {
        expect(
          x64[id],
          containsAll(['semantic-model-windows', 'semantic-vectors-windows']),
          reason: id,
        );
      }
      expect(x64['basic'], isNot(contains('semantic-model-windows')));
    });

    test('בלי ספרייה מאונדקסת ליעד (ARM64) אין "מלאה + אינדקס"', () {
      expect(
        _presets([
          ...kKnownComponents,
          ...legacyIndexed,
        ], _windowsTargets[1]).keys,
        isNot(contains('full-indexed')),
      );
    });
  });

  group('רכיב עתידי נוחת במקום סביר בלי שינוי קוד', () {
    const futureRequired = ComponentSpec(
      id: 'future-required',
      name: 'רכיב חדש נדרש',
      description: 'סוג שהסקריפט אינו מכיר.',
      type: 'runtime-blob',
      required: true,
      installOrder: 15,
      platform: 'windows',
      assets: [AssetSpec(pattern: r'^future\.bin$')],
    );
    const futureOptional = ComponentSpec(
      id: 'future-optional',
      name: 'רכיב חדש רשות',
      description: 'סוג שהסקריפט אינו מכיר.',
      type: 'runtime-blob',
      required: false,
      installOrder: 15,
      platform: 'windows',
      assets: [AssetSpec(pattern: r'^future-opt\.bin$')],
    );

    test('סוג לא מוכר עם required נכנס ל"בסיסית"', () {
      final presets = _presets([
        ...kKnownComponents,
        futureRequired,
      ], _windowsTargets[0]);
      expect(presets['basic'], contains('future-required'));
    });

    test('סוג לא מוכר ברשות נשאר ל"בחירה אישית" בלבד', () {
      final presets = _presets([
        ...kKnownComponents,
        futureOptional,
      ], _windowsTargets[0]);
      presets.forEach((name, members) {
        expect(members, isNot(contains('future-optional')), reason: name);
      });
    });
  });
}
