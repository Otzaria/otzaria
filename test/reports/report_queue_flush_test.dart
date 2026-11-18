import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/reports/report_queue_flush.dart';

void main() {
  test('שליחה מיידית, טיימר יחיד והפעלה מחדש לאחר השהיה', () {
    fakeAsync((time) {
      final queue = ReportQueueFlush();
      var calls = 0;
      Future<int> flush() => queue.run(() async => ++calls);

      queue.start(flush);
      queue.start(flush);
      expect(calls, 1);

      time.elapse(const Duration(minutes: 10));
      expect(calls, 3);

      unawaited(queue.suspend());
      time.elapse(const Duration(minutes: 10));
      expect(calls, 3);

      queue.start(flush);
      expect(calls, 4);
      unawaited(queue.suspend());
      time.flushMicrotasks();
    });
  });

  test('השהיה מחכה לשליחה פעילה והרצה מקבילה מדולגת', () async {
    final queue = ReportQueueFlush();
    final delivery = Completer<int>();
    final active = queue.run(() => delivery.future);

    expect(await queue.run(() async => 99), 0);
    var suspended = false;
    final suspension = queue.suspend().then((_) => suspended = true);
    await Future<void>.delayed(Duration.zero);
    expect(suspended, isFalse);

    delivery.complete(2);
    expect(await active, 2);
    await suspension;
    expect(suspended, isTrue);
  });

  test('שגיאה בשליחה משחררת את התור להרצה הבאה', () async {
    final queue = ReportQueueFlush();
    await expectLater(
      queue.run(() async => throw StateError('delivery failed')),
      throwsStateError,
    );
    expect(await queue.run(() async => 1), 1);
  });
}
