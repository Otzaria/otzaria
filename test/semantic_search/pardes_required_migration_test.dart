import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/repository/semantic_settings_store.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;

import 'semantic_test_support.dart';
import '../test_helpers/memory_cache_provider.dart';

const _legacyFamilyId = 'otzaria/Meivin-Embed-QA491-native256';
const _legacyDigest = '11111111111111111111111111111111';
const _pardesDigest = '22222222222222222222222222222222';
const _pardesFamily = SemanticVectorsFamily.pardesWindows;

void main() {
  late Directory root;
  final repositories = <SemanticSearchRepository>[];

  setUp(() {
    root = Directory.systemTemp.createTempSync('pardes_required_migration_');
    _installLegacyModel(root);
    markInstalledWindowsSet(root, _legacyDigest);
  });
  tearDown(() async {
    for (final repository in repositories) {
      await repository.releaseForLibraryMove();
    }
    repositories.clear();
    root.deleteSync(recursive: true);
  });

  SemanticSearchRepository repository({
    required FakeBackend backend,
    SemanticSettingsStore? settings,
    FakeConsentStore? consent,
    FakeLocator? locator,
    FakeDownloads? downloads,
    Future<String> Function(SemanticVectorsFamily family)? identityLoader,
  }) {
    final files = downloads ?? FakeDownloads();
    final result = SemanticSearchRepository(
      backend: backend,
      settings: settings ?? (FakeSettingsStore()..dataEnabled = true),
      consent: () => consent ?? FakeConsentStore(),
      paths: () async => SemanticPaths(p.join(root.path, 'otzaria')),
      identityLoader:
          identityLoader ?? (family) async => bundledModelJson(family),
      locator: locator ?? FakeLocator(),
      download:
          ({
            required url,
            required destPath,
            required resumeIdentity,
            expectedSize,
            expectedSha256,
            onProgress,
            isCancelled,
          }) async {
            await files.call(
              url: url,
              destPath: destPath,
              resumeIdentity: resumeIdentity,
              expectedSize: expectedSize,
              expectedSha256: expectedSha256,
              onProgress: onProgress,
              isCancelled: isCancelled,
            );
            if (url.endsWith('/model.json')) {
              await File(
                destPath,
              ).writeAsString(bundledModelJson(_pardesFamily));
            }
          },
      libraryVersion: () async => 30,
      onnxRuntimePath: () => '/app/onnxruntime/onnxruntime.dll',
      isPlatformSupported: () => true,
      diskSpace: (_) async => const DiskSpaceInfo(volumeId: 'C', freeBytes: -1),
    );
    repositories.add(result);
    return result;
  }

  test('מייבין מותקן אינו זמין לחיפוש גם כשכל הקבצים שלו קיימים', () async {
    final backend = _legacyBackend();
    final repo = repository(backend: backend);

    expect(
      (await repo.refresh()).phase,
      SemanticAvailabilityPhase.needsDownload,
    );
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);
    expect(_legacyDirectory(root).existsSync(), isTrue);
  });

  test('כשל טעינת הזהות ברקע מדווח בלי לזרוק שוב מתוך הטיפול בכשל', () async {
    final backend = _legacyBackend();
    var identityLoads = 0;
    final repo = repository(
      backend: backend,
      identityLoader: (_) async {
        identityLoads++;
        throw const FormatException('invalid bundled identity');
      },
    );
    await repo.refresh();
    expect(identityLoads, 0);

    repo.scheduleVectorsUpdate();
    await expectLater(repo.pendingJob, completes);

    expect(identityLoads, 1);
    expect(repo.availability.phase, SemanticAvailabilityPhase.failed);
    expect(repo.availability.failure?.kind, SemanticFailureKind.internal);
    expect(backend.installRequests, isEmpty);
    expect(_legacyDirectory(root).existsSync(), isTrue);
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);
    expect(identityLoads, 1);
  });

  test('בחירת מייבין שנשמרה בגרסה קודמת אינה מונעת את המעבר', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>('key-semantic-model-choice', 'meivin');
    const settings = SettingsSemanticSettingsStore();
    await settings.setDataEnabled(true);
    final backend = _legacyBackend()..installedIdentityDigest = _pardesDigest;
    final repo = repository(
      backend: backend,
      settings: settings,
      locator: FakeLocator(
        releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
      ),
    );

    repo.scheduleVectorsUpdate();
    await repo.pendingJob;
    await repo.ensureOpen();

    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(
      backend.openRequests.single.modelIdentityJson,
      bundledModelJson(_pardesFamily),
    );
    expect(_legacyDirectory(root).existsSync(), isFalse);
  });

  test('פרדס שסומן בעבר כמדולג אינו משאיר את המשתמש במייבין', () async {
    final release = releaseV30(
      family: _pardesFamily,
      identityDigest: _pardesDigest,
    );
    final settings = FakeSettingsStore()
      ..dataEnabled = true
      ..skippedVectorsRelease = release.releaseTag;
    final backend = _legacyBackend()..installedIdentityDigest = _pardesDigest;
    final repo = repository(
      backend: backend,
      settings: settings,
      locator: FakeLocator(release),
    );

    repo.scheduleVectorsUpdate();
    await repo.pendingJob;

    expect(backend.installRequests, hasLength(1));
    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(repo.availability.phase, SemanticAvailabilityPhase.ready);
    expect(_legacyDirectory(root).existsSync(), isFalse);
  });

  test('הפעלה אחרי התקנת פרדס משלימה ניקוי שנותר בלי הורדה חוזרת', () async {
    final dir = Directory(p.join(root.path, 'otzaria', 'pardesqa491-onnx'))
      ..createSync(recursive: true);
    for (final name in [
      'model.onnx',
      'tokenizer.json',
      'LICENSE-AGPL-3.0.txt',
      'Pardes_NOTICE.txt',
      kSemanticOwnerMarker,
    ]) {
      File(p.join(dir.path, name)).writeAsStringSync('installed');
    }
    File(
      p.join(dir.path, 'model.json'),
    ).writeAsStringSync(bundledModelJson(_pardesFamily));
    final backend = FakeBackend()
      ..supportsLongLineWindows = true
      ..vectors = const SemanticVectorsSummary(
        present: true,
        modelFamilyId: kCompactPardesModelFamilyId,
        identityDigest: _pardesDigest,
        libraryVersion: 30,
      );
    final downloads = FakeDownloads();
    final locator = FakeLocator();
    final repo = repository(
      backend: backend,
      downloads: downloads,
      locator: locator,
    );

    repo.scheduleVectorsUpdate();
    await repo.pendingJob;

    expect(repo.availability.phase, SemanticAvailabilityPhase.ready);
    expect(locator.lookups, isEmpty);
    expect(downloads.urls, isEmpty);
    expect(backend.installRequests, isEmpty);
    expect(_legacyDirectory(root).existsSync(), isFalse);
  });

  test('אותה גרסת ספרייה עוברת אוטומטית ל-base פרדס בלי delta', () async {
    final backend = _legacyBackend()..installedIdentityDigest = _pardesDigest;
    final locator = FakeLocator(
      releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
    );
    final downloads = FakeDownloads();
    final repo = repository(
      backend: backend,
      locator: locator,
      downloads: downloads,
    );

    repo.scheduleVectorsUpdate();
    await repo.pendingJob;

    expect(locator.lookups, [30]);
    expect(locator.candidates.single.map((candidate) => candidate.family), [
      _pardesFamily,
    ]);
    expect(locator.chainLookups, isEmpty);
    expect(backend.installRequests, hasLength(1));
    expect(
      backend.installRequests.single.modelIdentityJson,
      bundledModelJson(_pardesFamily),
    );
    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(repo.availability.phase, SemanticAvailabilityPhase.ready);
    expect(_legacyDirectory(root).existsSync(), isFalse);
    expect(downloads.urls.any((url) => url.contains('meivin')), isFalse);
    expect(
      downloads.urls.any((url) => url.endsWith('Pardes_NOTICE.txt')),
      isTrue,
    );
    expect(
      downloads.urls.any((url) => url.endsWith('document.fp32.onnx')),
      isFalse,
    );

    await repo.ensureOpen();
    expect(
      backend.openRequests.single.modelPath,
      endsWith(p.join('pardesqa491-onnx', 'model.onnx')),
    );
    expect(
      backend.openRequests.single.modelIdentityJson,
      bundledModelJson(_pardesFamily),
    );

    final downloadCount = downloads.urls.length;
    final restarted = repository(
      backend: backend,
      locator: locator,
      downloads: downloads,
    );
    restarted.scheduleVectorsUpdate();
    await restarted.pendingJob;
    await restarted.ensureOpen();
    expect(locator.lookups, [30]);
    expect(downloads.urls.length, downloadCount);
    expect(backend.installRequests, hasLength(1));
    expect(
      backend.openRequests.last.modelIdentityJson,
      bundledModelJson(_pardesFamily),
    );
  });

  test('ניקוי מודל מייבין ממתין לסיום התקנת וקטורי פרדס', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final backend = _GatedInstallBackend(gate)
      ..vectors = _legacyVectors
      ..installedIdentityDigest = _pardesDigest
      ..supportsLongLineWindows = true;
    final repo = repository(
      backend: backend,
      locator: FakeLocator(
        releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
      ),
    );
    repo.scheduleVectorsUpdate();
    await waitFor(() => backend.installStarted);
    expect(backend.installStarted, isTrue);
    expect(_legacyDirectory(root).existsSync(), isTrue);
    expect(backend.vectors.modelFamilyId, _legacyFamilyId);
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);

    gate.complete();
    await repo.pendingJob;
    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(_legacyDirectory(root).existsSync(), isFalse);
  });

  test('ביטול אחרי commit מנקה את מייבין בלי להתחיל איחוד וקטורים', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final backend = _PostCommitBackend(gate)
      ..vectors = _legacyVectors
      ..installedIdentityDigest = _pardesDigest
      ..supportsLongLineWindows = true
      ..installResults.add(
        const SemanticInstallSummary(
          kind: 'base',
          libraryVersion: 30,
          segments: 1,
          bytesOnDisk: 10,
          needsCompaction: true,
          alreadyApplied: false,
        ),
      );
    final settings = FakeSettingsStore()..dataEnabled = true;
    final repo = repository(
      backend: backend,
      settings: settings,
      locator: FakeLocator(
        releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
      ),
    );
    repo.scheduleVectorsUpdate();
    await waitFor(() => backend.committed);
    expect(backend.committed, isTrue);
    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(_legacyDirectory(root).existsSync(), isTrue);

    await repo.cancelDownload();
    gate.complete();
    await repo.pendingJob;

    expect(settings.downloadPaused, isTrue);
    expect(repo.availability.phase, SemanticAvailabilityPhase.ready);
    expect(_legacyDirectory(root).existsSync(), isFalse);
    expect(backend.vectors.needsCompaction, isTrue);
    expect(backend.compactVersions, isEmpty);
    await repo.ensureOpen();
    expect(
      backend.openRequests.single.modelIdentityJson,
      bundledModelJson(_pardesFamily),
    );
  });

  for (final failure in const [
    SemanticFailure(SemanticFailureKind.artifactCorrupt),
    SemanticFailure(
      SemanticFailureKind.artifactIncompatible,
      'incompatible',
      'model.chunking_identity',
    ),
  ]) {
    test(
      'כשל ${failure.kind.name} שומר נתונים ישנים ואינו פותח אותם',
      () async {
        final backend = _legacyBackend()..installFailures.add(failure);
        final settings = FakeSettingsStore()..dataEnabled = true;
        final repo = repository(
          backend: backend,
          settings: settings,
          locator: FakeLocator(
            releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
          ),
        );
        await repo.enableAndDownload();

        expect(backend.installRequests, hasLength(1));
        expect(backend.vectors, _legacyVectors);
        expect(_legacyDirectory(root).existsSync(), isTrue);
        expect(repo.availability.phase, isNot(SemanticAvailabilityPhase.ready));
        await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
        expect(backend.openRequests, isEmpty);
        if (failure.kind == SemanticFailureKind.artifactIncompatible) {
          expect(settings.skippedVectorsRelease, isNull);
          expect(
            repo.availability.failure?.kind,
            SemanticFailureKind.artifactIncompatible,
          );
        }
      },
    );
  }

  test('פרסום מייבין בלבד אינו משמש תחליף לפרדס', () async {
    final backend = _legacyBackend();
    final downloads = FakeDownloads();
    final repo = repository(
      backend: backend,
      downloads: downloads,
      locator: FakeLocator(releaseV30(family: SemanticVectorsFamily.windows)),
    );
    repo.scheduleVectorsUpdate();
    await repo.pendingJob;

    expect(
      repo.availability.phase,
      SemanticAvailabilityPhase.vectorsNotPublished,
    );
    expect(downloads.urls, isEmpty);
    expect(backend.installRequests, isEmpty);
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);
    expect(_legacyDirectory(root).existsSync(), isTrue);
  });

  test('מצב לא מקוון אינו מפעיל מחדש את מייבין ואינו פונה לרשת', () async {
    final backend = _legacyBackend();
    final downloads = FakeDownloads();
    final locator = FakeLocator(releaseV30(family: _pardesFamily));
    final settings = FakeSettingsStore()
      ..dataEnabled = true
      ..isOfflineMode = true;
    final repo = repository(
      backend: backend,
      settings: settings,
      locator: locator,
      downloads: downloads,
    );
    await repo.enableAndDownload();

    expect(repo.availability.phase, SemanticAvailabilityPhase.failed);
    expect(repo.availability.failure?.kind, SemanticFailureKind.offline);
    expect(locator.lookups, isEmpty);
    expect(downloads.urls, isEmpty);
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);
    expect(_legacyDirectory(root).existsSync(), isTrue);
  });

  test('ביטול שומר את ההתקנה הישנה; חידוש מסיים את המעבר לפרדס', () async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final backend = _legacyBackend()..installedIdentityDigest = _pardesDigest;
    final downloads = FakeDownloads()..gate = gate;
    final settings = FakeSettingsStore()..dataEnabled = true;
    final repo = repository(
      backend: backend,
      settings: settings,
      downloads: downloads,
      locator: FakeLocator(
        releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
      ),
    );
    repo.scheduleVectorsUpdate();
    await waitFor(() => downloads.urls.isNotEmpty);
    expect(downloads.urls, isNotEmpty);
    await repo.cancelDownload();
    gate.complete();
    await repo.pendingJob;

    expect(settings.downloadPaused, isTrue);
    expect(backend.installRequests, isEmpty);
    expect(_legacyDirectory(root).existsSync(), isTrue);
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    expect(backend.openRequests, isEmpty);

    await repo.enableAndDownload();
    expect(settings.downloadPaused, isFalse);
    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(_legacyDirectory(root).existsSync(), isFalse);
    expect(repo.availability.phase, SemanticAvailabilityPhase.ready);
  });

  for (final condition in ['disabled', 'paused', 'no-consent']) {
    test('המעבר ברקע מכבד $condition', () async {
      final backend = _legacyBackend();
      final downloads = FakeDownloads();
      final locator = FakeLocator(releaseV30(family: _pardesFamily));
      final settings = FakeSettingsStore()
        ..dataEnabled = condition != 'disabled'
        ..downloadPaused = condition == 'paused';
      final consent = FakeConsentStore(
        condition == 'no-consent'
            ? SearchFeedbackConsent.declined
            : SearchFeedbackConsent.granted,
      );
      final repo = repository(
        backend: backend,
        settings: settings,
        consent: consent,
        locator: locator,
        downloads: downloads,
      );
      repo.scheduleVectorsUpdate();
      await repo.pendingJob;

      expect(locator.lookups, isEmpty);
      expect(downloads.urls, isEmpty);
      expect(backend.installRequests, isEmpty);
      expect(_legacyDirectory(root).existsSync(), isTrue);
    });
  }

  test('תיקייה ישנה ללא סימון בעלות נשמרת גם אחרי המעבר', () async {
    File(
      p.join(_legacyDirectory(root).path, kSemanticOwnerMarker),
    ).deleteSync();
    final userFile = File(p.join(_legacyDirectory(root).path, 'personal.txt'))
      ..writeAsStringSync('keep');
    final backend = _legacyBackend()..installedIdentityDigest = _pardesDigest;
    final repo = repository(
      backend: backend,
      locator: FakeLocator(
        releaseV30(family: _pardesFamily, identityDigest: _pardesDigest),
      ),
    );
    repo.scheduleVectorsUpdate();
    await repo.pendingJob;

    expect(repo.availability.phase, SemanticAvailabilityPhase.ready);
    expect(backend.vectors.modelFamilyId, kCompactPardesModelFamilyId);
    expect(userFile.readAsStringSync(), 'keep');
  });
}

const _legacyVectors = SemanticVectorsSummary(
  present: true,
  modelFamilyId: _legacyFamilyId,
  identityDigest: _legacyDigest,
  libraryVersion: 30,
  libraryReleaseTag: 'v30-20260930165019',
);

FakeBackend _legacyBackend() => FakeBackend()
  ..supportsLongLineWindows = true
  ..vectors = _legacyVectors;

Directory _legacyDirectory(Directory root) =>
    Directory(p.join(root.path, 'otzaria', 'meivin-qa491-onnx'));

void _installLegacyModel(Directory root) {
  final dir = _legacyDirectory(root)..createSync(recursive: true);
  for (final name in [
    'query.int8.onnx',
    'tokenizer.json',
    'LICENSE',
    kSemanticOwnerMarker,
  ]) {
    File(p.join(dir.path, name)).writeAsStringSync('legacy');
  }
  File(
    p.join(dir.path, 'model.json'),
  ).writeAsStringSync(bundledModelJson(SemanticVectorsFamily.anchor));
}

class _GatedInstallBackend extends FakeBackend {
  _GatedInstallBackend(this.gate);

  final Completer<void> gate;
  bool installStarted = false;

  @override
  Future<SemanticInstallSummary> installVectors(
    SemanticInstallRequest request, {
    required SemanticCancelHandle cancel,
  }) async {
    installStarted = true;
    await gate.future;
    return super.installVectors(request, cancel: cancel);
  }
}

class _PostCommitBackend extends FakeBackend {
  _PostCommitBackend(this.gate);

  final Completer<void> gate;
  bool committed = false;

  @override
  Future<SemanticInstallSummary> installVectors(
    SemanticInstallRequest request, {
    required SemanticCancelHandle cancel,
  }) async {
    final result = await super.installVectors(request, cancel: cancel);
    committed = true;
    await gate.future;
    return result;
  }
}
