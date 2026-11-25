import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';

void main() {
  test('timeout ממתין לאותה עבודת עמוד ומקבל את התוצאה המאוחרת', () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      final calls = <int>[];
      ({Map<int, String> texts, int droppedPages})? result;
      IndexingRepository.extractPageTextsWithRetry(
        pageCount: 2,
        loadPageText: (index) {
          calls.add(index);
          return index == 0 ? first.future : Future.value('עמוד שני');
        },
        beforeEachPage: () async => true,
      ).then((value) => result = value);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      expect(calls, [0, 1]);
      expect(result, isNull);
      first.complete('עמוד ראשון');
      clock.flushMicrotasks();
      expect(result!.texts, {0: 'עמוד ראשון', 1: 'עמוד שני'});
      expect(result!.droppedPages, 0);
      expect(calls, [0, 1]);
    });
  });

  test('תוצאה שהושלמה בין הסריקה לחזרה מנוצלת בלי חילוץ נוסף', () {
    fakeAsync((clock) {
      final first = Completer<String?>();
      final second = Completer<String?>();
      final calls = <int>[];
      ({Map<int, String> texts, int droppedPages})? result;
      IndexingRepository.extractPageTextsWithRetry(
        pageCount: 2,
        loadPageText: (index) {
          calls.add(index);
          return index == 0 ? first.future : second.future;
        },
        beforeEachPage: () async => true,
      ).then((value) => result = value);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      first.complete('ראשון');
      second.complete('שני');
      clock.flushMicrotasks();
      expect(result!.texts, {0: 'ראשון', 1: 'שני'});
      expect(calls, [0, 1]);
    });
  });

  test('100 עמודים תקועים מוזנקים פעם אחת לעמוד, בלי תור ניסיונות כפול', () {
    fakeAsync((clock) {
      final pending = List.generate(100, (_) => Completer<String?>());
      final calls = <int>[];
      ({Map<int, String> texts, int droppedPages})? result;
      IndexingRepository.extractPageTextsWithRetry(
        pageCount: pending.length,
        loadPageText: (index) {
          calls.add(index);
          return pending[index].future;
        },
        beforeEachPage: () async => true,
      ).then((value) => result = value);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1001));
      expect(result!.droppedPages, 100);
      expect(result!.texts, isEmpty);
      expect(calls, List.generate(100, (index) => index));
      for (final future in pending) {
        future.completeError(StateError('late native failure'));
      }
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('null שהוחזר מהעמוד עצמו עדיין מאפשר ניסיון חוזר', () async {
    var calls = 0;
    final result = await IndexingRepository.extractPageTextsWithRetry(
      pageCount: 1,
      loadPageText: (_) async => ++calls == 1 ? null : 'טקסט',
      beforeEachPage: () async => true,
    );
    expect(calls, 2);
    expect(result!.texts, {0: 'טקסט'});
    expect(result.droppedPages, 0);
  });

  for (final cancelled in [false, true]) {
    test('null מאוחר מאפשר ניסיון חוזר רק בלי ביטול ($cancelled)', () {
      fakeAsync((clock) {
        final first = Completer<String?>();
        var isCancelled = false;
        var completed = false;
        var calls = 0;
        ({Map<int, String> texts, int droppedPages})? result;
        IndexingRepository.extractPageTextsWithRetry(
          pageCount: 1,
          loadPageText: (_) =>
              ++calls == 1 ? first.future : Future.value('טקסט'),
          beforeEachPage: () async => !isCancelled,
        ).then((value) {
          result = value;
          completed = true;
        });
        clock.elapse(const Duration(seconds: 5));
        expect(calls, 1);
        expect(completed, isFalse);

        isCancelled = cancelled;
        first.complete(null);
        clock.flushMicrotasks();

        expect(completed, isTrue);
        expect(calls, cancelled ? 1 : 2);
        if (cancelled) {
          expect(result, isNull);
        } else {
          expect(result!.texts, {0: 'טקסט'});
          expect(result!.droppedPages, 0);
        }
      });
    });
  }

  for (final asynchronous in [false, true]) {
    test('כשל חילוץ נשמר בלי ניסיון חוזר (async=$asynchronous)', () async {
      var calls = 0;
      final failure = StateError('text extraction failed');
      await expectLater(
        IndexingRepository.extractPageTextsWithRetry(
          pageCount: 2,
          loadPageText: (_) {
            calls++;
            if (asynchronous) return Future.error(failure);
            throw failure;
          },
          beforeEachPage: () async => true,
        ),
        throwsA(same(failure)),
      );
      expect(calls, 1);
    });
  }

  test('ביטול אחרי timeout אינו מזניק עמוד נוסף או ניסיון חוזר', () {
    fakeAsync((clock) {
      final pending = Completer<String?>();
      var cancelled = false;
      var completed = false;
      var calls = 0;
      IndexingRepository.extractPageTextsWithRetry(
        pageCount: 100,
        loadPageText: (_) {
          calls++;
          return pending.future;
        },
        beforeEachPage: () async => !cancelled,
      ).then((value) {
        expect(value, isNull);
        completed = true;
      });
      clock.flushMicrotasks();
      cancelled = true;
      clock.elapse(const Duration(seconds: 5));
      expect(completed, isTrue);
      expect(calls, 1);
      pending.complete('תוצאה ישנה');
      clock.flushMicrotasks();
      expect(calls, 1);
    });
  });
}
