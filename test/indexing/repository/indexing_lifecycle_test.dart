import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../test_helpers/memory_cache_provider.dart';

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => Settings.init(cacheProvider: MemoryCacheProvider()));

  Library library() =>
      Library(categories: [])
        ..books.add(TextBook(id: 1, title: 'Indexed document'));

  test('whenIdle includes preflight before the first indexed book', () async {
    final repository = _Repository(_Provider())
      ..preflightGate = Completer<void>();
    final run = repository.runIndexing(library(), onProgress: (_, _) {});
    await repository.preflightEntered.future;
    var idle = false;
    final drained = IndexingRepository.whenIdle().then((_) => idle = true);
    await _tick();
    final idleBeforePreflightFinished = idle;
    repository.preflightGate!.complete();
    await run;
    await drained;

    expect(idleBeforePreflightFinished, isFalse);
  });

  test(
    'cancellation during preflight does not restart or latch indexing',
    () async {
      final provider = _Provider();
      final currentLibrary = library();
      final repository = _Repository(provider)
        ..requiresReindex = false
        ..orderGate = Completer<void>();
      final run = repository.runIndexing(currentLibrary, onProgress: (_, _) {});
      await repository.orderEntered.future;
      IndexingRepository(provider).cancelIndexing();
      repository.orderGate!.complete();
      final result = await run;

      expect(result.completed, isFalse);
      expect(provider.isIndexing.value, isFalse);
      provider.indexedFilePaths.add(
        BookIdentity.indexedFilePath(currentLibrary.books.single),
      );
      final next = await repository.runIndexing(
        currentLibrary,
        onProgress: (_, _) {},
      );
      expect(next.completed, isTrue);
      expect(repository.preflights, 2);
    },
  );

  test(
    'replacement drains preflight without restarting a cancelled run',
    () async {
      final provider = _Provider();
      final repository = _Repository(provider)
        ..requiresReindex = false
        ..orderGate = Completer<void>();
      final run = repository.runIndexing(library(), onProgress: (_, _) {});
      await repository.orderEntered.future;
      var replacing = false;
      final replacement = IndexingRepository.withIndexingSuspended(() async {
        replacing = true;
        expect(provider.isIndexing.value, isFalse);
      });
      await _tick();
      final replacingBeforePreflightFinished = replacing;
      repository.orderGate!.complete();
      final result = await run;
      await replacement;

      expect(replacingBeforePreflightFinished, isFalse);
      expect(result.completed, isFalse);
      expect(repository.cancellations, 1);
      expect(provider.isIndexing.value, isFalse);
    },
  );

  test('queued replacements do not overlap or admit new runs', () async {
    final firstEntered = Completer<void>();
    final firstRelease = Completer<void>();
    final secondEntered = Completer<void>();
    final secondRelease = Completer<void>();
    final first = IndexingRepository.withIndexingSuspended(() async {
      firstEntered.complete();
      await firstRelease.future;
    });
    await firstEntered.future;
    final second = IndexingRepository.withIndexingSuspended(() async {
      secondEntered.complete();
      await secondRelease.future;
    });
    await _tick();
    final overlapped = secondEntered.isCompleted;
    final repository = _Repository(_Provider());
    final blocked = await repository.runIndexing(
      library(),
      onProgress: (_, _) {},
    );
    firstRelease.complete();
    await first;
    await secondEntered.future;
    await repository.runIndexing(library(), onProgress: (_, _) {});
    final preflightsWhileSuspended = repository.preflights;
    secondRelease.complete();
    await second;
    await repository.runIndexing(library(), onProgress: (_, _) {});

    expect(overlapped, isFalse);
    expect(blocked.completed, isFalse);
    expect(preflightsWhileSuspended, 0);
    expect(repository.preflights, 1);
  });

  test('a failed replacement does not poison the queued replacement', () async {
    final release = Completer<void>();
    final first = IndexingRepository.withIndexingSuspended<void>(() async {
      await release.future;
      throw StateError('replacement failed');
    });
    final failure = expectLater(first, throwsStateError);
    var replaced = false;
    final second = IndexingRepository.withIndexingSuspended(() async {
      replaced = true;
    });
    release.complete();
    await failure;
    await second;
    final repository = _Repository(_Provider());
    await repository.runIndexing(library(), onProgress: (_, _) {});
    await IndexingRepository.whenIdle();

    expect(replaced, isTrue);
    expect(repository.preflights, 1);
  });

  test('an idle replacement queue does not retain its previous zone', () async {
    final firstZone = FakeAsync();
    final nextZone = FakeAsync();
    var completed = 0;
    try {
      firstZone.run((_) {
        unawaited(
          IndexingRepository.withIndexingSuspended(() async {}).then((_) {
            completed++;
          }),
        );
      });
      await _tick();
      firstZone.flushMicrotasks();
      expect(completed, 1);

      nextZone.run((_) {
        unawaited(
          IndexingRepository.withIndexingSuspended(() async {}).then((_) {
            completed++;
          }),
        );
        nextZone.flushMicrotasks();
      });
      expect(completed, 2);
    } finally {
      firstZone.flushMicrotasks();
      nextZone.flushMicrotasks();
    }
  });
}

class _Repository extends IndexingRepository {
  _Repository(super.provider);

  final preflightEntered = Completer<void>();
  final orderEntered = Completer<void>();
  Completer<void>? preflightGate;
  Completer<void>? orderGate;
  bool requiresReindex = true;
  int preflights = 0;
  int cancellations = 0;

  @override
  Future<bool> requiresManualReindex(Library library) async {
    preflights++;
    if (!preflightEntered.isCompleted) preflightEntered.complete();
    await preflightGate?.future;
    return requiresReindex;
  }

  @override
  Future<void> syncBookOrder(Library library) async {
    if (!orderEntered.isCompleted) orderEntered.complete();
    await orderGate?.future;
  }

  @override
  void cancelIndexing() {
    cancellations++;
    super.cancelIndexing();
  }
}

class _Provider implements TantivyDataProvider {
  @override
  final isIndexing = ValueNotifier(false);

  @override
  final indexedFilePaths = <String>{};

  @override
  Future<SearchEngine> get engine async => _Engine();

  @override
  bool get isTempFallback => false;

  @override
  String? get activeIndexPath => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _Engine implements SearchEngine {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
