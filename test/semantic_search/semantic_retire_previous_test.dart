import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/semantic_search/repository/semantic_data_ownership.dart';
import 'package:path/path.dart' as p;

import 'semantic_test_support.dart';

void main() {
  late Directory root;
  String vectorsDirectory() =>
      SemanticPaths(p.join(root.path, 'otzaria')).vectorsDirectory;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('semantic_retire_');
    installModelFiles(root);
    await markSemanticDirectory(vectorsDirectory());
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  SemanticVectorsSummary generation(int value, {bool recovered = false}) =>
      SemanticVectorsSummary(
        present: true,
        modelFamilyId: installedV30.modelFamilyId,
        libraryVersion: installedV30.libraryVersion,
        libraryReleaseTag: installedV30.libraryReleaseTag,
        segments: installedV30.segments,
        generation: value,
        recoveredFromPrevious: recovered,
      );

  test('פתיחה מהדור החי מפנה גיבוי רק פעם אחת לסשן פעיל', () async {
    final backend = FakeBackend()..vectors = generation(7);
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retiredDirs.isNotEmpty);
    expect(backend.retiredDirs, [backend.openRequests.single.vectorsDir]);

    await repo.ensureOpen();
    expect(backend.openRequests, hasLength(1));
    expect(backend.retireDirs, hasLength(1));
  });

  test('פינוי מתחיל רק אחרי שחימום הסשן הסתיים', () async {
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..vectors = generation(7)
      ..warmUpGate = gate;
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    expect(backend.searchRequests, hasLength(1));
    expect(backend.retireDirs, isEmpty);

    gate.complete();
    await waitFor(() => backend.retiredDirs.isNotEmpty);
  });

  test('פתיחה שנפלה לדור הקודם לא מוחקת אותו', () async {
    final backend = FakeBackend()..vectors = generation(7, recovered: true);
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    expect(backend.openRequests, hasLength(1));
    expect(backend.retiredDirs, isEmpty);
  });

  test('סט תפוס מנסה שוב בסשן הפעיל כשההורדות עצורות וללא רשת', () async {
    final backend = FakeBackend()
      ..vectors = generation(7)
      ..retireFailures.add(
        const SemanticFailure(SemanticFailureKind.vectorsBusy),
      );
    final settings = FakeSettingsStore()
      ..dataEnabled = true
      ..downloadPaused = true
      ..isOfflineMode = true;
    final downloads = FakeDownloads();
    final repo = buildRepository(
      root: root,
      backend: backend,
      settings: settings,
      download: downloads.call,
    );

    await repo.ensureOpen();
    await waitFor(() => backend.retiredDirs.isNotEmpty);
    expect(backend.retireDirs, hasLength(2));
    expect(backend.openRequests, hasLength(1));
    expect(downloads.urls, isEmpty);
    expect((await repo.refresh()).phase, SemanticAvailabilityPhase.ready);
  });

  test('התקנה עם סשן פעיל בודקת מחדש אם אפשר לפנות', () async {
    final backend = FakeBackend()
      ..vectors = SemanticVectorsSummary(
        present: true,
        modelFamilyId: installedV30.modelFamilyId,
        libraryVersion: 29,
        libraryReleaseTag: 'v29',
        generation: 7,
      );
    final repo = buildRepository(
      root: root,
      backend: backend,
      locator: FakeLocator(releaseV30()),
    );

    await repo.ensureOpen();
    await waitFor(() => backend.retiredDirs.isNotEmpty);
    await repo.enableAndDownload();
    await waitFor(() => backend.retiredDirs.length == 2);

    expect(backend.installRequests, hasLength(1));
    expect(backend.openRequests, hasLength(1));
    expect(backend.calls, isNot(contains('disable')));
    expect(
      backend.calls.where((call) => call == 'retire' || call == 'install'),
      orderedEquals(['retire', 'install', 'retire']),
    );
  });

  test('התקנה מבטלת פינוי פעיל ומנסה לפנות שוב אם נכשלה', () async {
    final gate = Completer<void>();
    final backend = FakeBackend()
      ..vectors = SemanticVectorsSummary(
        present: true,
        modelFamilyId: installedV30.modelFamilyId,
        libraryVersion: 29,
        libraryReleaseTag: 'v29',
        generation: 7,
      )
      ..retireGate = gate
      ..installFailures.add(
        const SemanticFailure(SemanticFailureKind.internal),
      );
    final repo = buildRepository(
      root: root,
      backend: backend,
      locator: FakeLocator(releaseV30()),
    );

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    final install = repo.enableAndDownload();
    await waitFor(() => backend.retireCancel!.isCancelled);
    expect(backend.installRequests, isEmpty);
    gate.complete();
    await install;
    await waitFor(() => backend.retiredDirs.isNotEmpty);

    expect(backend.retireDirs, hasLength(2));
    expect(backend.installRequests, hasLength(1));
  });

  for (final move in [false, true]) {
    test('סגירת נתונים ממתינה לפינוי ומבטלת אותו (העברה: $move)', () async {
      final gate = Completer<void>();
      final backend = FakeBackend()
        ..vectors = generation(7)
        ..retireGate = gate;
      final repo = buildRepository(root: root, backend: backend);
      await repo.ensureOpen();
      await waitFor(() => backend.retireDirs.isNotEmpty);

      final closing = move ? repo.releaseForLibraryMove() : repo.removeData();
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, isNot(contains('disable')));
      gate.complete();
      await closing;
      expect(backend.calls, contains('disable'));
      expect(backend.retiredDirs, isEmpty);
      if (move) repo.finishLibraryMove();
    });
  }

  test('מחיקה והתקנה מחדש מאפשרות לפנות אותו מספר דור שוב', () async {
    final backend = FakeBackend()..vectors = generation(7);
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retiredDirs.isNotEmpty);
    await repo.removeData();

    installModelFiles(root);
    await markSemanticDirectory(vectorsDirectory());
    await repo.ensureOpen();
    await waitFor(() => backend.retiredDirs.length == 2);
    expect(backend.openRequests, hasLength(2));
  });

  test('כשל אחר נרשם בלבד, והחיפוש ממשיך לעבוד', () async {
    final backend = FakeBackend()
      ..vectors = generation(7)
      ..retireFailures.add(
        const SemanticFailure(SemanticFailureKind.artifactCorrupt),
      );
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    expect(backend.retireDirs, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await repo.refresh()).phase, SemanticAvailabilityPhase.ready);
    await repo.ensureOpen();
    expect(backend.openRequests, hasLength(1));
  });
}
