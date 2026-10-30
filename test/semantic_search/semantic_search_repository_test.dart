import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/library_update/services/companion_assets_service.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_model_identity.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_family.dart';
import 'package:otzaria/semantic_search/models/semantic_vectors_release.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/repository/semantic_download_client.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show PatchDownloadException;

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

    test('מנוע שאיבד את ה-session (פתיחה מחדש של האינדקס) נפתח שוב', () async {
      installModelFiles(root);
      final backend = FakeBackend()..vectors = installedV30;
      final repository = buildRepository(root: root, backend: backend);
      await repository.ensureOpen();
      await pumpEventQueue();

      backend.statusValue = const SemanticBackendStatus(
        state: SemanticBackendState.notConfigured,
        rawState: 'notConfigured',
      );
      await repository.search(
        const SemanticSearchRequest(query: 'חסד', facets: ['/']),
      );

      expect(backend.calls.where((c) => c == 'open'), hasLength(2));
      expect(backend.calls, contains('search:חסד'));
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
      // השני חייב להגיע כשהראשון כבר במנוע; בעומס ensureOpen מתעכב והראשון
      // היה מבוטל לפני שהגיע אליו.
      while (backend.searchHandles.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
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

  group('משפחת החלונות', () {
    const anchorDigest =
        '0c3f95be734d4a5d80abafe1bd5be0a9dccfab82c86a5961e84ad71a83a62c6a';
    final windowsDigest = 'ab' * 32;
    final installedAnchorV30 = SemanticVectorsSummary(
      present: true,
      identityDigest: anchorDigest,
      libraryVersion: 30,
      libraryReleaseTag: installedV30.libraryReleaseTag,
      segments: installedV30.segments,
    );

    Future<int> chunkingOf(SemanticVectorsFamily family) async =>
        SemanticModelIdentity.parse(bundledModelJson(family)).chunkingIdentity;

    File windowsMarker() => File(
      p.join(paths().vectorsDirectory, kSemanticWindowsIdentityFileName),
    );

    SemanticVectorsRelease windowsRelease(int chunking) => releaseV30(
      family: SemanticVectorsFamily.windows,
      identityDigest: windowsDigest,
      chunkingIdentity: chunking,
    );

    test('מנוע בלי חלונות מתקין את הישנה בלי לקרוא את נכס החלונות', () async {
      installModelFiles(root);
      final locator = FakeLocator(releaseV30());
      final backend = FakeBackend()..vectors = installedAnchorV30;
      final repository = buildRepository(
        root: root,
        backend: backend,
        settings: FakeSettingsStore()..dataEnabled = true,
        locator: locator,
        libraryVersion: 31,
        identityLoader: (family) async => family == SemanticVectorsFamily.anchor
            ? bundledModelJson()
            : throw StateError('windows identity read'),
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(locator.candidates.single, [
        (
          family: SemanticVectorsFamily.anchor,
          chunkingIdentity: await chunkingOf(SemanticVectorsFamily.anchor),
        ),
      ]);
      expect(
        backend.installRequests.single.modelIdentityJson,
        bundledModelJson(),
      );
      expect(windowsMarker().existsSync(), isFalse);
    });

    test(
      'סט ישן מוחלף בסט החלונות: ה-session נסגר, והפתיחה בזהות החדשה',
      () async {
        installModelFiles(root);
        final locator = FakeLocator(
          windowsRelease(await chunkingOf(SemanticVectorsFamily.windows)),
        );
        final backend = FakeBackend()
          ..supportsLongLineWindows = true
          ..vectors = installedAnchorV30
          ..installedIdentityDigest = windowsDigest;
        final repository = buildRepository(
          root: root,
          backend: backend,
          settings: FakeSettingsStore()..dataEnabled = true,
          locator: locator,
        );
        await repository.ensureOpen();
        expect(
          backend.openRequests.single.modelIdentityJson,
          bundledModelJson(),
        );

        repository.scheduleVectorsUpdate();
        await repository.pendingJob;

        expect(locator.candidates.single.map((c) => c.family), [
          SemanticVectorsFamily.windows,
          SemanticVectorsFamily.anchor,
        ]);
        expect(
          backend.installRequests.single.modelIdentityJson,
          bundledModelJson(SemanticVectorsFamily.windows),
        );
        final disable = backend.calls.lastIndexOf('disable');
        expect(disable, isNonNegative);
        expect(disable, lessThan(backend.calls.indexOf('install')));
        expect(windowsMarker().readAsStringSync(), windowsDigest);

        repository.scheduleVectorsUpdate();
        await repository.pendingJob;
        expect(locator.lookups, hasLength(1));

        await repository.ensureOpen();
        expect(
          backend.openRequests.last.modelIdentityJson,
          bundledModelJson(SemanticVectorsFamily.windows),
        );
        expect(
          (await repository.engineSnapshot()).vectorsReleaseTag,
          'vectors-windows-v30-20260930165019',
        );
      },
    );

    test('הסימון נכתב לפני ההתקנה: קריסה אחריה פותחת בזהות החלונות', () async {
      installModelFiles(root);
      final backend = FakeBackend()
        ..supportsLongLineWindows = true
        ..installFailures.add(
          const SemanticFailure(SemanticFailureKind.internal, 'crashed'),
        );
      final repository = buildRepository(
        root: root,
        backend: backend,
        locator: FakeLocator(
          windowsRelease(await chunkingOf(SemanticVectorsFamily.windows)),
        ),
      );
      await repository.enableAndDownload();
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.internal,
      );

      // ההתקנה עצמה הושלמה, והתהליך נפל לפני שהמאגר המשיך.
      final reopened = FakeBackend()
        ..supportsLongLineWindows = true
        ..vectors = SemanticVectorsSummary(
          present: true,
          identityDigest: windowsDigest,
          libraryVersion: 30,
          libraryReleaseTag: installedV30.libraryReleaseTag,
          segments: installedV30.segments,
        );
      await buildRepository(
        root: root,
        backend: reopened,
        settings: FakeSettingsStore(),
      ).ensureOpen();
      expect(
        reopened.openRequests.single.modelIdentityJson,
        bundledModelJson(SemanticVectorsFamily.windows),
      );
    });

    test('סט חלונות קיים אינו מוחלף בסט הישן של גרסה חדשה', () async {
      installModelFiles(root);
      windowsMarker()
        ..createSync(recursive: true)
        ..writeAsStringSync(windowsDigest);
      final downloads = FakeDownloads();
      final locator = FakeLocator(releaseV30());
      final backend = FakeBackend()
        ..supportsLongLineWindows = true
        ..vectors = SemanticVectorsSummary(
          present: true,
          identityDigest: windowsDigest,
          libraryVersion: 30,
          libraryReleaseTag: installedV30.libraryReleaseTag,
          segments: installedV30.segments,
        );
      final repository = buildRepository(
        root: root,
        backend: backend,
        settings: FakeSettingsStore()..dataEnabled = true,
        download: downloads.call,
        locator: locator,
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(locator.candidates.single.map((c) => c.family), [
        SemanticVectorsFamily.windows,
      ]);
      expect(downloads.urls, isEmpty);
      expect(backend.installRequests, isEmpty);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('סט חלונות שלא פורסם: הסט הישן באותה גרסה נשאר בלי הורדה', () async {
      installModelFiles(root);
      final downloads = FakeDownloads();
      final backend = FakeBackend()
        ..supportsLongLineWindows = true
        ..vectors = installedAnchorV30;
      final repository = buildRepository(
        root: root,
        backend: backend,
        settings: FakeSettingsStore()..dataEnabled = true,
        download: downloads.call,
        locator: FakeLocator(
          releaseV30(
            identityDigest: anchorDigest,
            chunkingIdentity: await chunkingOf(SemanticVectorsFamily.anchor),
          ),
        ),
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(downloads.urls, isEmpty);
      expect(backend.installRequests, isEmpty);
      await repository.ensureOpen();
      expect(
        backend.openRequests.single.modelIdentityJson,
        bundledModelJson(),
      );
    });

    test('chunking שהמנוע דוחה בהתקנה — נרשם ולא מורד שוב', () async {
      installModelFiles(root);
      final downloads = FakeDownloads();
      final settings = FakeSettingsStore()..dataEnabled = true;
      final backend = FakeBackend()
        ..vectors = installedAnchorV30
        ..installFailures.add(
          const SemanticFailure(
            SemanticFailureKind.artifactIncompatible,
            'this build resolves lines under another chunking',
            'model.chunking_identity',
          ),
        );
      final repository = buildRepository(
        root: root,
        backend: backend,
        settings: settings,
        download: downloads.call,
        locator: FakeLocator(releaseV30()),
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      expect(settings.skippedVectorsRelease, 'vectors-v30-20260930165019');
      final before = downloads.urls.length;

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
      expect(downloads.urls.length, before);
    });

    for (final field in [
      'store.store_format_version',
      'store.vector_precision',
    ]) {
      test('$field שהמנוע אינו קורא — נרשם ולא מורד שוב', () async {
        installModelFiles(root);
        final downloads = FakeDownloads();
        final settings = FakeSettingsStore()..dataEnabled = true;
        final backend = FakeBackend()
          ..vectors = installedAnchorV30
          ..installFailures.add(
            SemanticFailure(
              SemanticFailureKind.artifactIncompatible,
              'this build reads another store',
              field,
            ),
          );
        final repository = buildRepository(
          root: root,
          backend: backend,
          settings: settings,
          download: downloads.call,
          locator: FakeLocator(releaseV30()),
          libraryVersion: 31,
        );

        repository.scheduleVectorsUpdate();
        await repository.pendingJob;
        expect(settings.skippedVectorsRelease, 'vectors-v30-20260930165019');
        final before = downloads.urls.length;

        repository.scheduleVectorsUpdate();
        await repository.pendingJob;
        expect(downloads.urls.length, before);
        expect(backend.installRequests, hasLength(1));
      });
    }
  });

  group('deltas של משפחת החלונות', () {
    final digest = 'ab' * 32;
    late int chunking;
    late FakeBackend backend;
    late FakeDownloads downloads;
    late FakeLocator locator;
    late FakeSettingsStore settings;
    late SemanticSearchRepository repository;

    setUp(() {
      chunking = SemanticModelIdentity.parse(
        bundledModelJson(SemanticVectorsFamily.windows),
      ).chunkingIdentity;
      installModelFiles(root);
      markInstalledWindowsSet(root, digest);
      backend = FakeBackend()
        ..supportsLongLineWindows = true
        ..installedIdentityDigest = digest
        ..vectors = SemanticVectorsSummary(
          present: true,
          identityDigest: digest,
          libraryVersion: 28,
          libraryReleaseTag: 'v28-20260930165019',
        );
      downloads = FakeDownloads();
      locator = FakeLocator(
        releaseV30(
          family: SemanticVectorsFamily.windows,
          identityDigest: digest,
          chunkingIdentity: chunking,
        ),
      );
      settings = FakeSettingsStore()..dataEnabled = true;
      repository = buildRepository(
        root: root,
        backend: backend,
        settings: settings,
        download: downloads.call,
        locator: locator,
      );
    });

    List<SemanticVectorsRelease> chainTo30() => [
      deltaRelease(28, 29, identityDigest: digest, chunkingIdentity: chunking),
      deltaRelease(29, 30, identityDigest: digest, chunkingIdentity: chunking),
    ];

    SemanticInstallSummary delta(
      int version, {
      bool alreadyApplied = false,
      bool needsCompaction = false,
    }) => SemanticInstallSummary(
      kind: 'delta',
      libraryVersion: version,
      segments: 2,
      bytesOnDisk: 20,
      needsCompaction: needsCompaction,
      alreadyApplied: alreadyApplied,
    );

    Future<void> update() async {
      repository.scheduleVectorsUpdate();
      await repository.pendingJob;
    }

    test('שרשרת: מורידים ומתקינים רק את ה-deltas, לפי הסדר', () async {
      locator.chain = chainTo30();
      backend.installResults.addAll([delta(29), delta(30)]);

      await update();

      expect(locator.chainLookups.single.installedVersion, 28);
      expect(downloads.urls, [
        'https://github.test/delta/28-29',
        'https://github.test/delta/29-30',
      ]);
      expect(backend.installRequests.map((r) => r.manifestJson), [
        for (final release in chainTo30()) release.manifestJson,
      ]);
      expect(backend.vectors.libraryVersion, 30);
      expect(settings.skippedVectorsRelease, isNull);
      expect(Directory(paths().vectorsDownloadDirectory).existsSync(), isFalse);
      expect(backend.calls, isNot(contains('compact')));
    });

    test('בלי שרשרת — ה-base', () async {
      await update();

      expect(locator.chainLookups, hasLength(1));
      expect(downloads.urls, ['https://github.test/vectors/0']);
      expect(backend.installRequests.single.manifestJson, '{"kind":"base"}');
    });

    test('delta שכבר הוחל — ממשיכים לבא', () async {
      locator.chain = chainTo30();
      backend.installResults.addAll([
        delta(29, alreadyApplied: true),
        delta(30),
      ]);

      await repository.enableAndDownload();

      // אינו כשל ואינו נפילה ל-base: הצעד הבא בשרשרת מותקן.
      expect(backend.installRequests.map((r) => r.manifestJson), [
        for (final release in chainTo30()) release.manifestJson,
      ]);
      expect(downloads.urls, isNot(contains('https://github.test/vectors/0')));
      expect(repository.availability.failure, isNull);
      expect(backend.vectors.libraryVersion, 30);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    for (final field in [
      'delta.from_library_version',
      'delta.identity',
      'delta.codec_params',
      'store.store_format_version',
    ]) {
      test('$field — נופלים ל-base, בלי לדלג על ה-release', () async {
        locator.chain = chainTo30();
        backend.installFailures.add(
          SemanticFailure(
            SemanticFailureKind.artifactIncompatible,
            'delta does not follow the set',
            field,
          ),
        );

        await update();

        expect(downloads.urls, [
          'https://github.test/delta/28-29',
          'https://github.test/vectors/0',
        ]);
        expect(backend.installRequests.last.manifestJson, '{"kind":"base"}');
        expect(settings.skippedVectorsRelease, isNull);
        expect(backend.vectors.libraryVersion, 30);
        expect(repository.availability.failure, isNull);
      });
    }

    test('delta פגום — base, וגם העבודה הבאה אינה חוזרת לשרשרת', () async {
      locator.chain = chainTo30();
      backend.installFailures.add(
        const SemanticFailure(SemanticFailureKind.artifactCorrupt),
      );

      await update();

      expect(downloads.urls, [
        'https://github.test/delta/28-29',
        'https://github.test/vectors/0',
      ]);
      expect(backend.installRequests.last.manifestJson, '{"kind":"base"}');
      expect(settings.skippedVectorsRelease, isNull);

      // הסט חזר ל-v28 (למשל שחזור הדור הקודם): שוב base, בלי השרשרת.
      backend.vectors = SemanticVectorsSummary(
        present: true,
        identityDigest: digest,
        libraryVersion: 28,
        libraryReleaseTag: 'v28-20260930165019',
      );
      downloads.urls.clear();
      await update();

      expect(locator.chainLookups, hasLength(1));
      expect(downloads.urls, ['https://github.test/vectors/0']);
    });

    test('SHA שגוי בהורדת delta — base', () async {
      locator.chain = chainTo30();
      final urls = <String>[];
      repository = buildRepository(
        root: root,
        backend: backend,
        settings: settings,
        locator: locator,
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
              urls.add(url);
              if (url.contains('/delta/')) {
                throw PatchDownloadException('sha mismatch');
              }
              await File(destPath).create(recursive: true);
            },
      );

      await update();

      expect(urls, [
        'https://github.test/delta/28-29',
        'https://github.test/vectors/0',
      ]);
      expect(backend.installRequests.single.manifestJson, '{"kind":"base"}');
    });

    test('כשל רשת בהורדת delta אינו מוריד base', () async {
      locator.chain = chainTo30();
      downloads.error = const SocketException('offline');

      await repository.enableAndDownload();

      expect(downloads.urls, ['https://github.test/delta/28-29']);
      expect(backend.installRequests, isEmpty);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.network,
      );
    });

    for (final (status, headers) in [
      (408, <String, String>{}),
      (429, <String, String>{}),
      (429, {'retry-after': '60'}),
      (403, {'x-ratelimit-remaining': '0'}),
      (502, <String, String>{}),
      (503, <String, String>{}),
    ]) {
      test('HTTP $status $headers בהורדת delta אינו מוריד base', () async {
        locator.chain = chainTo30();
        final urls = <String>[];
        var responseCancelled = false;
        final responseBody = StreamController<List<int>>(
          onCancel: () => responseCancelled = true,
        );
        repository = buildRepository(
          root: root,
          backend: backend,
          settings: settings,
          locator: locator,
          download: CompanionAssetsService(
            clientFactory: () => SemanticDownloadClient(
              MockClient.streaming((request, _) async {
                urls.add(request.url.toString());
                return http.StreamedResponse(
                  responseBody.stream,
                  status,
                  headers: headers,
                );
              }),
            ),
          ).downloadVerifiedFile,
        );

        await repository.enableAndDownload();

        expect(urls, ['https://github.test/delta/28-29']);
        expect(responseCancelled, isTrue);
        await responseBody.close();
        expect(backend.installRequests, isEmpty);
        expect(
          repository.availability.failure?.kind,
          status == 429 || status == 403
              ? SemanticFailureKind.rateLimited
              : SemanticFailureKind.network,
        );
      });
    }

    test('התקדמות השרשרת אינה חוזרת אחורה', () async {
      locator.chain = chainTo30();
      backend.installResults.addAll([delta(29), delta(30)]);
      final seen = <double>[];
      final sub = repository.availabilityChanges.listen((availability) {
        final fraction = availability.progress?.fraction;
        if (fraction != null) seen.add(fraction);
      });

      await repository.enableAndDownload();
      await sub.cancel();

      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
      }
      expect(seen.last, 1.0);
    });

    test('המקום בכונן נבדק לכל השרשרת', () async {
      locator.chain = chainTo30();
      repository = buildRepository(
        root: root,
        backend: backend,
        settings: settings,
        download: downloads.call,
        locator: locator,
        freeBytes: 11,
      );

      await repository.enableAndDownload();

      // שתי הורדות של בית ושני segments של 5.
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.insufficientDiskSpace,
      );
      expect(downloads.urls, isEmpty);
    });

    test('סט של זהות אחרת או של המשפחה הישנה — בלי חיפוש שרשרת', () async {
      backend.vectors = SemanticVectorsSummary(
        present: true,
        identityDigest: 'ee' * 32,
        libraryVersion: 28,
        libraryReleaseTag: 'v28-20260930165019',
      );
      locator.chain = chainTo30();

      await update();

      expect(locator.chainLookups, isEmpty);
      expect(downloads.urls, ['https://github.test/vectors/0']);
    });

    test('איחוד אוטומטי שומר רשומות: גרסת המסד אינה גרסת האינדקס', () async {
      locator.chain = chainTo30();
      backend.installResults.addAll([
        delta(29),
        delta(30, needsCompaction: true),
      ]);

      await update();
      await waitFor(() => backend.vectors.needsCompaction == false);

      expect(backend.compactVersions, [null]);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('איחוד שנתקל ב-vectorsBusy מנסה שוב מאוחר יותר', () async {
      locator.chain = chainTo30();
      backend
        ..installResults.addAll([delta(29), delta(30, needsCompaction: true)])
        ..compactFailures.add(
          const SemanticFailure(SemanticFailureKind.vectorsBusy),
        );

      await update();
      await waitFor(() => backend.compactVersions.length >= 2);

      expect(backend.compactVersions, [null, null]);
      expect(backend.vectors.needsCompaction, isFalse);
      expect(repository.availability.failure, isNull);
    });

    test('ביטול בזמן המתנה לאיחוד אינו מחדש כתיבה בתיקיית ההורדות', () async {
      final gate = Completer<void>();
      locator.chain = chainTo30();
      backend
        ..installResults.addAll([delta(29), delta(30, needsCompaction: true)])
        ..compactGate = gate;
      await update();
      await waitFor(() => backend.compactHandles.isNotEmpty);
      backend.vectors = SemanticVectorsSummary(
        present: true,
        identityDigest: digest,
        libraryVersion: 28,
      );
      downloads.urls.clear();

      repository.scheduleVectorsUpdate();
      await waitFor(() => backend.compactHandles.single.isCancelled);
      await repository.cancelDownload();
      gate.complete();
      await repository.pendingJob;

      expect(downloads.urls, isEmpty);
      expect(Directory(paths().vectorsDownloadDirectory).existsSync(), isFalse);
    });

    test('מחיקת הנתונים מבטלת איחוד שרץ וממתינה לו', () async {
      final gate = Completer<void>();
      locator.chain = chainTo30();
      backend
        ..installResults.addAll([delta(29), delta(30, needsCompaction: true)])
        ..compactGate = gate;

      await update();
      await waitFor(() => backend.compactHandles.isNotEmpty);
      var removed = false;
      final removing = repository.removeData().then((_) => removed = true);
      await pumpEventQueue();
      expect(backend.compactHandles.single.isCancelled, isTrue);
      expect(removed, isFalse);
      gate.complete();
      await removing;

      expect(settings.dataEnabled, isFalse);
    });
  });

  group('התקדמות כוללת', () {
    Future<List<SemanticDownloadProgress>> runJob(
      SemanticSearchRepository repository,
    ) async {
      final seen = <SemanticDownloadProgress>[];
      final sub = repository.availabilityChanges.listen((availability) {
        final progress = availability.progress;
        if (progress != null) seen.add(progress);
      });
      await repository.enableAndDownload();
      await sub.cancel();
      return seen;
    }

    test('אחוז אחד שאינו מתאפס בין רכיב החיפוש, הנתונים וההתקנה', () async {
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
      );

      final seen = await runJob(repository);

      final fractions = seen.map((p) => p.fraction!).toList();
      for (var i = 1; i < fractions.length; i++) {
        expect(fractions[i], greaterThanOrEqualTo(fractions[i - 1]));
      }
      expect(fractions.last, 1.0);
      final steps = {for (final p in seen) p.item: (p.step, p.stepCount)};
      expect(steps, {
        SemanticDownloadItem.model: (1, 3),
        SemanticDownloadItem.vectors: (2, 3),
        SemanticDownloadItem.install: (3, 3),
      });
      final model = testModelReleases[SemanticQuantization.int8]!;
      expect(seen.first.totalBytes, model.downloadSize + 1);
      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
    });

    test('רכיב חיפוש שכבר הורד אינו נספר כשלב', () async {
      installModelFiles(root);
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
      );

      final seen = await runJob(repository);

      expect(
        seen.map((p) => p.item),
        isNot(contains(SemanticDownloadItem.model)),
      );
      final steps = {for (final p in seen) p.item: (p.step, p.stepCount)};
      expect(steps, {
        SemanticDownloadItem.vectors: (1, 2),
        SemanticDownloadItem.install: (2, 2),
      });
      expect(seen.first.totalBytes, 1);
    });

    test('סגירת ה-bloc (סגירת הדיאלוג) אינה מבטלת את ההורדה', () async {
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
      );
      final bloc = SemanticSearchBloc(repository: repository);

      bloc.add(const SemanticDownloadRequested());
      await waitFor(
        () =>
            repository.availability.phase ==
            SemanticAvailabilityPhase.downloading,
      );
      await bloc.close();
      await repository.pendingJob;

      expect(repository.availability.phase, SemanticAvailabilityPhase.ready);
      expect(repository.availability.pausedByUser, isFalse);
    });
  });
}
