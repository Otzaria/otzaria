import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';

import 'semantic_test_support.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('semantic_retire_'));
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

  /// ה-session נסגר כמו אחרי פתיחה מחדש של האינדקס, והחיפוש הבא פותח שוב.
  void dropSession(FakeBackend backend) =>
      backend.statusValue = const SemanticBackendStatus(
        state: SemanticBackendState.notConfigured,
        rawState: 'notConfigured',
      );

  test('פתיחה מהדור החי מוחקת את הדור הקודם פעם אחת לכל דור (#2467)', () async {
    installModelFiles(root);
    final backend = FakeBackend()..vectors = generation(7);
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    expect(backend.retireDirs, [backend.openRequests.single.vectorsDir]);

    await repo.ensureOpen();
    dropSession(backend);
    await repo.ensureOpen();
    expect(backend.openRequests, hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(backend.retireDirs, hasLength(1));

    backend.vectors = generation(8);
    dropSession(backend);
    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.length == 2);
    expect(backend.retireDirs, hasLength(2));
  });

  test('פתיחה שנפלה לדור הקודם לא מוחקת אותו', () async {
    installModelFiles(root);
    final backend = FakeBackend()..vectors = generation(7, recovered: true);
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(backend.openRequests, hasLength(1));
    expect(backend.retireDirs, isEmpty);
  });

  test('סט תפוס: אין כשל בממשק, והפתיחה הבאה מנסה שוב', () async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = generation(7)
      ..retireFailures.add(
        const SemanticFailure(SemanticFailureKind.vectorsBusy),
      );
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await repo.refresh()).phase, SemanticAvailabilityPhase.ready);

    dropSession(backend);
    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.length == 2);
    expect(backend.retireDirs, hasLength(2));
  });

  test('כשל אחר נרשם בלבד, והחיפוש ממשיך לעבוד', () async {
    installModelFiles(root);
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
