import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/printing/pdf_export_cancellation.dart';
import 'package:test/test.dart';

void main() {
  test('ללא token אין ביטול; cancel מונע עבודה חדשה', () {
    expect(PdfExportCancellationToken.isCancelledAt(0), isFalse);
    PdfExportCancellationToken.throwIfCancelledAt(0);
    final token = PdfExportCancellationToken();
    expect(token.isCancelled, isFalse);
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(token.acquire, throwsA(isA<PdfExportCancelledException>()));
    token.dispose();
  });

  test('שני leases רואים אותו ביטול גם אחרי dispose של הבעלים', () {
    final token = PdfExportCancellationToken();
    final first = token.acquire();
    final second = token.acquire();
    expect(first.address, second.address);
    expect(PdfExportCancellationToken.isCancelledAt(first.address), isFalse);
    token.dispose();
    expect(PdfExportCancellationToken.isCancelledAt(first.address), isTrue);
    first.dispose();
    first.dispose();
    expect(PdfExportCancellationToken.isCancelledAt(second.address), isTrue);
    expect(
      () => PdfExportCancellationToken.throwIfCancelledAt(second.address),
      throwsA(isA<PdfExportCancelledException>()),
    );
    second.dispose();
    token.dispose();
    expect(() => first.address, throwsStateError);
    expect(() => second.address, throwsStateError);
  });

  test('lease שהסתיים אינו מונע פעולה נוספת לפני ביטול', () {
    final token = PdfExportCancellationToken();
    final first = token.acquire();
    first.dispose();
    final second = token.acquire();
    expect(PdfExportCancellationToken.isCancelledAt(second.address), isFalse);
    second.dispose();
    token.dispose();
  });

  test('worker סינכרוני רואה ביטול בלי להריץ את תור האירועים שלו', () async {
    final token = PdfExportCancellationToken();
    final lease = token.acquire();
    final ready = ReceivePort();
    final address = lease.address;
    final signal = ready.sendPort;
    final worker = Isolate.run(() {
      signal.send(true);
      final deadline = Stopwatch()..start();
      while (!PdfExportCancellationToken.isCancelledAt(address)) {
        if (deadline.elapsed > const Duration(seconds: 10)) {
          throw StateError(
            'The synchronous worker did not observe cancellation.',
          );
        }
        sleep(const Duration(milliseconds: 1));
      }
      return PdfExportCancellationToken.isCancelledAt(address);
    });
    try {
      await ready.first.timeout(const Duration(seconds: 5));
      token.dispose();
      expect(await worker, isTrue);
    } finally {
      token.dispose();
      try {
        await worker;
      } finally {
        lease.dispose();
        ready.close();
      }
    }
  });
}
