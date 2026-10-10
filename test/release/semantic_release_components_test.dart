import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/settings/l10n/settings_catalogs.g.dart';

import '../../tool/download_assistant/fixtures/generate_fixtures.dart';
import '../../tool/release/download_assistant_selection.dart';
import '../../tool/release/generate_release_manifest.dart';
import '../../tool/release/semantic_release_components.dart';

const _api = 'https://api.github.test/repos';
const _tag = 'v30-20260930165019';
const _vectorsTag = 'vectors-$_tag';
const _segment = 'otzaria-vectors-0c3f95be-v30-base.oxv.zst';
const _manifestName = 'otzaria-vectors-0c3f95be-v30-base.manifest.json';

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

String _identityJson() =>
    File('assets/semantic/meivin-round2-onnx/model.json').readAsStringSync();

String _vectorsManifest({String? familyId}) {
  final identity = SemanticModelIdentity.parse(_identityJson());
  return jsonEncode({
    'kind': 'base',
    'identity': {
      'model': {
        'family_id': familyId ?? identity.familyId,
        'tokenizer_checksum': identity.tokenizerChecksum,
      },
    },
    'fromLibraryVersion': 0,
    'toLibraryVersion': 30,
    'libraryReleaseTag': _tag,
    'segment': {'sha256': 'cd' * 32, 'size': 1779752972},
    'files': [
      {'file': _segment, 'sha256': 'ab' * 32, 'size': 1642517351},
    ],
  });
}

final SemanticModelRelease _model =
    kSemanticModelReleases[SemanticQuantization.int8]!;

class _GitHub {
  bool vectorsPublished = true;
  String manifest = _vectorsManifest();
  int graphSize = _model.graph.size;

  static http.Response _json(Object? body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), 200);

  http.Client client() => MockClient((request) async {
    final url = request.url.toString();
    if (url == '$_api/Otzaria/SeforimLibrary/releases/tags/$_vectorsTag') {
      if (!vectorsPublished) return http.Response('{}', 404);
      return _json({
        'tag_name': _vectorsTag,
        'body': 'Manifest: `$_manifestName`, SHA-256 `${_sha(manifest)}`.',
        'assets': [
          {
            'name': _manifestName,
            'size': utf8.encode(manifest).length,
            'digest': 'sha256:${_sha(manifest)}',
            'browser_download_url': 'https://dl.test/$_manifestName',
          },
          {
            'name': _segment,
            'size': 1642517351,
            'digest': 'sha256:${'ab' * 32}',
            'browser_download_url': 'https://dl.test/$_segment',
          },
        ],
      });
    }
    if (url == 'https://dl.test/$_manifestName') {
      return http.Response.bytes(utf8.encode(manifest), 200);
    }
    if (url ==
        '$_api/Otzaria/otzaria-semantic-search/releases/tags/'
            'model-meivin-round2-int8-v1') {
      return _json({
        'assets': [
          for (final file in [
            _model.graph,
            _model.tokenizer.zipped!,
            _model.identity,
            _model.license,
          ])
            {
              'name': file.name,
              'size': file == _model.graph ? graphSize : file.size,
              'digest': 'sha256:${file.sha256}',
            },
        ],
      });
    }
    return http.Response('not found', 404);
  });

  Future<List<Map<String, Object?>>> resolve() => resolveSemanticComponents(
    libraryTag: _tag,
    modelIdentityJson: _identityJson(),
    clientFactory: client,
    apiBase: _api,
  );
}

void main() {
  group('רכיבי החיפוש הסמנטי ב-CI', () {
    test('מודל ווקטורים לכל פלטפורמה נתמכת, עם כתובות חיצוניות', () async {
      final components = await _GitHub().resolve();

      expect(components.map((c) => c['id']), [
        for (final platform in kSemanticComponentPlatforms) ...[
          'semantic-model-$platform',
          'semantic-vectors-$platform',
        ],
      ]);
      final model = components.first;
      expect(model['type'], kSemanticModelComponentType);
      expect(model['origin'], 'imported');
      expect(model['required'], isFalse);
      expect(model['outputFolder'], 'semantic-import/meivin-round2-onnx');
      expect(
        (model['assets'] as List).map((a) => (a as Map)['repository']).toSet(),
        {'Otzaria/otzaria-semantic-search'},
      );
      expect(
        (model['assets'] as List).first,
        containsPair('releaseTag', 'model-meivin-round2-int8-v1'),
      );
      // tokenizer.json נחסם במסנני תוכן; האפליקציה פורסת את ה-zip המוכן.
      expect((model['assets'] as List).map((a) => (a as Map)['name']), [
        _model.graph.name,
        'tokenizer.json.zip',
        _model.identity.name,
        _model.license.name,
      ]);

      final vectors = components[1];
      expect(vectors['type'], kSemanticVectorsComponentType);
      expect(vectors['dependsOn'], ['semantic-model-windows']);
      expect(vectors['outputFolder'], 'semantic-import/vectors');
      expect(vectors['compatibility'], {
        'libraryReleaseTag': _tag,
        'libraryVersion': 30,
        'modelFamilyId': SemanticModelIdentity.parse(_identityJson()).familyId,
        'vectorsManifestSha256': _sha(_vectorsManifest()),
      });
      final assets = (vectors['assets'] as List).cast<Map>();
      expect(assets.map((a) => a['name']), [_segment, _manifestName]);
      expect(assets.map((a) => a['repository']).toSet(), {
        'Otzaria/SeforimLibrary',
      });
      expect(assets.map((a) => a['releaseTag']).toSet(), {_vectorsTag});
      expect(assets.last['sha256'], _sha(_vectorsManifest()));
    });

    test('שם, תיאור והסבר באנגלית לכל רכיב', () async {
      final hebrew = RegExp(r'[֐-׿]');
      for (final component in await _GitHub().resolve()) {
        final id = component['id'];
        for (final key in const ['nameEn', 'descriptionEn', 'outputNoteEn']) {
          expect(component[key], isA<String>(), reason: '$id $key');
          expect(component[key], isNot(contains(hebrew)), reason: '$id $key');
          expect(component[key], contains('Smart Search'), reason: '$id $key');
        }
        expect(
          (component['descriptionEn'] as String).contains('Apple Silicon'),
          component['platform'] == 'macos',
          reason: '$id',
        );
      }
    });

    // אותו שם שהמשתמש רואה באפליקציה באנגלית.
    test('שם המצב באנגלית הוא התרגום שבאפליקציה', () {
      expect(
        kSettingsCatalogs['en']![kSemanticSearchModeName],
        kSemanticSearchModeNameEn,
      );
    });

    test('הרכיבים עוברים את אימות המניפסט כ---external', () async {
      final dir = Directory.systemTemp.createTempSync('semantic-manifest');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/otzaria-0.10.3-windows.exe').writeAsStringSync('x');

      final manifest = buildReleaseManifest(
        releaseTag: '0.10.3+1',
        releaseVersion: '0.10.3',
        directory: dir,
        externalComponents: await _GitHub().resolve(),
      );

      final ids = (manifest['components'] as List).map((c) => (c as Map)['id']);
      expect(ids.first, 'otzaria-windows-x64');
      expect(ids, contains('semantic-vectors-linux'));

      // חלק שהשלם אינו תלוי בו לא היה מגיע לעולם — האימות דוחה אותו.
      final vectors = (manifest['components'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((c) => c['id'] == 'semantic-vectors-linux');
      vectors['dependsOn'] = const <String>[];
      expect(
        validateReleaseManifest(manifest),
        contains(
          'component semantic-model-linux: partOf must name a component '
          'that dependsOn it',
        ),
      );
    });

    test('אין release וקטורים לתג הספרייה — הרכיבים מושמטים', () async {
      final github = _GitHub()..vectorsPublished = false;

      await expectLater(
        github.resolve(),
        throwsA(
          isA<SemanticComponentsOmitted>().having(
            (e) => e.reason,
            'reason',
            contains('vectors-$_tag'),
          ),
        ),
      );
    });

    test('וקטורים של מודל אחר — מושמטים', () async {
      final github = _GitHub()
        ..manifest = _vectorsManifest(familyId: 'other/model@1');

      await expectLater(
        github.resolve(),
        throwsA(isA<SemanticComponentsOmitted>()),
      );
    });

    test('נכס מודל שאינו תואם לנעוץ באפליקציה — מושמטים', () async {
      final github = _GitHub()..graphSize = 1;

      await expectLater(
        github.resolve(),
        throwsA(isA<SemanticComponentsOmitted>()),
      );
    });

    test('ה-workflow מעביר את הרכיבים ואינו נכשל בלעדיהם', () {
      final workflow = File(
        '.github/workflows/build-and-announce.yml',
      ).readAsStringSync().replaceAll('\r\n', '\n');
      final step = workflow.indexOf(
        '- name: Resolve semantic search components',
      );
      final generate = workflow.indexOf('- name: Generate release manifest');
      expect(step, greaterThan(0));
      expect(generate, greaterThan(step));
      final body = workflow.substring(step, generate);
      expect(body, contains('continue-on-error: true'));
      expect(body, contains('needs.bump_version.outputs.library_tag'));
      expect(body, contains('tool/release/semantic_release_components.dart'));
      expect(
        workflow.substring(generate, generate + 1200),
        contains('--external'),
      );
    });
  });

  group('outputFolder במניפסט', () {
    Map<String, Object?> withFolder(Object? folder) => {
      'schemaVersion': 1,
      'releaseTag': 't',
      'releaseVersion': 'v',
      'components': [
        {
          'id': 'c',
          'name': 'n',
          'description': 'd',
          'type': 'semantic-model',
          'required': false,
          'origin': 'imported',
          'installOrder': 1,
          'dependsOn': const <String>[],
          'downloadSize': 1,
          'outputFolder': folder,
          'assets': [
            {
              'kind': 'single',
              'repository': 'Otzaria/x',
              'releaseTag': 't',
              'name': 'a',
              'size': 1,
              'sha256': 'ab' * 32,
            },
          ],
        },
      ],
    };

    test('תיקייה יחסית של שמות בטוחים בלבד', () {
      expect(
        validateReleaseManifest(withFolder('semantic-import/vectors')),
        isEmpty,
      );
      for (final bad in ['../x', '/abs', 'a//b', 'a/..', r'a\b', '', 'א']) {
        expect(
          validateReleaseManifest(withFolder(bad)),
          isNotEmpty,
          reason: bad,
        );
      }
    });
  });

  group('הבחירה במסייעים', () {
    final manifest = buildFixtureManifest();

    test(
      '"מלאה" ו"מלאה + אינדקס" כוללות את נתוני החיפוש החכם, "בסיסית" לא',
      () {
        for (final target in kFixtureTargets) {
          final presets = {
            for (final preset in buildPresets(manifest, target))
              preset.id: preset.members,
          };
          final semantic = [
            'semantic-model-${target.platform}',
            'semantic-vectors-${target.platform}',
          ];
          if (target.platform == 'android') {
            expect(
              presets.values.expand((m) => m),
              isNot(contains(semantic.first)),
            );
            continue;
          }
          expect(presets['full'], containsAll(semantic), reason: '$target');
          if (presets.containsKey('full-indexed')) {
            expect(presets['full-indexed'], containsAll(semantic));
          }
          expect(presets['basic'] ?? const [], isNot(contains(semantic.first)));
        }
      },
    );

    test('קובצי הנתונים נכתבים בתיקייה שהאפליקציה מזהה', () {
      const target = AssistantTarget(platform: 'windows', architecture: 'x64');
      final files = plannedOutputFiles(manifest, const [
        'semantic-model-windows',
        'semantic-vectors-windows',
      ], target);
      expect(files, [
        'semantic-import/meivin-round2-onnx/seforim-embed-round2-int8.onnx',
        'semantic-import/meivin-round2-onnx/tokenizer.json',
        'semantic-import/meivin-round2-onnx/model.json',
        'semantic-import/meivin-round2-onnx/LICENSE',
        'semantic-import/vectors/$_segment',
        'semantic-import/vectors/$_manifestName',
      ]);
      // ב-Windows המתקין המלא מעתיק בעצמו; בשאר היעדים — העתקה ידנית.
      expect(plannedOutputNotes(manifest, const ['semantic-vectors-windows']), [
        kSemanticWindowsOutputNote,
      ]);
      expect(plannedOutputNotes(manifest, const ['semantic-vectors-linux']), [
        kSemanticOutputNote,
      ]);
    });

    test('ההסבר בעמוד הסיום באנגלית, ובלעדיו — בעברית', () {
      expect(
        plannedOutputNotes(manifest, const [
          'semantic-model-windows',
          'semantic-vectors-windows',
        ], english: true),
        [kSemanticWindowsOutputNoteEn],
      );
      expect(
        plannedOutputNotes(manifest, const [
          'semantic-vectors-linux',
        ], english: true),
        [kSemanticOutputNoteEn],
      );

      final old = jsonDecode(jsonEncode(manifest)) as Map<String, Object?>;
      for (final component in (old['components'] as List).cast<Map>()) {
        component.remove('outputNoteEn');
      }
      expect(
        plannedOutputNotes(old, const [
          'semantic-vectors-linux',
        ], english: true),
        [kSemanticOutputNote],
      );
    });

    test('וקטורים שנבחרו לבדם מגיעים עם המודל', () {
      const target = AssistantTarget(platform: 'linux', architecture: 'x64');
      expect(
        withDependencies(manifest, const ['semantic-vectors-linux'], target),
        [
          'semantic-model-linux',
          'semantic-vectors-linux',
        ],
      );
    });
  });
}
