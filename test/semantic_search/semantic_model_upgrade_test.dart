import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('semantic_model_upgrade_');
    installModelFiles(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  for (final family in const [
    SemanticVectorsFamily.windows,
    SemanticVectorsFamily.anchor,
  ]) {
    test(
      'אותה ספרייה: מחליפים מודל קודם מסוג $family ב-base של פרדס',
      () async {
        final oldDigest = '11' * 32;
        final newDigest = '22' * 32;
        if (family == SemanticVectorsFamily.windows) {
          markInstalledWindowsSet(root, oldDigest);
        }
        final backend = FakeBackend()
          ..vectors = SemanticVectorsSummary(
            present: true,
            modelFamilyId: SemanticModelIdentity.parse(
              File(
                'assets/semantic/meivin-round2-onnx/model.json',
              ).readAsStringSync(),
            ).familyId,
            identityDigest: oldDigest,
            libraryVersion: 30,
            libraryReleaseTag: installedV30.libraryReleaseTag,
          )
          ..installedIdentityDigest = newDigest;
        final locator = FakeLocator(
          releaseV30(identityDigest: newDigest),
        );
        final repository = buildRepository(
          root: root,
          backend: backend,
          settings: FakeSettingsStore()..dataEnabled = true,
          locator: locator,
        );

        expect(
          (await repository.refresh()).phase,
          SemanticAvailabilityPhase.needsDownload,
        );
        repository.scheduleVectorsUpdate();
        await repository.pendingJob;

        expect(locator.lookups, [30]);
        expect(locator.chainLookups, isEmpty);
        expect(backend.installRequests, hasLength(1));
        expect(
          backend.installRequests.single.modelIdentityJson,
          bundledModelJson(),
        );
        expect(repository.availability.phase, SemanticAvailabilityPhase.ready);

        repository.scheduleVectorsUpdate();
        await repository.pendingJob;
        expect(locator.lookups, [30]);
        await repository.ensureOpen();
        expect(
          backend.openRequests.single.modelIdentityJson,
          bundledModelJson(),
        );
      },
    );
  }

  test('פרסום מייבין אינו מחליף סט ממודל קודם ואינו משמש fallback', () async {
    final oldDigest = '11' * 32;
    markInstalledWindowsSet(root, oldDigest);
    final backend = FakeBackend()
      ..vectors = SemanticVectorsSummary(
        present: true,
        modelFamilyId: 'previous-model',
        identityDigest: oldDigest,
        libraryVersion: 30,
      );
    final locator = FakeLocator(
      releaseV30(family: SemanticVectorsFamily.anchor),
    );
    final repository = buildRepository(
      root: root,
      backend: backend,
      locator: locator,
      settings: FakeSettingsStore()..dataEnabled = true,
    );

    repository.scheduleVectorsUpdate();
    await repository.pendingJob;

    expect(locator.candidates.single.map((candidate) => candidate.family), [
      SemanticVectorsFamily.pardesWindows,
    ]);
    expect(backend.installRequests, isEmpty);
    expect(locator.chainLookups, isEmpty);
    expect(
      repository.availability.phase,
      SemanticAvailabilityPhase.vectorsNotPublished,
    );
    await expectLater(repository.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);
  });

  for (final familyId in ['previous-model', '']) {
    test(
      'בלי פרסום תואם לא פותחים סט של family=$familyId ולא מורידים מודל',
      () async {
        final backend = FakeBackend()
          ..vectors = SemanticVectorsSummary(
            present: true,
            modelFamilyId: familyId,
            identityDigest: '11' * 32,
            libraryVersion: 30,
          );
        final downloads = FakeDownloads();
        final locator = FakeLocator();
        final repository = buildRepository(
          root: root,
          backend: backend,
          locator: locator,
          download: downloads.call,
          settings: FakeSettingsStore()..dataEnabled = true,
        );
        expect(
          (await repository.refresh()).phase,
          SemanticAvailabilityPhase.needsDownload,
        );
        await expectLater(
          repository.ensureOpen(),
          throwsA(isA<SemanticFailure>()),
        );

        repository.scheduleVectorsUpdate();
        await repository.pendingJob;

        expect(locator.lookups, [30]);
        expect(downloads.urls, isEmpty);
        expect(backend.installRequests, isEmpty);
        expect(backend.openRequests, isEmpty);
        expect(
          repository.availability.phase,
          SemanticAvailabilityPhase.vectorsNotPublished,
        );
      },
    );
  }

  test('base בזהות אחרת סוגר session גם כשהמודל וסוג החלוקה נשארו', () async {
    final backend = FakeBackend()
      ..vectors = SemanticVectorsSummary(
        present: true,
        modelFamilyId: kTestModelFamilyId,
        identityDigest: '11' * 32,
        libraryVersion: 29,
      )
      ..installedIdentityDigest = '22' * 32;
    final repository = buildRepository(
      root: root,
      backend: backend,
      locator: FakeLocator(releaseV30(identityDigest: '22' * 32)),
      settings: FakeSettingsStore()..dataEnabled = true,
    );
    await repository.ensureOpen();

    repository.scheduleVectorsUpdate();
    await repository.pendingJob;

    final closed = backend.calls.indexOf('disable');
    expect(closed, isNonNegative);
    expect(closed, lessThan(backend.calls.indexOf('install')));
    await repository.ensureOpen();
    expect(backend.openRequests, hasLength(2));
  });
}
