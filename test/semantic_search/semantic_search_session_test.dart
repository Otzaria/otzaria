import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_results_source.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';

import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticVote;

import 'semantic_test_support.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('semantic_session_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<(SemanticSearchRepository, FakeBackend)> openRepository() async {
    installModelFiles(root);
    final backend = FakeBackend()
      ..vectors = installedV30
      ..searchGate = Completer<void>();
    final repository = buildRepository(root: root, backend: backend);
    await repository.ensureOpen();
    await pumpEventQueue();
    return (repository, backend);
  }

  const request = SemanticSearchRequest(query: 'חסד', facets: ['/']);

  test('חיפוש בערוץ אחד אינו מבטל חיפוש בערוץ אחר', () async {
    final (repository, backend) = await openRepository();
    final tabA = SemanticSearchSession();
    final tabB = SemanticSearchSession();

    final a = repository.search(request, session: tabA);
    await pumpEventQueue();
    final b = repository.search(request, session: tabB);
    await pumpEventQueue();
    backend.searchGate!.complete();

    expect(await a, isNotNull);
    expect(await b, isNotNull);
  });

  test('חיפוש חדש באותו ערוץ מחליף את הקודם', () async {
    final (repository, backend) = await openRepository();
    final tab = SemanticSearchSession();

    final first = repository.search(request, session: tab);
    await pumpEventQueue();
    final second = repository.search(request, session: tab);
    await pumpEventQueue();
    backend.searchGate!.complete();

    expect(await first, isNull);
    expect(await second, isNotNull);
  });

  test('שני מקורות (שתי כרטיסיות): ביטול באחד לא נוגע בשני', () async {
    final (repository, backend) = await openRepository();
    final tabA = EngineSemanticResultsSource(repository);
    final tabB = EngineSemanticResultsSource(repository);
    const options = SemanticQueryOptions(query: 'חסד');

    final a = tabA.fetch(options, offset: 0, limit: 10);
    await pumpEventQueue();
    final b = tabB.fetch(options, offset: 0, limit: 10);
    await pumpEventQueue();
    tabB.cancel();
    backend.searchGate!.complete();

    expect(await a, isNotNull);
    expect(await b, isNull);
  });

  test('מזהה עימוד נפרד לכל חיפוש ונשמר בהמשך ובניסיון חוזר', () async {
    final (repository, backend) = await openRepository();
    backend.searchGate = null;
    final tabA = EngineSemanticResultsSource(repository);
    final tabB = EngineSemanticResultsSource(repository);
    const options = SemanticQueryOptions(query: 'חסד');
    final votes = [
      SemanticVote(filePath: 'id:1', id: BigInt.one, relevant: true),
    ];

    await tabA.fetch(options, offset: 0, limit: 10);
    await tabB.fetch(options, offset: 0, limit: 10);
    await tabA.fetch(options, offset: 10, limit: 10, votes: votes);
    tabA.cancel();
    await tabA.fetch(options, offset: 10, limit: 10, votes: votes);
    await tabA.fetch(options, offset: 0, limit: 10);

    final requests = backend.searchRequests.where(
      (r) => r.query == options.query,
    );
    final ids = requests.map((r) => r.paginationSessionId).toList();
    expect(ids, hasLength(5));
    expect(ids, everyElement(isNotEmpty));
    expect(ids.toSet(), hasLength(3));
    expect(ids[2], ids[0]);
    expect(ids[3], ids[0]);
    expect(requests.map((r) => r.votes), [
      isEmpty,
      isEmpty,
      votes,
      votes,
      isEmpty,
    ]);
  });

  test(
    'לפני העברת ספרייה: חיפושים מבוטלים וה-session נסגר, ונפתח שוב',
    () async {
      final (repository, backend) = await openRepository();
      final running = repository.search(request);
      await pumpEventQueue();

      await repository.releaseForLibraryMove();
      backend.searchGate!.complete();

      expect(await running, isNull);
      expect(backend.calls, contains('disable'));
      backend.searchGate = null;
      await expectLater(
        repository.search(request),
        throwsA(isA<SemanticFailure>()),
      );
      repository.finishLibraryMove();
      await repository.search(request);
      expect(backend.calls.where((call) => call == 'open'), hasLength(2));
    },
  );
}
