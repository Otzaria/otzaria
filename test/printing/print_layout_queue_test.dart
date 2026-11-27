import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/pdf_export_cancellation.dart';
import 'package:otzaria/printing/print_layout_queue.dart';

void main() {
  test('פריסות ממסכים שונים רצות אחת אחרי השנייה', () async {
    var active = 0;
    var maxActive = 0;
    final gates = List.generate(3, (_) => Completer<void>());
    final runs = [
      for (final gate in gates)
        PrintLayoutQueue.run(() async {
          active++;
          if (active > maxActive) maxActive = active;
          await gate.future;
          active--;
          return gates.indexOf(gate);
        }, isCancelled: () => false),
    ];
    await pumpEventQueue();
    expect(active, 1);
    for (final gate in gates) {
      gate.complete();
      await pumpEventQueue();
    }
    expect(await Future.wait(runs), [0, 1, 2]);
    expect(maxActive, 1);
    expect(PrintLayoutQueue.idle, isNull);
  });

  test('מסך שנסגר בזמן ההמתנה אינו מתחיל פריסה', () async {
    final gate = Completer<void>();
    final first = PrintLayoutQueue.run(
      () => gate.future,
      isCancelled: () => false,
    );
    var closed = false;
    var started = false;
    final queued = PrintLayoutQueue.run(() async {
      started = true;
    }, isCancelled: () => closed);
    closed = true;
    gate.complete();
    await first;
    await expectLater(queued, throwsA(isA<PdfExportCancelledException>()));
    expect(started, isFalse);
  });

  test('כשל בפריסה אינו חוסם את הבאה', () async {
    final failed = PrintLayoutQueue.run<int>(
      () async => throw StateError('layout'),
      isCancelled: () => false,
    );
    final next = PrintLayoutQueue.run(() async => 7, isCancelled: () => false);
    await expectLater(failed, throwsStateError);
    expect(await next, 7);
  });
}
