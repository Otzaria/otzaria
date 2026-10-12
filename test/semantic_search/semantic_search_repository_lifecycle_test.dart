import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:path/path.dart' as p;
import 'semantic_test_support.dart';

class DelayedOpenBackend extends FakeBackend {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<SemanticBackendStatus> open(SemanticOpenRequest request) async {
    started.complete();
    await release.future;
    return super.open(request);
  }
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('semantic_audit_'));
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });
  test('pending open must close after consent revocation', () async {
    installModelFiles(root);
    final backend = DelayedOpenBackend()..vectors = installedV30;
    final consent = FakeConsentStore();
    final repo = buildRepository(
      root: root,
      backend: backend,
      consent: consent,
    );
    final opening = repo.ensureOpen();
    await backend.started.future;
    consent.set(SearchFeedbackConsent.declined);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    backend.release.complete();
    await expectLater(
      opening,
      throwsA(
        isA<SemanticFailure>().having(
          (f) => f.kind,
          'kind',
          SemanticFailureKind.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(backend.calls, contains('disable'));
    expect(backend.calls.where((s) => s.startsWith('search:')), isEmpty);
  });
  test('retry must redownload an existing invalid model', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..openFailure = const SemanticFailure(
        SemanticFailureKind.modelInvalid,
        'damaged model',
      );
    final download = FakeDownloads();
    final repo = buildRepository(
      root: root,
      backend: backend,
      download: download.call,
    );
    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    await repo.enableAndDownload();
    expect(download.urls, contains(endsWith('seforim-embed-round2-int8.onnx')));
  });
  test(
    'library update during vector download must trigger next version',
    () async {
      installModelFiles(root);
      var version = 30;
      final consent = FakeConsentStore();
      final backend = FakeBackend();
      final settings = FakeSettingsStore();
      final locator = FakeLocator(releaseV30());
      final downloads = FakeDownloads()..gate = Completer<void>();
      final gate = downloads.gate!;
      final repo = SemanticSearchRepository(
        backend: backend,
        consent: () => consent,
        settings: settings,
        paths: () async => SemanticPaths(p.join(root.path, 'otzaria')),
        identityLoader: (family) async => bundledModelJson(family),
        locator: locator,
        download: downloads.call,
        libraryVersion: () async => version,
        onnxRuntimePath: () => null,
        isPlatformSupported: () => true,
        diskSpace: (_) async =>
            const DiskSpaceInfo(volumeId: 'audit', freeBytes: -1),
        modelReleases: testModelReleases,
        isSecondaryWindow: () => false,
      );
      final first = repo.enableAndDownload();
      await waitFor(() => downloads.urls.isNotEmpty);
      version = 31;
      repo.scheduleVectorsUpdate(libraryTag: 'v31-20261004');
      gate.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(locator.lookups, contains(31));
    },
  );
  test('must not claim and delete a foreign model folder', () async {
    final paths = SemanticPaths(p.join(root.path, 'otzaria'));
    final foreign = File(p.join(paths.modelDirectory, 'user-kept.txt'));
    await foreign.create(recursive: true);
    await foreign.writeAsString('valuable');
    final repo = buildRepository(
      root: root,
      locator: FakeLocator(releaseV30()),
    );
    await repo.enableAndDownload();
    await repo.removeData();
    expect(await foreign.exists(), isTrue);
  });
  for (final action in ['remove', 'move']) {
    test(
      '$action waits for pending open and closes it before completion',
      () async {
        installModelFiles(root);
        final backend = DelayedOpenBackend()..vectors = installedV30;
        final repo = buildRepository(root: root, backend: backend);
        final opening = repo.ensureOpen();
        final rejected = expectLater(opening, throwsA(isA<SemanticFailure>()));
        await backend.started.future;
        var closed = false;
        final closing =
            (action == 'remove'
                    ? repo.removeData()
                    : repo.releaseForLibraryMove())
                .then((_) => closed = true);
        await Future<void>.delayed(Duration.zero);
        expect(closed, false);
        backend.release.complete();
        await rejected;
        await closing;
        expect(backend.calls, contains('disable'));
        expect(backend.calls.where((s) => s.startsWith('search:')), isEmpty);
        if (action == 'move') repo.finishLibraryMove();
      },
    );
  }

  test(
    'retry verifies hashes and downloads only the damaged package file',
    () async {
      installModelFiles(root);
      final paths = SemanticPaths(p.join(root.path, 'otzaria'));
      SemanticModelFile file(String name, List<int> bytes) => SemanticModelFile(
        name: name,
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
      const good = [1, 2, 3, 4];
      await File(
        paths.modelFile(SemanticQuantization.int8),
      ).writeAsBytes([4, 3, 2, 1]);
      await File(paths.tokenizerFile).writeAsBytes(good);
      await File(paths.licenseFile).writeAsBytes(good);
      final release = SemanticModelRelease(
        baseUrl: 'https://model.test',
        graph: file('graph.onnx', good),
        tokenizer: file('tokenizer.json', good),
        license: file('LICENSE', good),
        identity: testModelReleases[SemanticQuantization.int8]!.identity,
      );
      final backend = FakeBackend()
        ..vectors = installedV30
        ..openFailure = const SemanticFailure(SemanticFailureKind.modelInvalid);
      final downloads = FakeDownloads();
      final repo = buildRepository(
        root: root,
        backend: backend,
        download: downloads.call,
        modelReleases: {SemanticQuantization.int8: release},
      );
      await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
      await repo.enableAndDownload();
      expect(downloads.urls, ['https://model.test/graph.onnx']);
      downloads.urls.clear();
      await repo.enableAndDownload();
      expect(
        downloads.urls,
        isEmpty,
        reason: 'verification is not repeated without another model failure',
      );
    },
  );
  test(
    'explicit resume during cancelled download waits and starts a fresh job',
    () async {
      final downloads = FakeDownloads()..gate = Completer<void>();
      final gate = downloads.gate!;
      final settings = FakeSettingsStore();
      final repo = buildRepository(
        root: root,
        settings: settings,
        locator: FakeLocator(releaseV30()),
        download: downloads.call,
      );
      final first = repo.enableAndDownload();
      await waitFor(() => downloads.urls.isNotEmpty);
      await repo.cancelDownload();
      final resumed = repo.enableAndDownload();
      await waitFor(() => !settings.downloadPaused);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await first;
      await resumed;
      expect(
        downloads.urls.where(
          (url) => url.endsWith('seforim-embed-round2-int8.onnx'),
        ),
        hasLength(2),
      );
      expect(repo.availability.failure, isNull);
    },
  );
}
