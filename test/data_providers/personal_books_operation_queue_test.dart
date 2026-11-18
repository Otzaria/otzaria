import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/personal_books_operation_queue.dart';

void main() {
  late PersonalBooksOperationQueue queue;

  setUp(() {
    queue = PersonalBooksOperationQueue();
  });

  test(
    'executes operations serially and counts queued work immediately',
    () async {
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final order = <int>[];
      var secondStarted = false;

      final first = queue.enqueue(() async {
        order.add(1);
        firstStarted.complete();
        await releaseFirst.future;
        return 1;
      });
      final second = queue.enqueue(() async {
        secondStarted = true;
        order.add(2);
        return 2;
      });

      expect(queue.busyCount.value, 2);
      await firstStarted.future;
      expect(secondStarted, isFalse);
      expect(order, [1]);

      releaseFirst.complete();
      expect(await first, 1);
      expect(await second, 2);
      expect(order, [1, 2]);
      expect(queue.busyCount.value, 0);
      expect(queue.isBusy, isFalse);
    },
  );

  test('a failed operation does not block the next operation', () async {
    final failed = queue.enqueue<int>(() async {
      throw StateError('operation failed');
    });
    final next = queue.enqueue(() async => 42);

    await expectLater(failed, throwsA(isA<StateError>()));
    expect(await next, 42);
    expect(queue.busyCount.value, 0);
  });

  test('busy count is released when an operation throws', () async {
    final operation = queue.enqueue<int>(() async {
      throw StateError('failure');
    });

    await expectLater(operation, throwsA(isA<StateError>()));
    expect(queue.isBusy, isFalse);
  });
}
