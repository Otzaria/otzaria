import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  const gateway = SearchEngineGateway();
  const request = SearchEngineRequest(query: 'test', facets: []);

  tearDown(() => expect(SearchEngineGateway.hasActiveOperations, isFalse));

  test('חיפושים מקבילים נספרים עד שכולם מסתיימים', () async {
    final first = _PendingEngine();
    final second = _PendingEngine();
    final a = gateway.search(first, request);
    final b = gateway.search(second, request);
    expect(SearchEngineGateway.hasActiveOperations, isTrue);
    first.result.complete([]);
    await a;
    expect(SearchEngineGateway.hasActiveOperations, isTrue);
    second.result.complete([]);
    await b;
  });

  test('כשל חיפוש משחרר את מונה הפעילות', () async {
    final engine = _PendingEngine();
    final pending = gateway.search(engine, request);
    final expectation = expectLater(pending, throwsStateError);
    engine.result.completeError(StateError('injected'));
    await expectation;
  });

  test('חיפוש ביטוי ליטרלי משתתף באותו מונה', () async {
    final engine = _PendingEngine();
    final pending = gateway.searchLiteralPhrase(
      engine,
      request,
      includeAdjacentLine: false,
    );
    expect(SearchEngineGateway.hasActiveOperations, isTrue);
    engine.result.complete([]);
    await pending;
  });

  test('stream נספר רק בהאזנה ונשאר פעיל עד סיום הביטול', () async {
    final engine = _PendingEngine();
    final cancelled = Completer<void>();
    engine.updates.onCancel = () => cancelled.future;
    final stream = gateway.searchStreamWithCounts(engine, request, chunkSize: 5);
    expect(SearchEngineGateway.hasActiveOperations, isFalse);
    final subscription = stream.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(SearchEngineGateway.hasActiveOperations, isTrue);
    final cancelling = subscription.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(SearchEngineGateway.hasActiveOperations, isTrue);
    cancelled.complete();
    await cancelling;
    await engine.updates.close();
  });

  test('כשל ב-stream אינו משאיר פעילות לאחר סגירתו', () async {
    final engine = _PendingEngine();
    final pending = gateway
        .searchStreamWithCounts(engine, request, chunkSize: 5)
        .toList();
    final expectation = expectLater(pending, throwsStateError);
    engine.updates.addError(StateError('injected'));
    await engine.updates.close();
    await expectation;
  });
}

class _PendingEngine extends SearchEngineOperations {
  final result = Completer<List<SearchResult>>();
  final updates = StreamController<SearchStreamUpdate>();

  @override
  Future<List<SearchResult>> searchExact(SearchEngineRequest request) =>
      result.future;

  @override
  Future<List<SearchResult>> searchInlineExact(SearchEngineRequest request) =>
      result.future;

  @override
  Stream<SearchStreamUpdate> searchStreamWithCounts(
    SearchEngineRequest request, {
    required int chunkSize,
  }) => updates.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
