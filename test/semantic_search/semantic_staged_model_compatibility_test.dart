import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_import_layout.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:path/path.dart' as p;

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('semantic_staged_model_');
    installModelFiles(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  File stagePreviousModel(SemanticVectorsFamily family) {
    final oldModel =
        jsonDecode(
              File(
                family.identityAsset.replaceFirst(
                  'meivin-qa491',
                  'meivin-round2',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final currentModel = jsonDecode(bundledModelJson(family));
    expect(oldModel['chunking_identity'], currentModel['chunking_identity']);
    expect(oldModel['family_id'], isNot(currentModel['family_id']));
    final dir = Directory(
      p.join(
        root.path,
        kSemanticImportFolderName,
        kSemanticImportVectorsFolderName,
      ),
    )..createSync(recursive: true);
    final segment = File(
      p.join(dir.path, 'otzaria-vectors-old-v30-base.oxv.zst'),
    )..writeAsStringSync('previous model vectors');
    File(
      p.join(dir.path, 'otzaria-vectors-old-v30-base.manifest.json'),
    ).writeAsStringSync(
      jsonEncode({
        'kind': 'base',
        'identity': {'model': oldModel},
        'fromLibraryVersion': 0,
        'toLibraryVersion': 30,
        'libraryReleaseTag': 'v30-20260930165019',
        'segment': {'size': 99},
        'files': [
          {
            'file': p.basename(segment.path),
            'size': segment.lengthSync(),
            'sha256': sha256.convert(segment.readAsBytesSync()).toString(),
          },
        ],
      }),
    );
    return segment;
  }

  test('וקטורים מוכנים מהמודל הקודם אינם גוברים על release תואם', () async {
    final previous = stagePreviousModel(SemanticVectorsFamily.anchor);
    final backend = FakeBackend()..supportsLongLineWindows = true;
    final release = releaseV30(family: SemanticVectorsFamily.windows);
    final locator = FakeLocator(release);
    final repository = buildRepository(
      root: root,
      backend: backend,
      locator: locator,
    );

    await repository.enableAndDownload();

    expect(locator.lookups, [30]);
    expect(backend.installRequests.single.manifestJson, release.manifestJson);
    expect(
      backend.installRequests.single.modelIdentityJson,
      bundledModelJson(SemanticVectorsFamily.windows),
    );
    expect(previous.existsSync(), isTrue);
    expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
  });

  for (final family in SemanticVectorsFamily.values) {
    test(
      'נתונים מוכנים ממודל קודם אינם נצרכים במצב לא מקוון: $family',
      () async {
        final previous = stagePreviousModel(family);
        final backend = FakeBackend()..supportsLongLineWindows = true;
        final locator = FakeLocator();
        final downloads = FakeDownloads();
        final repository = buildRepository(
          root: root,
          backend: backend,
          locator: locator,
          download: downloads.call,
          settings: FakeSettingsStore()..isOfflineMode = true,
        );

        await repository.enableAndDownload();

        expect(backend.installRequests, isEmpty);
        expect(previous.existsSync(), isTrue);
        expect(locator.lookups, isEmpty);
        expect(downloads.urls, isEmpty);
        expect(
          repository.availability.failure?.kind,
          SemanticFailureKind.offline,
        );
      },
    );
  }
}
