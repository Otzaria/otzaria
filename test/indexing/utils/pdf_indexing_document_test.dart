import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/indexing/utils/pdf_indexing_document.dart';
import 'package:pdfrx/pdfrx.dart';

class _Document extends Fake implements PdfDocument {
  int disposals = 0;
  Completer<void>? closeGate;
  Object? closeError;

  @override
  Future<void> dispose() async {
    disposals++;
    await closeGate?.future;
    if (closeError case final error?) throw error;
  }
}

void main() {
  test('פתיחה בזמן מעבירה בעלות לצרכן בלבד', () {
    fakeAsync((clock) {
      final document = _Document();
      PdfDocument? received;
      openIndexingPdf(
        open: () async => document,
        isCancelled: () => false,
      ).then((value) => received = value);
      clock.flushMicrotasks();
      expect(received, same(document));
      clock.elapse(const Duration(minutes: 2));
      expect(document.disposals, 0);
      received!.dispose();
      clock.flushMicrotasks();
      expect(document.disposals, 1);
    });
  });

  test('מסמך שנפתח אחרי timeout נסגר בדיוק פעם אחת', () {
    fakeAsync((clock) {
      final opening = Completer<PdfDocument>();
      final document = _Document();
      Object? error;
      openIndexingPdf(
        open: () => opening.future,
        isCancelled: () => false,
      ).then<void>(
        (_) => fail('A late document must not reach the consumer'),
        onError: (Object value, StackTrace _) => error = value,
      );
      clock.elapse(const Duration(seconds: 60));
      expect(error, isA<TimeoutException>());
      expect(document.disposals, 0);
      opening.complete(document);
      clock.flushMicrotasks();
      expect(document.disposals, 1);
      clock.elapse(const Duration(minutes: 2));
      expect(document.disposals, 1);
    });
  });

  test('ביטול לפני הפתיחה לא מזניק עבודה', () async {
    var opens = 0;
    final result = await openIndexingPdf(
      open: () async {
        opens++;
        return _Document();
      },
      isCancelled: () => true,
    );
    expect(result, isNull);
    expect(opens, 0);
  });

  test('ביטול במהלך פתיחה ממתין לסגירה בלי להעביר מסמך לצרכן', () {
    fakeAsync((clock) {
      final opening = Completer<PdfDocument>();
      final document = _Document()..closeGate = Completer<void>();
      var cancelled = false;
      var completed = false;
      openIndexingPdf(
        open: () => opening.future,
        isCancelled: () => cancelled,
      ).then((value) {
        expect(value, isNull);
        completed = true;
      });
      cancelled = true;
      opening.complete(document);
      clock.flushMicrotasks();
      expect(document.disposals, 1);
      expect(completed, isFalse);
      document.closeGate!.complete();
      clock.flushMicrotasks();
      expect(completed, isTrue);
      expect(document.disposals, 1);
    });
  });

  test('כשל פתיחה בזמן נשמר וכשל מאוחר אינו שגיאה ללא מטפל', () {
    fakeAsync((clock) {
      final failure = StateError('open failed');
      Object? received;
      openIndexingPdf(
        open: () => Future.error(failure),
        isCancelled: () => false,
      ).then<void>(
        (_) => fail('Expected open failure'),
        onError: (Object error, StackTrace _) => received = error,
      );
      clock.flushMicrotasks();
      expect(received, same(failure));

      final opening = Completer<PdfDocument>();
      openIndexingPdf(
        open: () => opening.future,
        isCancelled: () => false,
      ).then<void>(
        (_) => fail('Expected timeout'),
        onError: (Object error, StackTrace _) => received = error,
      );
      clock.elapse(const Duration(seconds: 60));
      expect(received, isA<TimeoutException>());
      opening.completeError(failure);
      clock.flushMicrotasks();
    });
  });

  test('כשל סגירה אחרי timeout נרשם בלי שגיאה ללא מטפל', () {
    final dataRoot = Directory.systemTemp.createTempSync('pdf_indexing_');
    final previousDataRoot = AppPaths.cachedDataRootPath;
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    try {
      fakeAsync((clock) {
        final opening = Completer<PdfDocument>();
        final document = _Document()..closeError = StateError('close failed');
        openIndexingPdf(
          open: () => opening.future,
          isCancelled: () => false,
        ).then<void>(
          (_) => fail('Expected timeout'),
          onError: (Object error, StackTrace _) {
            expect(error, isA<TimeoutException>());
          },
        );
        clock.elapse(const Duration(seconds: 60));
        opening.complete(document);
        clock.flushMicrotasks();
        expect(document.disposals, 1);
        expect(
          ErrorLogFile.resolveFile().readAsStringSync(),
          contains('PDF indexing: late document cleanup failed'),
        );
      });
    } finally {
      AppPaths.debugOverrideDataRootPath(previousDataRoot);
      dataRoot.deleteSync(recursive: true);
    }
  });

  test('כשל סגירה בעת ביטול לפני timeout מועבר לצרכן', () async {
    final opening = Completer<PdfDocument>();
    final failure = StateError('close failed');
    final document = _Document()..closeError = failure;
    var cancelled = false;
    final result = openIndexingPdf(
      open: () => opening.future,
      isCancelled: () => cancelled,
    );
    final assertion = expectLater(result, throwsA(same(failure)));
    cancelled = true;
    opening.complete(document);
    await assertion;
    expect(document.disposals, 1);
  });

  test('50 פתיחות מאוחרות אינן משאירות מסמכים יתומים', () {
    fakeAsync((clock) {
      final documents = <_Document>[];
      for (var i = 0; i < 50; i++) {
        final opening = Completer<PdfDocument>();
        final document = _Document();
        documents.add(document);
        openIndexingPdf(
          open: () => opening.future,
          isCancelled: () => false,
        ).then<void>(
          (_) => fail('Expected timeout'),
          onError: (Object error, StackTrace _) {
            expect(error, isA<TimeoutException>());
          },
        );
        clock.elapse(const Duration(seconds: 60));
        opening.complete(document);
        clock.flushMicrotasks();
      }
      expect(documents.map((doc) => doc.disposals), everyElement(1));
      expect(clock.pendingTimers, isEmpty);
    });
  });
}
