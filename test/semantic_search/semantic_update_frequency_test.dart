import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_update_frequency.dart';
import 'package:otzaria/semantic_search/services/semantic_data_failure_log.dart';

import 'semantic_test_support.dart';

void main() {
  group('isSemanticRoutineUpdateDue', () {
    final now = DateTime.utc(2026, 11, 11);

    test('עם הספרייה תמיד, ידני אף פעם', () {
      expect(
        isSemanticRoutineUpdateDue(
          frequency: SemanticUpdateFrequency.withLibrary,
          lastUpdate: now,
          now: now,
        ),
        isTrue,
      );
      expect(
        isSemanticRoutineUpdateDue(
          frequency: SemanticUpdateFrequency.manual,
          lastUpdate: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('פעם בחודש: לפני 30 יום לא, אחריהם כן, ובלי מועד ידוע כן', () {
      bool due(DateTime? last) => isSemanticRoutineUpdateDue(
        frequency: SemanticUpdateFrequency.monthly,
        lastUpdate: last,
        now: now,
      );
      expect(due(now.subtract(const Duration(days: 29))), isFalse);
      expect(due(now.subtract(const Duration(days: 30))), isTrue);
      expect(due(null), isTrue);
      // שעון שהוזז אחורה לא חוסם לתמיד.
      expect(due(now.add(const Duration(days: 3))), isTrue);
    });

    test('ערך שמור לא מוכר נופל לברירת המחדל', () {
      expect(
        SemanticUpdateFrequency.fromStorage('weekly'),
        SemanticUpdateFrequency.withLibrary,
      );
      expect(
        SemanticUpdateFrequency.fromStorage('manual'),
        SemanticUpdateFrequency.manual,
      );
    });
  });

  group('עדכון רקע לפי התדירות', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('semantic_freq_'));
    tearDown(() async {
      for (var attempt = 0; attempt < 5 && root.existsSync(); attempt++) {
        try {
          root.deleteSync(recursive: true);
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });

    /// סט v30 מותקן, והספרייה כבר בגרסה 31.
    ({FakeLocator locator, FakeSettingsStore settings, FakeBackend backend})
    installedBehindLibrary(SemanticUpdateFrequency frequency) {
      installModelFiles(root);
      final settings = FakeSettingsStore()
        ..dataEnabled = true
        ..updateFrequency = frequency;
      final backend = FakeBackend()..vectors = installedV30;
      return (locator: FakeLocator(), settings: settings, backend: backend);
    }

    test('ידני: עדכון ספרייה לא מחפש וקטורים חדשים', () async {
      final f = installedBehindLibrary(SemanticUpdateFrequency.manual);
      final repository = buildRepository(
        root: root,
        locator: f.locator,
        settings: f.settings,
        backend: f.backend,
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(f.locator.lookups, isEmpty);
    });

    test('ידני: "בדוק עדכון" מחפש בכל זאת', () async {
      final f = installedBehindLibrary(SemanticUpdateFrequency.manual);
      final repository = buildRepository(
        root: root,
        locator: f.locator,
        settings: f.settings,
        backend: f.backend,
        libraryVersion: 31,
      );

      await repository.enableAndDownload();

      expect(f.locator.lookups, [31]);
    });

    test('פעם בחודש: אחרי עדכון מלפני שבוע לא מחפש', () async {
      final f = installedBehindLibrary(SemanticUpdateFrequency.monthly);
      f.settings.lastVectorsUpdate = DateTime.now().subtract(
        const Duration(days: 7),
      );
      final repository = buildRepository(
        root: root,
        locator: f.locator,
        settings: f.settings,
        backend: f.backend,
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(f.locator.lookups, isEmpty);
    });

    test('פעם בחודש: אחרי עדכון מלפני חודשיים מחפש', () async {
      final f = installedBehindLibrary(SemanticUpdateFrequency.monthly);
      f.settings.lastVectorsUpdate = DateTime.now().subtract(
        const Duration(days: 60),
      );
      final repository = buildRepository(
        root: root,
        locator: f.locator,
        settings: f.settings,
        backend: f.backend,
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(f.locator.lookups, [31]);
    });

    test('ידני: רכיב חיפוש חסר יורד, אבל לא הווקטורים', () async {
      final settings = FakeSettingsStore()
        ..dataEnabled = true
        ..updateFrequency = SemanticUpdateFrequency.manual;
      final locator = FakeLocator();
      final downloads = FakeDownloads();
      final repository = buildRepository(
        root: root,
        locator: locator,
        settings: settings,
        download: downloads.call,
        backend: FakeBackend()..vectors = installedV30,
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(locator.lookups, isEmpty);
      expect(downloads.urls, isNotEmpty);
      expect(
        downloads.urls.every((u) => u.startsWith('https://models.test/')),
        isTrue,
      );
    });

    test('ידני לא חוסם תיקון של סט פגום', () async {
      final f = installedBehindLibrary(SemanticUpdateFrequency.manual);
      f.backend.vectorsInfoFailure = const SemanticFailure(
        SemanticFailureKind.artifactCorrupt,
      );
      final repository = buildRepository(
        root: root,
        locator: f.locator,
        settings: f.settings,
        backend: f.backend,
        libraryVersion: 31,
      );

      repository.scheduleVectorsUpdate();
      await repository.pendingJob;

      expect(f.locator.lookups, [31]);
    });

    test('התקנה מוצלחת רושמת את מועד העדכון', () async {
      final settings = FakeSettingsStore();
      final repository = buildRepository(
        root: root,
        locator: FakeLocator(releaseV30()),
        settings: settings,
      );

      await repository.enableAndDownload();

      expect(
        repository.availability.phase,
        SemanticAvailabilityPhase.ready,
      );
      expect(settings.lastVectorsUpdate, isNotNull);
    });
  });

  group('רכיב ההרצה חסר', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('semantic_ort_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('נכשל לפני ההורדה ונרשם ביומן', () async {
      final downloads = FakeDownloads();
      final logged = <(SemanticFailure, Map<String, String?>)>[];
      final repository = buildRepository(
        root: root,
        download: downloads.call,
        locator: FakeLocator(releaseV30()),
        onnxRuntimePath: () => null,
      );
      repository.failureLog = SemanticDataFailureLog(
        write: (failure, details) => logged.add((failure, details)),
      );

      await repository.enableAndDownload();

      expect(downloads.urls, isEmpty);
      expect(
        repository.availability.failure?.kind,
        SemanticFailureKind.onnxRuntimeMissing,
      );
      expect(logged, hasLength(1));
      expect(logged.single.$1.kind, SemanticFailureKind.onnxRuntimeMissing);
      expect(logged.single.$2['Step'], 'download');
      expect(
        logged.single.$2['ONNX Runtime'],
        'not found next to the executable',
      );
    });
  });

  group('SemanticDataFailureLog', () {
    test('מצבי משתמש אינם נרשמים, וכשל חוזר נרשם פעם אחת', () {
      var now = DateTime(2026, 11, 11, 10);
      final logged = <SemanticFailureKind>[];
      final log = SemanticDataFailureLog(
        clock: () => now,
        write: (failure, _) => logged.add(failure.kind),
      );

      log.record(
        'download',
        const SemanticFailure(SemanticFailureKind.offline),
      );
      log.record(
        'download',
        const SemanticFailure(SemanticFailureKind.cancelled),
      );
      log.record(
        'open',
        const SemanticFailure(SemanticFailureKind.modelInvalid),
      );
      log.record(
        'open',
        const SemanticFailure(SemanticFailureKind.modelInvalid),
      );
      now = now.add(const Duration(minutes: 11));
      log.record(
        'open',
        const SemanticFailure(SemanticFailureKind.modelInvalid),
      );

      expect(logged, [
        SemanticFailureKind.modelInvalid,
        SemanticFailureKind.modelInvalid,
      ]);
    });
  });
}
