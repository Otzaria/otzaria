import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:path/path.dart' as p;

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_repo_'));
  tearDown(() async {
    // ב-Windows קובץ שעבודת רקע עוד סוגרת נועל את התיקייה הזמנית לרגע.
    for (var attempt = 0; attempt < 5 && root.existsSync(); attempt++) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  SemanticPaths paths() => SemanticPaths(p.join(root.path, 'otzaria'));

  group('זמינות', () {
    test('פלטפורמה שאינה נתמכת — מוסתר', () async {
      final repository = buildRepository(root: root, platformSupported: false);

      final availability = await repository.refresh();

      expect(availability.phase, SemanticAvailabilityPhase.hidden);
      expect(
        availability.hiddenReason,
        SemanticHiddenReason.unsupportedPlatform,
      );
    });

    test('מנוע בלי חיפוש סמנטי — מוסתר, וההסכמה עדיין מדווחת', () async {
      final backend = FakeBackend()
        ..statusValue = SemanticBackendStatus.notInBuild;
      final repository = buildRepository(root: root, backend: backend);

      final availability = await repository.refresh();

      expect(availability.phase, SemanticAvailabilityPhase.hidden);
      expect(availability.hiddenReason, SemanticHiddenReason.engineNotInBuild);
      expect(availability.consentGranted, isTrue);
      expect(availability.isMissingEngineOrData, isTrue);
    });

    test('בלי הסכמה — consentRequired', () async {
      final repository = buildRepository(
        root: root,
        consent: FakeConsentStore(SearchFeedbackConsent.declined),
      );

      final availability = await repository.refresh();

      expect(availability.phase, SemanticAvailabilityPhase.consentRequired);
      expect(availability.isMissingEngineOrData, isFalse);
    });

    test('בלי מודל — needsDownload; עם מודל ווקטורים — ready', () async {
      final backend = FakeBackend();
      final repository = buildRepository(root: root, backend: backend);

      expect(
        (await repository.refresh()).phase,
        SemanticAvailabilityPhase.needsDownload,
      );

      installModelFiles(root);
      backend.vectors = installedV30;
      final ready = await repository.refresh();
      expect(ready.phase, SemanticAvailabilityPhase.ready);
      expect(ready.isUsable, isTrue);
    });

    test('ביטול הסכמה סוגר את ה-session ומחזיר ל-consentRequired', () async {
      installModelFiles(root);
      final backend = FakeBackend()..vectors = installedV30;
      final consent = FakeConsentStore();
      final repository = buildRepository(
        root: root,
        backend: backend,
        consent: consent,
      );
      await repository.ensureOpen();

      consent.set(SearchFeedbackConsent.declined);
      await waitFor(
        () =>
            repository.availability.phase ==
            SemanticAvailabilityPhase.consentRequired,
      );

      expect(backend.calls, contains('disable'));
      expect(
        repository.availability.phase,
        SemanticAvailabilityPhase.consentRequired,
      );
    });
  });

  group('פתיחה וחיפוש', () {
    test('לא נפתח עד השימוש הראשון, ונפתח פעם אחת בלבד', () async {
      installModelFiles(root);
      final backend = FakeBackend()..vectors = installedV30;
      final repository = buildRepository(root: root, backend: backend);

      await repository.refresh();
      expect(backend.calls, isNot(contains('open')));

      await repository.search(
        const SemanticSearchRequest(query: 'חסד', facets: ['/']),
      );
      await repository.search(
        const SemanticSearchRequest(query: 'אמת', facets: ['/']),
      );
      await pumpEventQueue();

      expect(backend.calls.where((c) => c == 'open'), hasLength(1));
      final open = backend.openRequests.single;
      expect(open.vectorsDir, paths().vectorsDirectory);
      expect(open.modelPath, paths().modelFile(SemanticQuantization.int8));
      expect(open.modelIdentityJson, bundledModelJson());
      expect(open.onnxRuntimePath, '/app/onnxruntime/onnxruntime.dll');
      expect(backend.calls, contains('search:$kSemanticWarmUpQuery'));
    });

    test('חיפוש חדש מבטל את הקודם, והמבוטל מחזיר null', () async {
      installModelFiles(root);
      final backend = FakeBackend()
        ..vectors = installedV30
        ..searchGate = Completer<void>();
      final repository = buildRepository(root: root, backend: backend);
      await repository.ensureOpen();

      final first = repository.search(
        const SemanticSearchRequest(query: 'ראשון', facets: ['/']),
      );
      await pumpEventQueue();
      final second = repository.search(
        const SemanticSearchRequest(query: 'שני', facets: ['/']),
      );
      await pumpEventQueue();
      backend.searchGate!.complete();

      expect(await first, isNull);
      expect(await second, isNotNull);
      final userHandles = backend.searchHandles.skip(1).toList();
      expect(userHandles.first.isCancelled, isTrue);
      expect(userHandles.last.isCancelled, isFalse);
    });

    test('בלי הסכמה החיפוש נכשל ב-consentRequired', () async {
      installModelFiles(root);
      final repository = buildRepository(
        root: root,
        backend: FakeBackend()..vectors = installedV30,
        consent: FakeConsentStore(SearchFeedbackConsent.unknown),
      );

      await expectLater(
        repository.search(const SemanticSearchRequest(query: 'א', facets: [])),
        throwsA(
          isA<SemanticFailure>().having(
            (f) => f.kind,
            'kind',
            SemanticFailureKind.consentRequired,
          ),
        ),
      );
    });

    test('כשל פתיחה מוצג כ-failed עם סוג הכשל', () async {
      installModelFiles(root);
      final backend = FakeBackend()
        ..vectors = installedV30
        ..openFailure = const SemanticFailure(
          SemanticFailureKind.onnxRuntimeMissing,
        );
      final repository = buildRepository(root: root, backend: backend);

      await expectLater(
        repository.ensureOpen(),
        throwsA(isA<SemanticFailure>()),
      );
      expect(repository.availability.phase, SemanticAvailabilityPhase.failed);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.onnxRuntimeMissing,
      );
    });

    test('תמונת המנוע לטלמטריה', () async {
      installModelFiles(root);
      final backend = FakeBackend()..vectors = installedV30;
      final repository = buildRepository(root: root, backend: backend);
      await repository.ensureOpen();

      final snapshot = await repository.engineSnapshot();

      expect(snapshot.state, 'ready');
      expect(snapshot.modelFamilyId, startsWith('ArieLLL123/'));
      expect(snapshot.modelQuantization, 'int8');
      expect(
        snapshot.modelPackageChecksum,
        '9e408407922b4aab26dd148cbe4b9a0e573c65591cfc799ba28e991d77d9d065',
      );
      expect(snapshot.embeddingDim, 256);
      expect(snapshot.vectorsReleaseTag, 'vectors-v30-20260930165019');
      expect(snapshot.vectorsLibraryVersion, 30);
      expect(snapshot.vectorSegments, 1);
    });
  });

  group('הורדה', () {
    test('עדכון ברקע לא מוריד דבר לפני הפעלה מפורשת', () async {
      final downloads = FakeDownloads();
      final locator = FakeLocator(releaseV30());
      final repository = buildRepository(
        root: root,
        download: downloads.call,
        locator: locator,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(downloads.urls, isEmpty);
      expect(locator.lookups, isEmpty);
    });

    test('הפעלה בלי הסכמה לא מורידה ולא מסמנת את הנתונים', () async {
      final downloads = FakeDownloads();
      final settings = FakeSettingsStore();
      final repository = buildRepository(
        root: root,
        download: downloads.call,
        settings: settings,
        consent: FakeConsentStore(SearchFeedbackConsent.declined),
      );

      await repository.enableAndDownload();

      expect(downloads.urls, isEmpty);
      expect(settings.dataEnabled, isFalse);
      expect(
        repository.availability.phase,
        SemanticAvailabilityPhase.consentRequired,
      );
    });

    test('הפעלה עם הסכמה מורידה מודל ווקטורים ומתקינה', () async {
      final downloads = FakeDownloads();
      final backend = FakeBackend();
      final settings = FakeSettingsStore();
      final repository = buildRepository(
        root: root,
        backend: backend,
        download: downloads.call,
        settings: settings,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(settings.dataEnabled, isTrue);
      expect(downloads.urls, [
        'https://models.test/meivin/seforim-embed-round2-int8.onnx',
        'https://models.test/meivin/tokenizer.json',
        'https://models.test/meivin/LICENSE',
        'https://models.test/meivin/model.json',
        'https://github.test/vectors/0',
      ]);
      expect(File(paths().licenseFile).existsSync(), isTrue);
      expect(await repository.readModelLicense(), 'x');
      expect(
        File(paths().modelFile(SemanticQuantization.int8)).existsSync(),
        isTrue,
      );
      expect(File(paths().identityFile).readAsStringSync(), bundledModelJson());
      final install = backend.installRequests.single;
      expect(install.vectorsDir, paths().vectorsDirectory);
      expect(
        install.segmentPath,
        p.join(
          paths().vectorsDownloadDirectory,
          'otzaria-vectors-0c3f95be-v30-base.oxv.zst',
        ),
      );
      expect(
        install.publishedManifestSha256,
        '3dc43c8c9164753959a7aec16d25a8c3e93a04f9139d85f20a72a5ae91b5c5b2',
      );
      expect(install.modelIdentityJson, bundledModelJson());
      expect(Directory(paths().vectorsDownloadDirectory).existsSync(), isFalse);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('אחרי הפעלה, עדכון ברקע מוריד רק כשגרסת הספרייה השתנתה', () async {
      installModelFiles(root);
      final downloads = FakeDownloads();
      final locator = FakeLocator(releaseV30());
      final settings = FakeSettingsStore()..dataEnabled = true;
      final backend = FakeBackend()..vectors = installedV30;
      final repository = buildRepository(
        root: root,
        backend: backend,
        download: downloads.call,
        locator: locator,
        settings: settings,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      expect(locator.lookups, isEmpty);

      settings.isOfflineMode = true;
      final offline = buildRepository(
        root: root,
        backend: FakeBackend(),
        download: downloads.call,
        locator: locator,
        settings: settings,
        libraryVersion: 31,
      );
      offline.scheduleVectorsUpdate();
      await offline.pendingJob;
      expect(locator.lookups, isEmpty);

      settings.isOfflineMode = false;
      final online = buildRepository(
        root: root,
        backend: FakeBackend()..vectors = installedV30,
        download: downloads.call,
        locator: locator,
        settings: settings,
        libraryVersion: 31,
      );
      online.scheduleVectorsUpdate();
      await online.pendingJob;
      expect(locator.lookups, [31]);
    });

    test('release שלא פורסם — vectorsNotPublished, בלי להוריד דבר', () async {
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(),
        download: downloads.call,
      );

      await repository.enableAndDownload();

      expect(downloads.urls, isEmpty);

      final availability = repository.availability;
      expect(availability.phase, SemanticAvailabilityPhase.vectorsNotPublished);
      expect(availability.unpublishedLibraryVersion, 30);
      expect(availability.failure, isNull);
    });

    test('checksum שגוי של המודל — failed(checksumMismatch)', () async {
      final service = CompanionAssetsService(
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes([1, 2, 3], 200),
        ),
      );
      final repository = buildRepository(
        root: root,
        download: service.downloadVerifiedFile,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(repository.availability.phase, SemanticAvailabilityPhase.failed);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.checksumMismatch,
      );
      expect(
        File(paths().modelFile(SemanticQuantization.int8)).existsSync(),
        isFalse,
      );
    });

    test('אין מקום בכונן — insufficientDiskSpace לפני ההורדה', () async {
      installModelFiles(root);
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        download: downloads.call,
        locator: FakeLocator(releaseV30()),
        freeBytes: 5,
      );

      await repository.enableAndDownload();

      expect(downloads.urls, isEmpty);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.insufficientDiskSpace,
      );
    });

    test('מצב לא מקוון בהפעלה — failed(offline)', () async {
      final repository = buildRepository(
        root: root,
        settings: FakeSettingsStore()..isOfflineMode = true,
      );

      await repository.enableAndDownload();

      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.offline,
      );
    });

    test('דיוק בלי release — לא מוצע, והבחירה חוזרת ל-int8', () async {
      final settings = FakeSettingsStore()
        ..quantization = SemanticQuantization.fp32;
      final repository = buildRepository(root: root, settings: settings);

      expect(repository.availableQuantizations, [SemanticQuantization.int8]);
      expect(repository.quantization, SemanticQuantization.int8);
      await repository.setQuantization(SemanticQuantization.fp32);
      expect(repository.quantization, SemanticQuantization.int8);
    });

    test('בלי release למודל — modelSourceNotConfigured', () async {
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
        modelReleases: const {
          SemanticQuantization.int8: null,
          SemanticQuantization.fp32: null,
        },
      );

      await repository.enableAndDownload();

      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.modelSourceNotConfigured,
      );
    });

    test('segment מפוצל מחובר לקובץ אחד לפני ההתקנה', () async {
      installModelFiles(root);
      final backend = FakeBackend();
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: FakeLocator(releaseV30(parts: 2)),
      );

      await repository.enableAndDownload();

      expect(
        p.basename(backend.installRequests.single.segmentPath),
        'otzaria-vectors-0c3f95be-v30-base.oxv.zst',
      );
    });

    test('מחיקת הנתונים מוחקת קבצים ומכבה את העדכון ברקע', () async {
      installModelFiles(root);
      File(p.join(paths().vectorsDirectory, 'CURRENT'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      final settings = FakeSettingsStore()..dataEnabled = true;
      final repository = buildRepository(root: root, settings: settings);

      await repository.removeData();

      expect(settings.dataEnabled, isFalse);
      expect(Directory(paths().modelDirectory).existsSync(), isFalse);
      expect(Directory(paths().vectorsDirectory).existsSync(), isFalse);
      expect(
        repository.availability.phase,
        SemanticAvailabilityPhase.needsDownload,
      );
    });
  });

  group('סבב תיקונים', () {
    test('מחיקה אינה נוגעת בתיקיית vectors זרה', () async {
      installModelFiles(root);
      final foreign = File(p.join(paths().vectorsDirectory, 'notes.txt'))
        ..createSync(recursive: true);
      final repository = buildRepository(root: root);

      await repository.removeData();

      expect(foreign.existsSync(), isTrue);
      expect(Directory(paths().modelDirectory).existsSync(), isFalse);
    });

    test('לא מתקינים לתוך תיקיית vectors זרה', () async {
      installModelFiles(root);
      File(
        p.join(paths().vectorsDirectory, 'notes.txt'),
      ).createSync(recursive: true);
      final backend = FakeBackend();
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(backend.installRequests, isEmpty);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.internal,
      );
    });

    test('vectorsBusy — בלי כשל, וניסיון חוזר מעצמו', () async {
      installModelFiles(root);
      final backend = FakeBackend()
        ..installFailures.add(
          const SemanticFailure(
            SemanticFailureKind.vectorsBusy,
            'busy',
            'vectors_dir',
          ),
        );
      final repository = buildRepository(
        root: root,
        backend: backend,
        settings: FakeSettingsStore()..dataEnabled = true,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();
      expect(repository.availability.failure, isNull);

      await waitFor(() => backend.installRequests.length == 2);
      await repository.pendingJob;
      expect(backend.installRequests, hasLength(2));
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('פרסום חוזר (segment_id) — נרשם ולא מורד שוב', () async {
      installModelFiles(root);
      final downloads = FakeDownloads();
      final settings = FakeSettingsStore()..dataEnabled = true;
      const installedV29 = SemanticVectorsSummary(
        present: true,
        libraryVersion: 29,
        libraryReleaseTag: 'v29-20260927072953',
      );
      final backend = FakeBackend()
        ..vectors = installedV29
        ..installFailures.add(
          const SemanticFailure(
            SemanticFailureKind.artifactIncompatible,
            'segment f834 is installed with other bytes',
            'segment_id',
          ),
        );
      final repository = buildRepository(
        root: root,
        backend: backend,
        settings: settings,
        download: downloads.call,
        locator: FakeLocator(releaseV30()),
      );

      await repository.enableAndDownload();

      expect(settings.skippedVectorsRelease, 'vectors-v30-20260930165019');
      expect(repository.availability.failure, isNull);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
      final before = downloads.urls.length;

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      expect(downloads.urls.length, before);
    });

    test('סט פגום: סוגרים את ה-session ומתקינים שוב את אותו release', () async {
      installModelFiles(root);
      final backend = FakeBackend()..vectors = installedV30;
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: FakeLocator(releaseV30()),
      );
      await repository.ensureOpen();
      backend.vectorsInfoFailure = const SemanticFailure(
        SemanticFailureKind.artifactCorrupt,
      );

      await repository.refresh();
      expect(repository.availability.phase, SemanticAvailabilityPhase.failed);

      await repository.enableAndDownload();

      expect(backend.calls, containsAllInOrder(['disable', 'install']));
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('בקשת משתמש שמצטרפת לעבודה ברקע מקבלת את הכשל', () async {
      installModelFiles(root);
      final gate = Completer<void>();
      final downloads = FakeDownloads()
        ..gate = gate
        ..error = const SocketException('offline');
      final repository = buildRepository(
        root: root,
        settings: FakeSettingsStore()..dataEnabled = true,
        download: downloads.call,
        locator: FakeLocator(releaseV30()),
      );

      repository.scheduleVectorsUpdate();
      await waitFor(() => downloads.lastIsCancelled != null);
      final joined = repository.enableAndDownload();
      gate.complete();
      await joined;

      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.network,
      );
    });

    test('עצירה ידנית: עדכון ספרייה לא מחדש, ורק בקשה מפורשת', () async {
      installModelFiles(root);
      final settings = FakeSettingsStore()..dataEnabled = true;
      final gate = Completer<void>();
      final downloads = FakeDownloads()..gate = gate;
      final locator = FakeLocator(releaseV30());
      final repository = buildRepository(
        root: root,
        settings: settings,
        download: downloads.call,
        locator: locator,
      );

      final job = repository.enableAndDownload();
      await waitFor(() => downloads.lastIsCancelled != null);
      await repository.cancelDownload();
      expect(downloads.lastIsCancelled!(), isTrue);
      gate.complete();
      await job;
      expect(settings.downloadPaused, isTrue);
      expect(repository.availability.pausedByUser, isTrue);

      final lookups = locator.lookups.length;
      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      expect(locator.lookups.length, lookups);

      await repository.enableAndDownload();
      expect(settings.downloadPaused, isFalse);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('ביטול הסכמה באמצע הורדה עוצר אותה', () async {
      installModelFiles(root);
      final consent = FakeConsentStore();
      final gate = Completer<void>();
      final downloads = FakeDownloads()..gate = gate;
      final repository = buildRepository(
        root: root,
        consent: consent,
        download: downloads.call,
        locator: FakeLocator(releaseV30()),
      );
      await repository.refresh();

      final job = repository.enableAndDownload();
      await waitFor(() => downloads.lastIsCancelled != null);
      consent.set(SearchFeedbackConsent.declined);
      await pumpEventQueue();

      expect(downloads.lastIsCancelled!(), isTrue);
      gate.complete();
      await job;
    });

    test('ביטול הסכמה מבטל גם את חיפוש החימום', () async {
      installModelFiles(root);
      final consent = FakeConsentStore();
      final backend = FakeBackend()
        ..vectors = installedV30
        ..warmUpGate = Completer<void>();
      final repository = buildRepository(
        root: root,
        backend: backend,
        consent: consent,
      );
      await repository.ensureOpen();
      final warmUp = backend.searchHandles.single;

      consent.set(SearchFeedbackConsent.declined);
      await pumpEventQueue();

      expect(warmUp.isCancelled, isTrue);
      backend.warmUpGate!.complete();
    });

    test('חלון משני: לא מוריד ולא מוחק, ומדווח על כך', () async {
      final downloads = FakeDownloads();
      final settings = FakeSettingsStore()..dataEnabled = true;
      final repository = buildRepository(
        root: root,
        download: downloads.call,
        settings: settings,
        locator: FakeLocator(releaseV30()),
        secondaryWindow: true,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      await repository.enableAndDownload();
      await repository.removeData();

      expect(downloads.urls, isEmpty);
      expect(settings.dataEnabled, isTrue);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.secondaryWindow,
      );
      expect(repository.availability.isSecondaryWindow, isTrue);
    });

    test('בזמן העברת ספרייה לא מתחילות הורדות', () async {
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        download: downloads.call,
        settings: FakeSettingsStore()..dataEnabled = true,
        locator: FakeLocator(releaseV30()),
      );

      await repository.releaseForLibraryMove();
      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      await repository.enableAndDownload();
      expect(downloads.urls, isEmpty);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.libraryMoving,
      );

      repository.finishLibraryMove();
      await repository.enableAndDownload();
      expect(downloads.urls, isNotEmpty);
    });

    test('תג הספרייה מה-updater מגיע למאתר', () async {
      installModelFiles(root);
      final locator = FakeLocator();
      final repository = buildRepository(
        root: root,
        settings: FakeSettingsStore()..dataEnabled = true,
        locator: locator,
      );

      repository.scheduleVectorsUpdate(libraryTag: 'v30-20260930165019');
      await repository.pendingJob;

      expect(locator.tags, ['v30-20260930165019']);
    });
  });
}
