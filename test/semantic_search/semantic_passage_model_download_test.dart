import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_model_release.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/repository/semantic_staged_import.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadCancelled;

import 'semantic_test_support.dart';

const _passageBytes = [1, 2, 3, 4, 5, 6, 7, 8];

Matcher failure(SemanticFailureKind kind) => throwsA(
  isA<SemanticFailure>().having((value) => value.kind, 'kind', kind),
);

class _Downloads {
  final urls = <String>[];
  final destinations = <String>[];
  final started = Completer<void>();
  Completer<void>? gate;
  bool Function()? cancelled;
  List<int> bytes = _passageBytes;
  bool openBeforeWait = false;

  Future<void> call({
    required String url,
    required String destPath,
    required String resumeIdentity,
    int? expectedSize,
    String? expectedSha256,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    urls.add(url);
    destinations.add(destPath);
    cancelled = isCancelled;
    expect(resumeIdentity, sha256.convert(_passageBytes).toString());
    expect(expectedSha256, resumeIdentity);
    expect(expectedSize, _passageBytes.length);
    RandomAccessFile? opened;
    try {
      if (openBeforeWait) {
        opened = await File(destPath).open(mode: FileMode.write);
        await opened.writeFrom(bytes, 0, 4);
        await opened.flush();
      }
      if (!started.isCompleted) started.complete();
      await gate?.future;
      if (isCancelled?.call() ?? false) throw const PatchDownloadCancelled();
      if (opened != null) {
        await opened.writeFrom(bytes, 4);
        await opened.flush();
      } else {
        await File(destPath).writeAsBytes(bytes, flush: true);
      }
    } finally {
      await opened?.close();
    }
  }
}

class _Harness {
  _Harness(this.root, {bool separatePassages = true, FakeBackend? backend})
    : backend = backend ?? (FakeBackend()..vectors = installedV30) {
    installModelFiles(root);
    currentRoot = root;
    final queryRelease = testModelReleases[SemanticQuantization.int8]!;
    final release = SemanticModelRelease(
      baseUrl: queryRelease.baseUrl,
      graph: queryRelease.graph,
      tokenizer: queryRelease.tokenizer,
      identity: queryRelease.identity,
      license: queryRelease.license,
      passageGraph: separatePassages
          ? SemanticModelFile(
              name: 'document.fp32.onnx',
              size: _passageBytes.length,
              sha256: sha256.convert(_passageBytes).toString(),
            )
          : null,
    );
    repo = SemanticSearchRepository(
      backend: this.backend,
      consent: () => consent,
      settings: settings,
      paths: () async => paths,
      identityLoader: (family) async => bundledModelJson(family),
      locator: FakeLocator(),
      download: downloads.call,
      libraryVersion: () async => 30,
      onnxRuntimePath: () => '/app/onnxruntime/libonnxruntime.dylib',
      isPlatformSupported: () => true,
      diskSpace: (_) async =>
          const DiskSpaceInfo(volumeId: 'test', freeBytes: -1),
      modelReleases: {SemanticQuantization.int8: release},
    );
  }

  final Directory root;
  late Directory currentRoot;
  final FakeBackend backend;
  final settings = FakeSettingsStore()..dataEnabled = true;
  final consent = FakeConsentStore();
  final downloads = _Downloads();
  late final SemanticSearchRepository repo;

  SemanticPaths get paths => SemanticPaths(p.join(currentRoot.path, 'otzaria'));
  File get document => File(paths.modelFile(SemanticQuantization.fp32));

  Future<List<SemanticPassageHighlight>> highlight({
    SemanticCancelHandle? cancel,
    int id = 1,
  }) => repo.passageHighlights('כבוד אב', [
    SemanticHighlightTarget(filePath: 'id:$id', id: BigInt.from(id)),
  ], cancel ?? SemanticCancelHandle());

  Future<void> close() async {
    final gate = downloads.gate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await repo.releaseForLibraryMove();
  }
}

class _GatedDisableBackend extends FakeBackend {
  final started = Completer<void>();
  final release = Completer<void>();
  int disableCalls = 0;

  @override
  Future<void> disable() async {
    disableCalls++;
    if (!started.isCompleted) started.complete();
    await release.future;
    await super.disable();
  }
}

final class _StagingDeletionGate extends IOOverrides {
  final started = Completer<void>();
  final release = Completer<void>();
  int calls = 0;

  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    return p.basename(path).startsWith('.passage-model-')
        ? _GatedStagingDirectory(directory, this)
        : directory;
  }
}

class _GatedStagingDirectory extends Fake implements Directory {
  _GatedStagingDirectory(this.directory, this.gate);

  final Directory directory;
  final _StagingDeletionGate gate;

  @override
  String get path => directory.path;

  @override
  Future<bool> exists() => directory.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    gate.calls++;
    if (!gate.started.isCompleted) gate.started.complete();
    await gate.release.future;
    return directory.delete(recursive: recursive);
  }
}

void main() {
  late Directory root;
  _Harness? active;

  setUp(() {
    root = Directory.systemTemp.createTempSync('semantic_passage_');
    active = null;
  });
  tearDown(() async {
    await active?.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  _Harness harness({bool separatePassages = true, FakeBackend? backend}) =>
      active = _Harness(
        root,
        separatePassages: separatePassages,
        backend: backend,
      );

  test(
    'the published FP32 asset stays optional for the initial query package',
    () {
      final release = kSemanticModelReleases[SemanticQuantization.int8]!;
      expect(
        release.passageGraph!.name,
        SemanticQuantization.fp32.modelFileName,
      );
      expect(release.passageGraph!.size, 168145648);
      expect(
        release.passageGraph!.sha256,
        '46ba402ce20693d0a3b65aa557a368a3535bbb2a5a1f559d848e803788f7b667',
      );
      expect(release.downloadSize, lessThan(50000000));
      expect(kSemanticModelReleases[SemanticQuantization.fp32], isNull);
    },
  );

  test('query search does not fetch the optional passage graph', () async {
    final h = harness();
    await h.repo.search(
      const SemanticSearchRequest(query: 'חסד', facets: []),
    );
    expect(h.downloads.urls, isEmpty);
    expect(await h.document.exists(), isFalse);
  });

  test(
    'highlight does not start a download without an open query session',
    () async {
      final h = harness();
      await expectLater(
        h.highlight(),
        failure(SemanticFailureKind.notConfigured),
      );
      expect(h.downloads.urls, isEmpty);
      expect(h.backend.highlightTargets, isEmpty);
    },
  );

  test('highlight waits for an atomic verified passage download', () async {
    final h = harness();
    await h.repo.ensureOpen();
    h.downloads.gate = Completer<void>();
    final marked = h.highlight();
    await h.downloads.started.future;
    expect(h.backend.highlightTargets, isEmpty);
    expect(await h.document.exists(), isFalse);
    h.downloads.gate!.complete();
    expect(await marked, hasLength(1));
    expect(await h.document.readAsBytes(), _passageBytes);
    expect(await File('${h.document.path}.part').exists(), isFalse);
    expect(h.downloads.urls, ['https://models.test/meivin/document.fp32.onnx']);
    await h.highlight();
    expect(h.downloads.urls, hasLength(1));
  });

  test('an existing damaged passage file is verified and repaired', () async {
    final h = harness();
    await h.repo.ensureOpen();
    await h.document.writeAsBytes(List.filled(_passageBytes.length, 0));
    await h.highlight();
    expect(h.downloads.urls, hasLength(1));
    expect(await h.document.readAsBytes(), _passageBytes);
  });

  test(
    'a cached verification is invalidated after same-size file damage',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      await h.document.writeAsBytes(_passageBytes);
      await h.highlight();
      expect(h.downloads.urls, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await h.document.writeAsBytes(List.filled(_passageBytes.length, 9));
      await h.highlight();
      expect(h.downloads.urls, hasLength(1));
      expect(await h.document.readAsBytes(), _passageBytes);
    },
  );

  test(
    'a corrupt response never replaces the final graph or reaches Rust',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.downloads.bytes = List.filled(_passageBytes.length, 9);
      await expectLater(
        h.highlight(),
        failure(SemanticFailureKind.checksumMismatch),
      );
      expect(await h.document.exists(), isFalse);
      expect(await File('${h.document.path}.part').exists(), isFalse);
      expect(h.backend.highlightTargets, isEmpty);
      h.downloads.bytes = _passageBytes;
      await h.highlight();
      expect(await h.document.readAsBytes(), _passageBytes);
    },
  );

  test(
    'concurrent callers share the download and cancel independently',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.downloads.gate = Completer<void>();
      final firstCancel = SemanticCancelHandle();
      final first = h.highlight(cancel: firstCancel);
      final rejected = expectLater(
        first,
        failure(SemanticFailureKind.cancelled),
      );
      final second = h.highlight(id: 2);
      await h.downloads.started.future;
      firstCancel.cancel();
      await rejected;
      expect(h.downloads.cancelled!(), isFalse);
      expect(h.downloads.urls, hasLength(1));
      h.downloads.gate!.complete();
      expect((await second).single.id, BigInt.two);
      expect(h.backend.highlightTargets.map((target) => target.id), [
        BigInt.two,
      ]);
    },
  );

  test(
    'the last caller cancelling stops transfer before publication',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.downloads.gate = Completer<void>();
      final cancel = SemanticCancelHandle();
      final marked = h.highlight(cancel: cancel);
      final rejected = expectLater(
        marked,
        failure(SemanticFailureKind.cancelled),
      );
      await h.downloads.started.future;
      cancel.cancel();
      await rejected;
      expect(h.downloads.cancelled!(), isTrue);
      h.downloads.gate!.complete();
      await h.repo.releaseForLibraryMove();
      expect(await h.document.exists(), isFalse);
      expect(h.backend.highlightTargets, isEmpty);
    },
  );

  test(
    'new callers coalesce after a cancelled transfer has shut down',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      final firstGate = h.downloads.gate = Completer<void>();
      final cancel = SemanticCancelHandle();
      final first = h.highlight(cancel: cancel);
      final rejected = expectLater(
        first,
        failure(SemanticFailureKind.cancelled),
      );
      await h.downloads.started.future;
      cancel.cancel();
      await rejected;
      final secondGate = h.downloads.gate = Completer<void>();
      final second = h.highlight(id: 2);
      final third = h.highlight(id: 3);
      firstGate.complete();
      await waitFor(() => h.downloads.urls.length >= 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.downloads.urls, hasLength(2));
      secondGate.complete();
      expect(await Future.wait([second, third]), everyElement(hasLength(1)));
      expect(h.backend.highlightTargets.map((target) => target.id), [
        BigInt.two,
        BigInt.from(3),
      ]);
    },
  );

  test(
    'separate windows never write into each other\'s pending graph',
    () async {
      final first = harness();
      final second = _Harness(root);
      try {
        await first.repo.ensureOpen();
        await second.repo.ensureOpen();
        first.downloads.gate = Completer<void>();
        second.downloads.gate = Completer<void>();
        final firstHighlight = first.highlight();
        final secondHighlight = second.highlight();
        final rejected = expectLater(
          secondHighlight,
          failure(SemanticFailureKind.checksumMismatch),
        );
        await Future.wait([
          first.downloads.started.future,
          second.downloads.started.future,
        ]);
        expect(
          first.downloads.destinations.single,
          isNot(second.downloads.destinations.single),
        );
        first.downloads.gate!.complete();
        await firstHighlight;
        second.downloads.bytes = List.filled(_passageBytes.length, 9);
        second.downloads.gate!.complete();
        await rejected;
        expect(await first.document.readAsBytes(), _passageBytes);
        expect(first.backend.highlightTargets, hasLength(1));
        expect(second.backend.highlightTargets, isEmpty);
      } finally {
        await second.close();
      }
    },
  );

  test(
    'paused downloads permit cached highlights but no new download',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.settings.downloadPaused = true;
      await expectLater(h.highlight(), failure(SemanticFailureKind.notReady));
      expect(h.downloads.urls, isEmpty);
      await h.document.writeAsBytes(_passageBytes);
      await h.highlight();
      expect(h.backend.highlightTargets, hasLength(1));
    },
  );

  for (final action in ['rename', 'remove']) {
    test(
      'another window may $action the source without resurrecting it',
      () async {
        final h = harness();
        await h.repo.ensureOpen();
        h.downloads.gate = Completer<void>();
        h.downloads.openBeforeWait = !Platform.isWindows;
        final original = Directory(h.paths.modelDirectory);
        final oldDocument = h.document;
        final marked = h.highlight();
        final rejected = expectLater(
          marked,
          failure(SemanticFailureKind.cancelled),
        );
        await h.downloads.started.future;
        if (action == 'rename') {
          await original.rename('${original.path}-moved');
        } else {
          await original.delete(recursive: true);
        }
        h.downloads.gate!.complete();
        await rejected;
        expect(await original.exists(), isFalse);
        expect(await oldDocument.exists(), isFalse);
        expect(h.backend.highlightTargets, isEmpty);
      },
    );
  }

  test(
    'request cancellation retains an isolated partial for a later retry',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.downloads.gate = Completer<void>();
      h.downloads.openBeforeWait = true;
      final cancel = SemanticCancelHandle();
      final first = h.highlight(cancel: cancel);
      final rejected = expectLater(
        first,
        failure(SemanticFailureKind.cancelled),
      );
      await h.downloads.started.future;
      cancel.cancel();
      await rejected;
      h.downloads.gate!.complete();
      h.downloads.gate = null;
      h.downloads.openBeforeWait = false;
      await h.highlight();
      expect(h.downloads.destinations, hasLength(2));
      expect(h.downloads.destinations.first, h.downloads.destinations.last);
      expect(await h.document.readAsBytes(), _passageBytes);
    },
  );

  test(
    'offline mode uses verified cache and never requests a missing graph',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.settings.isOfflineMode = true;
      await expectLater(h.highlight(), failure(SemanticFailureKind.offline));
      expect(h.downloads.urls, isEmpty);
      await h.document.writeAsBytes(_passageBytes);
      await h.highlight();
      expect(h.backend.highlightTargets, hasLength(1));
    },
  );

  test(
    'a cancelled main download token is not reused by highlighting',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      await h.repo.cancelDownload();
      h.settings.downloadPaused = false;
      await h.highlight();
      expect(h.downloads.urls, hasLength(1));
      expect(h.backend.highlightTargets, hasLength(1));
    },
  );

  test(
    'offline highlighting adopts a verified prepared passage graph',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      final prepared = File(
        p.join(
          SemanticStagedImport.directoryOf(h.paths),
          kSemanticModelFolderName,
          'document.fp32.onnx',
        ),
      );
      await prepared.create(recursive: true);
      await prepared.writeAsBytes(_passageBytes);
      h.settings.isOfflineMode = true;
      await h.highlight();
      expect(h.downloads.urls, isEmpty);
      expect(await h.document.readAsBytes(), _passageBytes);
      expect(await prepared.exists(), isTrue);
      expect(h.backend.highlightTargets, hasLength(1));
    },
  );

  for (final action in ['move', 'remove']) {
    test(
      '$action waits for transfer shutdown and blocks new passage writes',
      () async {
        final h = harness();
        await h.repo.ensureOpen();
        h.downloads.gate = Completer<void>();
        final oldDocument = h.document;
        final marked = h.highlight();
        final rejected = expectLater(
          marked,
          failure(SemanticFailureKind.cancelled),
        );
        await h.downloads.started.future;
        var stopped = false;
        final stopping =
            (action == 'move'
                    ? h.repo.releaseForLibraryMove()
                    : h.repo.removeData())
                .then((_) => stopped = true);
        await rejected;
        expect(stopped, isFalse);
        await expectLater(
          h.highlight(id: 2),
          failure(SemanticFailureKind.cancelled),
        );
        h.downloads.gate!.complete();
        await stopping;
        expect(await oldDocument.exists(), isFalse);
        expect(h.backend.highlightTargets, isEmpty);
        if (action == 'move') {
          h.currentRoot = await Directory(p.join(root.path, 'new')).create();
          installModelFiles(h.currentRoot);
          h.repo.finishLibraryMove();
          await h.repo.ensureOpen();
          await h.highlight();
          expect(await h.document.readAsBytes(), _passageBytes);
          expect(await oldDocument.exists(), isFalse);
        }
      },
    );
  }

  test(
    'consent revocation cancels the passage transfer without a fallback',
    () async {
      final h = harness();
      await h.repo.ensureOpen();
      h.downloads.gate = Completer<void>();
      final marked = h.highlight();
      final rejected = expectLater(
        marked,
        failure(SemanticFailureKind.cancelled),
      );
      await h.downloads.started.future;
      final consentClosed = h.repo.availabilityChanges.firstWhere(
        (availability) => !availability.consentGranted,
      );
      h.consent.set(SearchFeedbackConsent.declined);
      await rejected;
      h.downloads.gate!.complete();
      await h.repo.releaseForLibraryMove();
      await consentClosed;
      expect(await h.document.exists(), isFalse);
      expect(h.backend.highlightTargets, isEmpty);
    },
  );

  test('concurrent close calls wait for the same staging cleanup', () async {
    final deletion = _StagingDeletionGate();
    addTearDown(() {
      if (!deletion.release.isCompleted) deletion.release.complete();
    });
    await IOOverrides.runWithIOOverrides(() async {
      final h = harness();
      await h.repo.ensureOpen();
      h.downloads.gate = Completer<void>();
      final rejected = expectLater(
        h.highlight(),
        failure(SemanticFailureKind.cancelled),
      );
      await h.downloads.started.future;
      final consentClosed = h.repo.availabilityChanges.firstWhere(
        (availability) => !availability.consentGranted,
      );
      h.consent.set(SearchFeedbackConsent.declined);
      await rejected;
      h.downloads.gate!.complete();
      await deletion.started.future;

      var moveCompleted = false;
      final moving = h.repo.releaseForLibraryMove().then((_) {
        moveCompleted = true;
      });
      try {
        // כל ה-Future-ים של הסגירה השנייה כבר זמינים; רק המחיקה חסומה.
        await pumpEventQueue(times: 1);
        expect(moveCompleted, isFalse);
        expect(deletion.calls, 1);
      } finally {
        deletion.release.complete();
        await moving;
        await consentClosed;
      }
      expect(await h.document.exists(), isFalse);
      expect(h.backend.highlightTargets, isEmpty);
    }, deletion);
  });

  test('a library move waits for an in-flight backend disable', () async {
    final backend = _GatedDisableBackend()..vectors = installedV30;
    addTearDown(() {
      if (!backend.release.isCompleted) backend.release.complete();
    });
    final h = harness(backend: backend);
    await h.repo.ensureOpen();
    final consentClosed = h.repo.availabilityChanges.firstWhere(
      (availability) => !availability.consentGranted,
    );
    h.consent.set(SearchFeedbackConsent.declined);
    await backend.started.future;

    var moveCompleted = false;
    final moving = h.repo.releaseForLibraryMove().then((_) {
      moveCompleted = true;
    });
    try {
      await pumpEventQueue(times: 1);
      expect(moveCompleted, isFalse);
      expect(backend.disableCalls, 1);
    } finally {
      backend.release.complete();
      await moving;
      await consentClosed;
    }
    expect(backend.calls, contains('disable'));
  });

  test('families without a separate passage graph retain their path', () async {
    final h = harness(separatePassages: false);
    await h.repo.ensureOpen();
    await h.highlight();
    expect(h.downloads.urls, isEmpty);
    expect(h.backend.highlightTargets, hasLength(1));
  });
}
