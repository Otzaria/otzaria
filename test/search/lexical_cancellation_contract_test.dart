import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  test(
    'repository waits for cancellation and propagates its failure',
    () async {
      final operations = _Operations();
      final repository = SearchRepository(
        engineProvider: () async => operations,
      );
      var completed = false;
      final cancellation = repository.cancelLexicalSearch(17);
      final failure = expectLater(cancellation, throwsStateError);
      unawaited(cancellation.then((_) => completed = true, onError: (_) {}));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      operations.pending.completeError(StateError('cancel failed'));
      await failure;
    },
  );

  test('operations share one prepared handle for each engine', () async {
    final engine = _Engine();
    final prepared = RustSearchEngineOperations.prepareCancellation(engine);
    final handle = _Handle();
    engine.pendingHandle.complete(handle);
    await prepared;
    await RustSearchEngineOperations(engine).cancelLexicalSearch(21);
    await RustSearchEngineOperations(engine).cancelLexicalSearch(22);
    expect(engine.handleRequests, 1);
    expect(handle.cancelled, [21, 22]);
    await RustSearchEngineOperations.disposeCancellation(engine);
    expect(handle.disposed, isTrue);
  });

  test(
    'provider cancellation waits for the engine and returns handle errors',
    () async {
      final opening = Completer<SearchEngine>();
      final provider = TantivyDataProvider.forTesting(opening.future);
      final engine = _Engine();
      final handle = _Handle()..error = StateError('cancel failed');
      var completed = false;
      final cancellation = provider.cancelLexicalSearch(31);
      final failure = expectLater(cancellation, throwsStateError);
      unawaited(cancellation.then((_) => completed = true, onError: (_) {}));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      opening.complete(engine);
      engine.pendingHandle.complete(handle);
      await failure;
      expect(handle.cancelled, [31]);
      await provider.dispose();
      expect(handle.disposed, isTrue);
      expect(engine.disposed, isTrue);
    },
  );

  test('disposing releases the engine and shares its pending handle', () async {
    final engine = _Engine();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    final prepared = RustSearchEngineOperations.prepareCancellation(engine);
    final cancelling = RustSearchEngineOperations(
      engine,
    ).cancelLexicalSearch(32);
    final disposing = provider.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(engine.disposed, isTrue);
    await RustSearchEngineOperations(engine).cancelLexicalSearch(33);
    expect(engine.handleRequests, 1);
    final handle = _Handle();
    engine.pendingHandle.complete(handle);
    await prepared;
    await disposing;
    await cancelling;
    expect(engine.handleRequests, 1);
    expect(handle.cancelled, isEmpty);
    expect(handle.disposed, isTrue);
    expect(engine.disposed, isTrue);
  });

  test(
    'disposing closes the index writer before releasing the engine',
    () async {
      final engine = _Engine()..closeGate = Completer<void>();
      final provider = TantivyDataProvider.forTesting(Future.value(engine));
      final disposing = provider.dispose();
      await Future.any([engine.closeEntered.future, disposing]);
      expect(engine.calls, ['closeIndexWriter']);
      engine.closeGate!.complete();
      await disposing;
      expect(engine.calls, ['closeIndexWriter', 'dispose']);
    },
  );

  test('a failed writer close still releases the engine', () async {
    final engine = _Engine()..closeGate = Completer<void>();
    final provider = TantivyDataProvider.forTesting(Future.value(engine));
    final disposing = provider.dispose();
    await Future.any([engine.closeEntered.future, disposing]);
    expect(engine.calls, ['closeIndexWriter']);
    engine.closeGate!.completeError(StateError('close failed'));
    await disposing;
    expect(engine.calls, ['closeIndexWriter', 'dispose']);
  });

  test(
    'cancellation after a failed open does not retry engine initialization',
    () async {
      final opening = Completer<SearchEngine>();
      final provider = TantivyDataProvider.forTesting(opening.future);
      final failure = expectLater(provider.engine, throwsStateError);
      opening.completeError(StateError('open failed'));
      await failure;
      await Future<void>.delayed(Duration.zero);
      await expectLater(provider.cancelLexicalSearch(41), completes);
    },
  );

  group('dictionary replacement ordering', () {
    setUpAll(() => Settings.init(cacheProvider: _EmptySettings()));

    for (final failReplacement in [false, true]) {
      test(
        'awaits detach and reload; replacement fails=$failReplacement',
        () async {
          final engine = _Engine();
          final provider = TantivyDataProvider.forTesting(Future.value(engine));
          var replaced = false;
          var completed = false;
          final replacing = provider.replaceMagicDictionaryDetached(() async {
            replaced = true;
            if (failReplacement) throw StateError('replace failed');
          });
          final result = failReplacement
              ? expectLater(replacing, throwsStateError)
              : expectLater(replacing, completes);
          unawaited(replacing.then((_) => completed = true, onError: (_) {}));
          await engine.detaching.future;
          expect(replaced, isFalse);
          engine.detachGate.complete(false);
          await engine.reloading.future;
          expect(replaced, isTrue);
          expect(completed, isFalse);
          engine.reloadGate.complete(true);
          await result;
          expect(engine.dictionaryPaths, hasLength(2));
          expect(engine.dictionaryPaths.first, endsWith('.detached'));
          expect(engine.dictionaryPaths.last, isNot(endsWith('.detached')));
        },
      );
    }
  });
}

class _Operations implements SearchEngineOperations {
  final pending = Completer<void>();

  @override
  Future<void> cancelLexicalSearch(int requestId) => pending.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Handle implements LexicalCancellationHandle {
  final cancelled = <int>[];
  Object? error;
  bool disposed = false;

  @override
  void cancel({required int requestId}) {
    if (disposed) throw StateError('handle disposed');
    cancelled.add(requestId);
    if (error != null) throw error!;
  }

  @override
  void dispose() => disposed = true;

  @override
  bool get isDisposed => disposed;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Engine implements SearchEngine {
  final pendingHandle = Completer<LexicalCancellationHandle>();
  final detaching = Completer<void>();
  final reloading = Completer<void>();
  final detachGate = Completer<bool>();
  final reloadGate = Completer<bool>();
  final dictionaryPaths = <String>[];
  final calls = <String>[];
  final closeEntered = Completer<void>();
  Completer<void>? closeGate;
  int handleRequests = 0;
  bool disposed = false;

  @override
  Future<LexicalCancellationHandle> lexicalCancellationHandle() {
    handleRequests++;
    return pendingHandle.future;
  }

  @override
  Future<bool> setMagicDictionaryPath({required String path}) {
    dictionaryPaths.add(path);
    if (path.endsWith('.detached')) {
      detaching.complete();
      return detachGate.future;
    }
    reloading.complete();
    return reloadGate.future;
  }

  @override
  Future<void> closeIndexWriter() {
    calls.add('closeIndexWriter');
    if (!closeEntered.isCompleted) closeEntered.complete();
    return closeGate?.future ?? Future<void>.value();
  }

  @override
  void dispose() {
    calls.add('dispose');
    disposed = true;
  }

  @override
  bool get isDisposed => disposed;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _EmptySettings implements CacheProvider {
  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
