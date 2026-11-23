import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import 'semantic_test_support.dart';

const _input = SemanticNearestInput(
  points: [SemanticPoint(text: 'חסד', asPassage: false)],
  topK: 5,
  facets: ['/'],
  exclude: [],
  pool: SemanticPool.best,
  maxCandidates: 10,
  rescore: false,
);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_bg_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<(SemanticSearchRepository, FakeBackend, FakeConsentStore)>
  openRepository() async {
    installModelFiles(root);
    final backend = FakeBackend()..vectors = installedV30;
    final consent = FakeConsentStore();
    final repository = buildRepository(
      root: root,
      backend: backend,
      consent: consent,
    );
    await repository.ensureOpen();
    await pumpEventQueue();
    return (repository, backend, consent);
  }

  test('nearest מעביר את הקלט למנוע ומודיע כשהחיפוש מתחיל', () async {
    final (repository, backend, _) = await openRepository();
    var searching = false;

    final response = await repository.nearest(
      _input,
      call: SemanticBackgroundCall(),
      onSearching: () => searching = true,
    );

    expect(response, isNotNull);
    expect(backend.nearestInputs.single, same(_input));
    expect(searching, isTrue);
  });

  test('חיפוש של המשתמש קודם לסריקה של תוסף', () async {
    final (repository, backend, _) = await openRepository();
    backend.searchGate = Completer<void>();
    final call = SemanticBackgroundCall();

    final nearest = repository.nearest(_input, call: call);
    await pumpEventQueue();
    final search = repository.search(
      const SemanticSearchRequest(query: 'חסד', facets: ['/']),
    );
    await pumpEventQueue();
    backend.searchGate!.complete();

    expect(await nearest, isNull);
    expect(call.preempted, isTrue);
    expect(await search, isNotNull);
  });

  test('ביטול ההסכמה עוצר סריקה, ואחריו אין פעולות', () async {
    final (repository, backend, consent) = await openRepository();
    backend.searchGate = Completer<void>();
    final call = SemanticBackgroundCall();

    final nearest = repository.nearest(_input, call: call);
    await pumpEventQueue();
    consent.set(SearchFeedbackConsent.declined);
    await pumpEventQueue();
    backend.searchGate!.complete();

    expect(await nearest, isNull);
    expect(call.preempted, isFalse);
    await expectLater(
      repository.coveredBooks(call: SemanticBackgroundCall()),
      throwsA(
        isA<SemanticFailure>().having(
          (failure) => failure.kind,
          'kind',
          SemanticFailureKind.consentRequired,
        ),
      ),
    );
  });

  test('פעולה שבוטלה לפני שהתחילה אינה מגיעה למנוע', () async {
    final (repository, backend, _) = await openRepository();
    final call = SemanticBackgroundCall()..cancel();

    expect(await repository.queryTokens(['א'], call: call), isNull);
    expect(await repository.nearest(_input, call: call), isNull);
    expect(backend.tokenRequests, isEmpty);
    expect(backend.nearestInputs, isEmpty);
  });

  test('ספירת טוקנים והספרים המכוסים', () async {
    final (repository, backend, _) = await openRepository();
    backend.coveredFilePaths = ['id:7'];

    final tokens = await repository.queryTokens([
      'אבג',
    ], call: SemanticBackgroundCall());
    final covered = await repository.coveredBooks(
      call: SemanticBackgroundCall(),
    );

    expect(tokens!.counts, [5]);
    expect(tokens.queryMaxTokens, 256);
    expect(covered!.filePaths, ['id:7']);
  });
}
