import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_retire_'));
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

  FakeBackend installedBackend() {
    installModelFiles(root);
    return FakeBackend()..vectors = installedV30;
  }

  test('פתיחה מוצלחת מפנה את הדור הקודם אחרי החימום', () async {
    final backend = installedBackend();
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);

    expect(backend.retireDirs, hasLength(1));
    expect(
      backend.calls.indexWhere((c) => c.startsWith('search:')),
      isNonNegative,
    );
  });

  test('סשן שחזר לדור הקודם אינו מפנה אותו', () async {
    final backend = installedBackend();
    backend.vectors = SemanticVectorsSummary(
      present: true,
      modelFamilyId: kTestModelFamilyId,
      libraryVersion: 30,
      recoveredFromPrevious: true,
    );
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.calls.any((c) => c.startsWith('search:')));
    await pumpEventQueue();

    expect(backend.retireDirs, isEmpty);
  });

  test('פתיחה שנכשלה אינה מפנה כלום', () async {
    final backend = installedBackend()
      ..openFailure = const SemanticFailure(
        SemanticFailureKind.artifactCorrupt,
      );
    final repo = buildRepository(root: root, backend: backend);

    await expectLater(repo.ensureOpen(), throwsA(isA<SemanticFailure>()));
    await pumpEventQueue();

    expect(backend.retireDirs, isEmpty);
  });

  test('כשל בפינוי אינו מציף את הממשק ואינו סוגר את החיפוש', () async {
    final backend = installedBackend()
      ..retireFailures.add(
        const SemanticFailure(SemanticFailureKind.artifactCorrupt),
      );
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    await pumpEventQueue();

    expect(repo.availability.failure, isNull);
    expect(backend.calls, isNot(contains('disable')));
  });

  test('vectorsBusy בפינוי מנסה שוב מאוחר יותר, בלי כשל', () async {
    final backend = installedBackend()
      ..retireFailures.add(
        const SemanticFailure(SemanticFailureKind.vectorsBusy),
      );
    final repo = buildRepository(root: root, backend: backend);

    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);
    await pumpEventQueue();

    expect(repo.availability.failure, isNull);
  });

  test('מחיקת הנתונים ממתינה לפינוי שרץ', () async {
    final gate = Completer<void>();
    final backend = installedBackend()..retireGate = gate;
    final repo = buildRepository(root: root, backend: backend);
    await repo.ensureOpen();
    await waitFor(() => backend.retireDirs.isNotEmpty);

    var removed = false;
    final removing = repo.removeData().then((_) => removed = true);
    await pumpEventQueue();
    expect(removed, isFalse);

    gate.complete();
    await removing;
    expect(removed, isTrue);
  });
}
