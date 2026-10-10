// ignore_for_file: avoid_print
//
// רכיבי החיפוש הסמנטי למניפסט ה-release (`--external` של
// generate_release_manifest.dart): מודל השאילתות הנעוץ באפליקציה, והוקטורים
// של תג הספרייה שה-release אורז.
//
//   dart run tool/release/semantic_release_components.dart \
//     --library-tag v30-20260930165019 --out semantic-components.json
//
// כל כשל (אין release וקטורים לתג, רשת, נכס שאינו תואם) כותב רשימה ריקה,
// מדפיס ::warning:: ויוצא ב-0 — רכיב רשות לעולם אינו מפיל שחרור.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_import_layout.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/repository/semantic_release_locator.dart';

/// הפלטפורמות שיש בהן חיפוש סמנטי (`isSemanticSearchPlatformSupported`).
/// לכל אחת זוג רכיבים משלה, כי שדה הפלטפורמה במניפסט מקבל ערך אחד.
const List<String> kSemanticComponentPlatforms = ['windows', 'linux', 'macos'];

const String kSemanticModelComponentType = 'semantic-model';
const String kSemanticVectorsComponentType = 'semantic-vectors';

/// אחרי הספרייה (30) — הנתונים נקראים מתוך התוכנה המותקנת.
const int kSemanticModelInstallOrder = 40;
const int kSemanticVectorsInstallOrder = 41;

const String kSemanticModelBundledIdentity =
    'assets/semantic/meivin-round2-onnx/model.json';

/// התיקיות היחסיות בתיקיית הפלט, לפי `semantic_import_layout.dart`.
const String kSemanticModelOutputFolder =
    '$kSemanticImportFolderName/$kSemanticModelFolderName';
const String kSemanticVectorsOutputFolder =
    '$kSemanticImportFolderName/$kSemanticImportVectorsFolderName';

/// ההסבר בעמוד הסיום של המסייעים, כשההעתקה ידנית.
const String kSemanticOutputNote =
    'במחשב היעד העתק את התיקייה $kSemanticImportFolderName אל התיקייה שמכילה '
    'את תיקיית הספרייה של אוצריא. כשתפעיל שם את מצב "$kSemanticSearchModeName" '
    '(אחרי ההסכמה), הנתונים יותקנו ממנה בלי הורדה.';

/// ב-Windows מתקיני אוצריא מעתיקים את התיקייה בעצמם (otzaria.iss, otzaria_full.iss).
const String kSemanticWindowsOutputNote =
    'מתקין אוצריא שבתיקייה הזאת (הרגיל או המלא) מעתיק בעצמו את התיקייה '
    '$kSemanticImportFolderName אל ליד תיקיית הספרייה. כשתפעיל את מצב '
    '"$kSemanticSearchModeName" (אחרי ההסכמה), הנתונים יותקנו ממנה בלי הורדה. '
    'בהתקנה מקובץ ה-ZIP הנייד — העתק אותה ידנית אל התיקייה שמכילה את תיקיית '
    'הספרייה של אוצריא.';

/// ההסבר לעמוד הסיום של יעד [platform].
String semanticOutputNote(String platform) =>
    platform == 'windows' ? kSemanticWindowsOutputNote : kSemanticOutputNote;

/// שם המצב באנגלית — התרגום של [kSemanticSearchModeName] באפליקציה.
const String kSemanticSearchModeNameEn = 'Smart Search';

/// התרגום של [kSemanticSearchModeLabel] באפליקציה (settings_en.arb).
const String kSemanticSearchModeLabelEn = 'Smart Search (Experimental)';

const String kSemanticOutputNoteEn =
    'On the target computer, copy the $kSemanticImportFolderName folder into '
    'the folder that contains the Otzaria library folder. When you turn on '
    '$kSemanticSearchModeNameEn there (after giving consent), the data will be '
    'installed from it without downloading.';

const String kSemanticWindowsOutputNoteEn =
    'The regular or full Otzaria installer in this folder copies the '
    '$kSemanticImportFolderName folder next to the library folder by itself. '
    'When you turn on $kSemanticSearchModeNameEn (after giving consent), the '
    'data will be installed from it without downloading. If you install '
    'using a portable ZIP, copy the folder yourself into the folder '
    'that contains the Otzaria library folder.';

String semanticOutputNoteEn(String platform) => platform == 'windows'
    ? kSemanticWindowsOutputNoteEn
    : kSemanticOutputNoteEn;

final RegExp _modelBaseUrl = RegExp(
  r'^https://github\.com/(Otzaria/[A-Za-z0-9._-]+)/releases/download/'
  r'([A-Za-z0-9._+-]+)$',
);

/// רכיב שאינו נכלל, עם הסיבה ללוג ה-CI.
class SemanticComponentsOmitted implements Exception {
  SemanticComponentsOmitted(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// קובצי המודל שהמסייעים מורידים: ה-zip של קובץ במקומו, כשיש — מסנני תוכן חוסמים
/// את tokenizer.json, והאפליקציה פורסת zip מוכן כמו בהורדה (`_fetchModelFile`).
List<SemanticModelFile> _offlineModelFiles(SemanticModelRelease model) => [
  for (final file in [
    model.graph,
    model.tokenizer,
    model.identity,
    model.license,
  ])
    file.zipped ?? file,
];

/// בונה את הרכיבים מנתונים שכבר אומתו — בלי רשת.
List<Map<String, Object?>> buildSemanticComponents({
  required SemanticModelRelease model,
  required String modelFamilyId,
  required SemanticVectorsRelease vectors,
  required String vectorsManifestName,
  List<String> platforms = kSemanticComponentPlatforms,
}) {
  final source = _modelBaseUrl.firstMatch(model.baseUrl);
  if (source == null) {
    throw SemanticComponentsOmitted(
      'the model release ${model.baseUrl} is not an Otzaria GitHub release',
    );
  }
  final modelRepository = source.group(1)!;
  final modelTag = source.group(2)!;
  final manifestBytes = utf8.encode(vectors.manifestJson);
  final manifestSha = vectors.publishedManifestSha256;
  if (manifestSha == null) {
    throw SemanticComponentsOmitted('vectors manifest has no published digest');
  }

  Map<String, Object?> asset(
    String repository,
    String tag,
    String name,
    int size,
    String sha256,
  ) => {
    'kind': 'single',
    'repository': repository,
    'releaseTag': tag,
    'name': name,
    'size': size,
    'sha256': sha256,
  };

  final modelAssets = [
    for (final file in _offlineModelFiles(model))
      asset(modelRepository, modelTag, file.name, file.size, file.sha256),
  ];
  final vectorsAssets = [
    for (final file in vectors.files)
      asset(
        kSemanticVectorsRepository,
        vectors.releaseTag,
        file.name,
        file.size,
        file.sha256,
      ),
    asset(
      kSemanticVectorsRepository,
      vectors.releaseTag,
      vectorsManifestName,
      manifestBytes.length,
      manifestSha,
    ),
  ];
  int total(List<Map<String, Object?>> assets) =>
      assets.fold(0, (sum, a) => sum + (a['size'] as int));

  const macNote = ' ב-macOS: רק במחשב עם מעבד Apple Silicon ו-macOS 14 ומעלה.';
  const macNoteEn =
      ' On macOS: only on a Mac with an Apple Silicon processor and macOS 14 '
      'or later.';
  return [
    for (final platform in platforms) ...[
      {
        'id': 'semantic-model-$platform',
        'name': '$kSemanticSearchModeName — מודל השאילתות',
        'nameEn': '$kSemanticSearchModeNameEn — Query Model',
        'description':
            'הרכיב שמבין את מילות החיפוש במצב "$kSemanticSearchModeName".'
            '${platform == 'macos' ? macNote : ''}',
        'descriptionEn':
            'The component that understands your search words in '
            '$kSemanticSearchModeNameEn.'
            '${platform == 'macos' ? macNoteEn : ''}',
        'type': kSemanticModelComponentType,
        'required': false,
        'origin': 'imported',
        'platform': platform,
        'installOrder': kSemanticModelInstallOrder,
        'dependsOn': const <String>[],
        // בלי הנתונים המודל אינו שמיש, ולכן הוא שורה אחת איתם בבחירה האישית.
        'partOf': 'semantic-vectors-$platform',
        'downloadSize': total(modelAssets),
        'outputFolder': kSemanticModelOutputFolder,
        'outputNote': semanticOutputNote(platform),
        'outputNoteEn': semanticOutputNoteEn(platform),
        'compatibility': {'modelFamilyId': modelFamilyId},
        'assets': modelAssets,
      },
      {
        'id': 'semantic-vectors-$platform',
        'name': kSemanticSearchModeLabel,
        'nameEn': kSemanticSearchModeLabelEn,
        'description':
            'מה שמצב "$kSemanticSearchModeName" צריך כדי לעבוד בלי אינטרנט: '
            'המודל שמבין את מילות החיפוש, והנתונים לגרסת הספרייה '
            '${vectors.toLibraryVersion}, זו שבהתקנה המלאה.'
            '${platform == 'macos' ? macNote : ''}',
        'descriptionEn':
            'What $kSemanticSearchModeNameEn needs to work without internet: '
            'the model that understands your search words, and the data for '
            'library version ${vectors.toLibraryVersion}, the one included in '
            'the full installation.'
            '${platform == 'macos' ? macNoteEn : ''}',
        'type': kSemanticVectorsComponentType,
        'required': false,
        'origin': 'imported',
        'platform': platform,
        'installOrder': kSemanticVectorsInstallOrder,
        'dependsOn': ['semantic-model-$platform'],
        'downloadSize': total(vectorsAssets),
        'outputFolder': kSemanticVectorsOutputFolder,
        'outputNote': semanticOutputNote(platform),
        'outputNoteEn': semanticOutputNoteEn(platform),
        'compatibility': {
          'libraryReleaseTag': vectors.libraryTag,
          'libraryVersion': vectors.toLibraryVersion,
          'modelFamilyId': modelFamilyId,
          'vectorsManifestSha256': manifestSha,
        },
        'assets': vectorsAssets,
      },
    ],
  ];
}

/// מאתר ומאמת ברשת את המודל ואת הוקטורים של [libraryTag], ובונה את הרכיבים.
///
/// זורק [SemanticComponentsOmitted] כשאין מה לכלול; כל כשל אחר נזרק כמות שהוא.
Future<List<Map<String, Object?>>> resolveSemanticComponents({
  required String libraryTag,
  required String modelIdentityJson,
  required http.Client Function() clientFactory,
  SemanticModelRelease? model,
  String apiBase = 'https://api.github.com/repos',
}) async {
  final release = model ?? kSemanticModelReleases[SemanticQuantization.int8];
  if (release == null) {
    throw SemanticComponentsOmitted('the app pins no int8 model release');
  }
  final version = SemanticVectorsReleaseLocator.versionOfTag(libraryTag);
  if (version == null) {
    throw SemanticComponentsOmitted('library tag $libraryTag has no version');
  }
  final vectors = await SemanticVectorsReleaseLocator(
    clientFactory: clientFactory,
    apiBase: '$apiBase/$kSemanticVectorsRepository',
  ).findForLibraryVersion(version, libraryTag: libraryTag);
  if (vectors == null) {
    throw SemanticComponentsOmitted(
      '$kSemanticVectorsRepository has no release vectors-$libraryTag',
    );
  }

  final client = clientFactory();
  try {
    final vectorAssets = await _releaseAssets(
      client,
      '$apiBase/$kSemanticVectorsRepository/releases/tags/'
      '${Uri.encodeComponent(vectors.releaseTag)}',
    );
    for (final file in vectors.files) {
      _checkAsset(vectorAssets, file.name, file.size, file.sha256);
    }
    final manifestName = vectorAssets.keys.firstWhere(
      (name) =>
          name.startsWith(kSemanticVectorsManifestPrefix) &&
          name.endsWith(kSemanticVectorsManifestSuffix),
      orElse: () => throw SemanticComponentsOmitted('no vectors manifest'),
    );
    _checkAsset(
      vectorAssets,
      manifestName,
      utf8.encode(vectors.manifestJson).length,
      vectors.publishedManifestSha256!,
    );

    final identity = SemanticModelIdentity.parse(modelIdentityJson);
    final built = (jsonDecode(vectors.manifestJson) as Map)['identity'];
    final builtModel = built is Map ? built['model'] : null;
    if (builtModel is! Map ||
        builtModel['family_id'] != identity.familyId ||
        builtModel['tokenizer_checksum'] != identity.tokenizerChecksum) {
      throw SemanticComponentsOmitted(
        'vectors-$libraryTag was built for another model than the bundled '
        '${identity.familyId}',
      );
    }

    final source = _modelBaseUrl.firstMatch(release.baseUrl);
    if (source == null) {
      throw SemanticComponentsOmitted('bad model release ${release.baseUrl}');
    }
    final modelAssets = await _releaseAssets(
      client,
      '$apiBase/${source.group(1)}/releases/tags/'
      '${Uri.encodeComponent(source.group(2)!)}',
    );
    for (final file in _offlineModelFiles(release)) {
      _checkAsset(modelAssets, file.name, file.size, file.sha256);
    }

    return buildSemanticComponents(
      model: release,
      modelFamilyId: identity.familyId,
      vectors: vectors,
      vectorsManifestName: manifestName,
    );
  } finally {
    client.close();
  }
}

Future<Map<String, Map<String, dynamic>>> _releaseAssets(
  http.Client client,
  String url,
) async {
  final response = await client
      .get(
        Uri.parse(url),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'otzaria-release',
        },
      )
      .timeout(const Duration(seconds: 30));
  if (response.statusCode == 404) {
    throw SemanticComponentsOmitted('release not found: $url');
  }
  if (response.statusCode != 200) {
    throw http.ClientException(
      'GitHub API ${response.statusCode}',
      Uri.parse(url),
    );
  }
  final release = jsonDecode(response.body);
  return {
    for (final asset
        in (release is Map ? release['assets'] as List? : null) ?? const [])
      if (asset is Map<String, dynamic> && asset['name'] is String)
        asset['name'] as String: asset,
  };
}

/// הנכס קיים, בגודל הצפוי, ו-digest של GitHub (כשיש) שווה ל-[sha256].
void _checkAsset(
  Map<String, Map<String, dynamic>> assets,
  String name,
  int size,
  String sha256,
) {
  final asset = assets[name];
  if (asset == null) throw SemanticComponentsOmitted('asset $name is missing');
  if (asset['size'] != size) {
    throw SemanticComponentsOmitted(
      'asset $name is ${asset['size']} bytes, expected $size',
    );
  }
  final digest = asset['digest'];
  if (digest is String &&
      digest.startsWith('sha256:') &&
      digest.substring(7).toLowerCase() != sha256.toLowerCase()) {
    throw SemanticComponentsOmitted('asset $name has digest $digest');
  }
}

/// לקוח שמזדהה מול api.github.com בלבד — הטוקן אינו עובר להפניות ההורדה.
class _GithubApiClient extends http.BaseClient {
  _GithubApiClient(this._token);
  final String? _token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final token = _token;
    if (token != null &&
        token.isNotEmpty &&
        request.url.host == 'api.github.com') {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

String? _option(List<String> args, String name) {
  final index = args.indexOf('--$name');
  return index < 0 || index + 1 >= args.length ? null : args[index + 1];
}

Future<void> main(List<String> args) async {
  final tag = _option(args, 'library-tag');
  final out = _option(args, 'out');
  if (tag == null || out == null) {
    stderr.writeln(
      'usage: dart run tool/release/semantic_release_components.dart '
      '--library-tag <tag> --out <file> [--model-identity <model.json>]',
    );
    exitCode = 2;
    return;
  }
  final identityPath =
      _option(args, 'model-identity') ?? kSemanticModelBundledIdentity;
  final token =
      Platform.environment['GH_TOKEN'] ?? Platform.environment['GITHUB_TOKEN'];

  var components = const <Map<String, Object?>>[];
  try {
    components = await resolveSemanticComponents(
      libraryTag: tag,
      modelIdentityJson: File(identityPath).readAsStringSync(),
      clientFactory: () => _GithubApiClient(token),
    );
    print(
      'Semantic search components for library $tag: '
      '${components.map((c) => c['id']).join(', ')}',
    );
  } catch (error) {
    print(
      '::warning::Semantic search data omitted from the release manifest '
      '(library $tag): $error',
    );
  }
  File(out).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(components)}\n',
  );
}
