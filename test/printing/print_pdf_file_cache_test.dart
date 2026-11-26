import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/print_pdf_file_cache.dart';

void main() {
  late Directory directory;
  late PrintPdfFileCache cache;
  late List<Future<PrintPdfFileLease>> requests;
  late List<Completer<void>> barriers;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdf-file-cache-test-');
    cache = PrintPdfFileCache(temporaryDirectory: directory);
    requests = [];
    barriers = [];
  });
  tearDown(() async {
    for (final barrier in barriers) {
      if (!barrier.isCompleted) barrier.complete();
    }
    for (final request in requests) {
      PrintPdfFileLease? lease;
      try {
        lease = await request;
      } catch (_) {
        continue;
      }
      await lease.dispose();
    }
    await cache.dispose();
    await directory.delete(recursive: true);
  });

  Future<PrintPdfFileLease> acquire(
    String signature,
    Future<void> Function(String path) generate,
  ) {
    final request = cache.acquire(signature, generate);
    requests.add(request);
    return request;
  }

  Completer<void> barrier() {
    final value = Completer<void>();
    barriers.add(value);
    return value;
  }

  test(
    'shares pending work and retains the file until every owner leaves',
    () async {
      final started = Completer<String>();
      final finish = barrier();
      var calls = 0;
      Future<void> generate(String path) async {
        calls++;
        started.complete(path);
        await finish.future;
        await File(path).writeAsString('shared result');
      }

      final first = acquire('A', generate);
      final second = acquire('A', generate);
      final path = await started.future;
      finish.complete();
      final a = await first;
      final b = await second;
      expect(calls, 1);
      expect(a.path, path);
      expect(b.path, path);
      await a.dispose();
      cache.invalidate();
      expect(await File(path).readAsString(), 'shared result');
      await b.dispose();
      expect(await File(path).parent.exists(), isFalse);
      expect(() => a.source, throwsStateError);
      await b.dispose();
    },
  );

  test(
    'A to B to A reuses pending A and caches the latest requested signature',
    () async {
      final finishA = barrier();
      final finishB = barrier();
      var callsA = 0;
      var callsB = 0;
      Future<void> generateA(String path) async {
        callsA++;
        await finishA.future;
        await File(path).writeAsString('A');
      }

      final firstA = acquire('A', generateA);
      final pendingB = acquire('B', (path) async {
        callsB++;
        await finishB.future;
        await File(path).writeAsString('B');
      });
      final secondA = acquire('A', generateA);
      finishA.complete();
      final a1 = await firstA;
      final a2 = await secondA;
      finishB.complete();
      final b = await pendingB;
      final thirdA = await acquire('A', (_) async => fail('A was duplicated'));
      expect(callsA, 1);
      expect(callsB, 1);
      expect(a1.path, a2.path);
      expect(thirdA.path, a1.path);
      final pathA = a1.path;
      final pathB = b.path;
      await a1.dispose();
      await a2.dispose();
      await thirdA.dispose();
      await b.dispose();
      expect(await File(pathA).exists(), isTrue);
      expect(await File(pathB).parent.exists(), isFalse);
    },
  );

  test('a new completed signature evicts only the cache reference', () async {
    final a = await acquire('A', (path) => File(path).writeAsString('A'));
    final oldPath = a.path;
    final b = await acquire('B', (path) => File(path).writeAsString('B'));
    final newPath = b.path;
    expect(await File(oldPath).readAsString(), 'A');
    await a.dispose();
    expect(await File(oldPath).parent.exists(), isFalse);
    await b.dispose();
    expect(await File(newPath).exists(), isTrue);
    await cache.dispose();
    expect(await File(newPath).parent.exists(), isFalse);
  });

  test(
    'an old generation cannot replace or remove a newer pending A',
    () async {
      final oldDone = barrier();
      final newDone = barrier();
      var newCalls = 0;
      final old = acquire('A', (path) async {
        await oldDone.future;
        await File(path).writeAsString('old A');
      });
      cache.invalidate();
      Future<void> generateNew(String path) async {
        newCalls++;
        await newDone.future;
        await File(path).writeAsString('new A');
      }

      final next = acquire('A', generateNew);
      oldDone.complete();
      final oldLease = await old;
      final duplicate = acquire('A', generateNew);
      newDone.complete();
      final nextLease = await next;
      final duplicateLease = await duplicate;
      expect(newCalls, 1);
      expect(nextLease.path, duplicateLease.path);
      expect(nextLease.path, isNot(oldLease.path));
      expect(await File(nextLease.path).readAsString(), 'new A');
      final oldPath = oldLease.path;
      await oldLease.dispose();
      expect(await File(oldPath).parent.exists(), isFalse);
    },
  );

  test('a late failure cannot remove a newer pending generation', () async {
    final oldDone = barrier();
    final newDone = barrier();
    final error = StateError('old generation failed');
    final old = acquire('A', (path) async {
      await oldDone.future;
      throw error;
    });
    final oldFailure = expectLater(old, throwsA(same(error)));
    cache.invalidate();
    var calls = 0;
    Future<void> generateNew(String path) async {
      calls++;
      await newDone.future;
      await File(path).writeAsString('new');
    }

    final next = acquire('A', generateNew);
    oldDone.complete();
    await oldFailure;
    final shared = acquire('A', generateNew);
    newDone.complete();
    expect((await next).path, (await shared).path);
    expect(calls, 1);
  });

  test(
    'failure removes its private directory and permits a fresh retry',
    () async {
      final failure = StateError('producer failed');
      late String failedPath;
      final failed = acquire('A', (path) async {
        failedPath = path;
        await File(path).writeAsString('incomplete');
        throw failure;
      });
      await expectLater(failed, throwsA(same(failure)));
      expect(await File(failedPath).parent.exists(), isFalse);
      final retry = await acquire(
        'A',
        (path) => File(path).writeAsString('complete'),
      );
      expect(retry.path, isNot(failedPath));
      expect(await File(retry.path).readAsString(), 'complete');
    },
  );

  for (final createEmptyFile in [false, true]) {
    test(
      'rejects missing/empty producer output (exists=$createEmptyFile)',
      () async {
        late String path;
        await expectLater(
          acquire('A', (target) async {
            path = target;
            if (createEmptyFile) await File(target).create();
          }),
          throwsStateError,
        );
        expect(await File(path).parent.exists(), isFalse);
      },
    );
  }

  test(
    'close waits for an in-flight producer and its delivered lease',
    () async {
      final started = Completer<String>();
      final finish = barrier();
      final pending = acquire('A', (path) async {
        started.complete(path);
        await finish.future;
        await File(path).writeAsString('ready after close');
      });
      final path = await started.future;
      var closed = false;
      final closing = cache.dispose().then((_) => closed = true);
      expect(() => cache.acquire('A', (_) async {}), throwsStateError);
      expect(closed, isFalse);
      finish.complete();
      final lease = await pending;
      expect(await File(path).exists(), isTrue);
      expect(closed, isFalse);
      await lease.dispose();
      await closing;
      expect(closed, isTrue);
      expect(await File(path).parent.exists(), isFalse);
    },
  );

  test(
    'close drains a failing producer without waiting for a nonexistent lease',
    () async {
      final started = Completer<void>();
      final finish = barrier();
      final failure = StateError('failed after close');
      final pending = acquire('A', (path) async {
        started.complete();
        await finish.future;
        throw failure;
      });
      final observed = expectLater(pending, throwsA(same(failure)));
      await started.future;
      final closing = cache.dispose();
      finish.complete();
      await observed;
      await closing;
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'the generated directory is private before the desktop POSIX producer',
    () async {
      final lease = await acquire(
        'A',
        (path) async {
          expect((await File(path).parent.stat()).mode & 0x1ff, 0x1c0);
          await File(path).writeAsString('private');
        },
      );
      final mode = (await File(lease.path).parent.stat()).mode;
      expect(mode & 0x1ff, 0x1c0);
    },
    skip: !Platform.isLinux && !Platform.isMacOS
        ? 'Other platforms use their temporary-directory policy.'
        : false,
  );

  test(
    'a permissions failure prevents generation and drains the entry',
    () async {
      final failingCache = PrintPdfFileCache(
        temporaryDirectory: _DisappearingDirectory(directory),
      );
      var generated = false;
      try {
        await expectLater(
          failingCache.acquire('A', (_) async {
            generated = true;
          }),
          throwsA(isA<FileSystemException>()),
        );
        expect(generated, isFalse);
        expect(await directory.list().toList(), isEmpty);
      } finally {
        await failingCache.dispose();
      }
    },
    skip: !Platform.isLinux && !Platform.isMacOS
        ? 'Other platforms use their temporary-directory policy.'
        : false,
  );

  test(
    'producer error remains primary and close reports failed cleanup',
    () async {
      final cleanupError = FileSystemException('delete failed', directory.path);
      final producerError = StateError('generation failed');
      final failingRoot = _CleanupFailureDirectory(directory, cleanupError);
      final failingCache = PrintPdfFileCache(temporaryDirectory: failingRoot);
      await expectLater(
        failingCache.acquire('A', (path) async {
          await File(path).writeAsString('partial');
          throw producerError;
        }),
        throwsA(same(producerError)),
      );
      await expectLater(failingCache.dispose(), throwsA(same(cleanupError)));
      expect(failingRoot.child!.deleteAttempts, 1);
    },
  );
}

class _CleanupFailureDirectory implements Directory {
  _CleanupFailureDirectory(this.base, this.error);
  final Directory base;
  final Object error;
  _CleanupFailureDirectory? child;
  var deleteAttempts = 0;

  @override
  String get path => base.path;

  @override
  Uri get uri => base.uri;

  @override
  Future<Directory> createTemp([String? prefix]) async =>
      child = _CleanupFailureDirectory(await base.createTemp(prefix), error);

  @override
  Future<bool> exists() => base.exists();

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    deleteAttempts++;
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DisappearingDirectory implements Directory {
  _DisappearingDirectory(this.base);

  final Directory base;

  @override
  Future<Directory> createTemp([String? prefix]) async {
    final created = await base.createTemp(prefix);
    await created.delete();
    return created;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
