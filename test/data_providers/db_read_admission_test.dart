import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';

Future<Object?> _outcome<T>(Future<T> future) =>
    future.then<Object?>((value) => value, onError: (Object error) => error);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final gates = <Completer<void>>[];
  final reads = <Future<Object?>>[];

  Future<Object?> holdRead({Map<String, Object?>? arguments}) {
    final gate = Completer<void>();
    gates.add(gate);
    final result = _outcome(
      DbReadWorker.trackFallbackRead(
        () => gate.future,
        requestArguments: arguments,
      ),
    );
    reads.add(result);
    return result;
  }

  tearDown(() async {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await Future.wait(reads);
    gates.clear();
    reads.clear();
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.disposeForTesting();
    DbReadWorker.maxFallbackReads = 2;
    DbReadWorker.maxQueuedFallbackReads = 32;
    DbReadWorker.maxPendingWorkerReads = 64;
    DbReadWorker.maxPendingRequestBytes = 512 * 1024;
    DbReadWorker.stallTimeout = const Duration(seconds: 10);
    DbReadWorker.admissionTimeout = const Duration(seconds: 10);
    DbReadWorker.lifecycleCommandTimeout = const Duration(seconds: 4);
    expect(DbReadWorker.resourceUsage.activeFallbackReads, 0);
    expect(DbReadWorker.resourceUsage.queuedReads, 0);
    expect(DbReadWorker.resourceUsage.estimatedQueuedBytes, 0);
  });

  test('queue count bounds callbacks before they start', () async {
    DbReadWorker.maxQueuedFallbackReads = 2;
    holdRead();
    holdRead();
    holdRead();
    holdRead();
    var overflowStarted = false;
    final overflow = await _outcome(
      DbReadWorker.trackFallbackRead(() async {
        overflowStarted = true;
      }),
    );
    expect(overflow, isA<DbReadWorkerBusy>());
    expect(overflowStarted, isFalse);
    expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
    expect(DbReadWorker.resourceUsage.queuedReads, 2);
    expect(DbReadWorker.resourceUsage.estimatedQueuedBytes, greaterThan(0));
  });

  test('queue bytes reject a large backlog before the count limit', () async {
    DbReadWorker.maxPendingRequestBytes = 4096;
    holdRead();
    holdRead();
    final arguments = {'title': 'x' * 1500};
    holdRead(arguments: arguments);
    final overflow = await holdRead(arguments: arguments);
    expect(overflow, isA<DbReadWorkerBusy>());
    expect(DbReadWorker.resourceUsage.queuedReads, 1);
    expect(
      DbReadWorker.resourceUsage.estimatedQueuedBytes,
      inInclusiveRange(3000, 4096),
    );
    if (const bool.fromEnvironment('RUN_DB_READ_ADMISSION_BENCHMARK')) {
      final usage = DbReadWorker.resourceUsage;
      // ignore: avoid_print
      print(
        jsonEncode({
          'scenario': 'db_read_queue_descriptor_snapshot',
          'definition':
              'Estimated request descriptors; excludes results/native memory',
          'liveWorkers': usage.liveWorkers,
          'activeFallbackReads': usage.activeFallbackReads,
          'pendingWorkerReads': usage.pendingWorkerReads,
          'queuedReads': usage.queuedReads,
          'estimatedQueuedBytes': usage.estimatedQueuedBytes,
          'limitBytes': DbReadWorker.maxPendingRequestBytes,
        }),
      );
    }
  });

  test(
    'one-shot catalog reads share fallback admission before spawn',
    () async {
      DbReadWorker.maxQueuedFallbackReads = 0;
      holdRead();
      holdRead();
      expect(
        await _outcome(DbReadWorker.runOnFreshIsolate(() => 7)),
        isA<DbReadWorkerBusy>(),
      );
      expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
      expect(DbReadWorker.resourceUsage.queuedReads, 0);
    },
  );

  test('public temporary tracking cannot bypass fallback admission', () async {
    DbReadWorker.maxQueuedFallbackReads = 0;
    holdRead();
    holdRead();
    var callbackStarted = false;
    expect(
      await _outcome(
        DbReadWorker.trackTemporaryRead(() async {
          callbackStarted = true;
          return 7;
        }),
      ),
      isA<DbReadWorkerBusy>(),
    );
    expect(callbackStarted, isFalse);
    expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
    expect(DbReadWorker.resourceUsage.queuedReads, 0);
  });

  test('an expired queued read never runs after a slot is released', () async {
    holdRead();
    holdRead();
    DbReadWorker.admissionTimeout = const Duration(milliseconds: 20);
    var queuedStarts = 0;
    final queued = _outcome(
      DbReadWorker.trackFallbackRead(() async {
        queuedStarts++;
      }),
    );
    expect(await queued, isA<DbReadWorkerBusy>());
    expect(DbReadWorker.resourceUsage.queuedReads, 0);
    expect(DbReadWorker.resourceUsage.estimatedQueuedBytes, 0);
    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait(reads);
    expect(queuedStarts, 0);
    expect(await DbReadWorker.trackFallbackRead(() async => 7), 7);
  });

  test('a synchronous callback error releases its real slot', () async {
    final error = StateError('read failed before returning a future');
    expect(
      await _outcome(DbReadWorker.trackFallbackRead(() => throw error)),
      same(error),
    );
    expect(DbReadWorker.resourceUsage.activeFallbackReads, 0);
    expect(await DbReadWorker.trackFallbackRead(() async => 11), 11);
  });

  test(
    'reopen cannot lend slots still owned by the previous generation',
    () async {
      holdRead();
      holdRead();
      final oldQueued = holdRead();
      await DbReadWorker.closeConnectionIfRunning(wait: false);
      DbReadWorker.allowReopen();
      expect(await oldQueued, isA<DbReadWorkerSuspended>());
      expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
      DbReadWorker.admissionTimeout = const Duration(milliseconds: 20);
      var newReadStarted = false;
      expect(
        await _outcome(
          DbReadWorker.trackFallbackRead(() async {
            newReadStarted = true;
          }),
        ),
        isA<DbReadWorkerBusy>(),
      );
      expect(newReadStarted, isFalse);
      for (final gate in gates) {
        gate.complete();
      }
      expect(
        await Future.wait(reads),
        everyElement(isA<DbReadWorkerSuspended>()),
      );
      expect(await DbReadWorker.trackFallbackRead(() async => 'new'), 'new');
    },
  );

  test('failed suspension does not forget live fallback connections', () async {
    holdRead();
    holdRead();
    DbReadWorker.lifecycleCommandTimeout = const Duration(milliseconds: 20);
    expect(await DbReadWorker.suspendForExternalWrite(), isFalse);
    expect(DbReadWorker.resourceUsage.activeFallbackReads, 2);
    expect(
      await _outcome(DbReadWorker.trackFallbackRead(() async => 1)),
      isA<DbReadWorkerSuspended>(),
    );
    await DbReadWorker.resumeAfterExternalWrite();
    DbReadWorker.admissionTimeout = const Duration(milliseconds: 20);
    expect(
      await _outcome(DbReadWorker.trackFallbackRead(() async => 2)),
      isA<DbReadWorkerBusy>(),
    );
    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait(reads);
    expect(await DbReadWorker.suspendForExternalWrite(), isTrue);
  });

  test('a queued callback handed a slot before close does not run', () async {
    holdRead();
    holdRead();
    var queuedStarted = false;
    final queued = _outcome(
      DbReadWorker.trackFallbackRead(() async {
        queuedStarted = true;
      }),
    );
    gates.first.complete();
    await DbReadWorker.closeConnectionIfRunning(wait: false);
    DbReadWorker.allowReopen();
    expect(await queued, isA<DbReadWorkerSuspended>());
    expect(queuedStarted, isFalse);
  });

  test('an oversized request does not spawn a persistent worker', () async {
    DbReadWorker.maxPendingRequestBytes = 1024;
    expect(
      await _outcome(
        DbReadWorker.request('textRange', {'title': 'x' * 1000}),
      ),
      isA<DbReadWorkerBusy>(),
    );
    expect(DbReadWorker.resourceUsage.liveWorkers, 0);
    expect(DbReadWorker.resourceUsage.pendingWorkerReads, 0);
  });

  test('close rejects a batch that has not reached its microtask', () async {
    final queued = _outcome(
      DbReadWorker.batched('heRef', {'dbPath': 'old.db', 'bookId': 1}),
    );
    await DbReadWorker.closeConnectionIfRunning(wait: false);
    DbReadWorker.allowReopen();
    expect(await queued, isA<DbReadWorkerSuspended>());
    expect(DbReadWorker.resourceUsage.liveWorkers, 0);
  });
}
