import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/pre_close_registry.dart';

void main() {
  group('PreCloseRegistry', () {
    // PreCloseRegistry is the load-bearing mechanism that flushes pending
    // in-memory writes (HistoryBloc snapshots, etc.) to Hive before the app
    // exits. Since `Hive.close()` is no longer called on Windows admin
    // install (it blocks on Defender real-time scan), correctness of the
    // close path now depends entirely on PreCloseRegistry running all
    // registered callbacks reliably.

    setUp(() async {
      // Drain any leftover callbacks from prior tests by running them and
      // unregistering. Required because PreCloseRegistry uses a static list.
      try {
        await PreCloseRegistry.runAll();
      } catch (_) {
        // Tolerate failures from leftover callbacks.
      }
    });

    test('runAll מריץ את כל ה-callbacks שנרשמו', () async {
      var callOne = 0;
      var callTwo = 0;
      Future<void> one() async => callOne++;
      Future<void> two() async => callTwo++;

      PreCloseRegistry.register(one);
      PreCloseRegistry.register(two);
      try {
        await PreCloseRegistry.runAll();
        expect(callOne, 1, reason: 'callback ראשון צריך לרוץ פעם אחת');
        expect(callTwo, 1, reason: 'callback שני צריך לרוץ פעם אחת');
      } finally {
        PreCloseRegistry.unregister(one);
        PreCloseRegistry.unregister(two);
      }
    });

    test(
      'runAll מבצע retry פעם נוספת אחרי כישלון ולא זורק אם הניסיון השני הצליח',
      () async {
        var attempts = 0;
        Future<void> flakyCallback() async {
          attempts++;
          if (attempts == 1) {
            throw StateError('כישלון בניסיון ראשון');
          }
        }

        PreCloseRegistry.register(flakyCallback);
        try {
          await PreCloseRegistry.runAll();
          expect(
            attempts,
            2,
            reason: 'אמור היה לרוץ פעמיים — ניסיון ראשון נכשל, ושני הצליח',
          );
        } finally {
          PreCloseRegistry.unregister(flakyCallback);
        }
      },
    );

    test(
      'runAll זורק PreCloseFlushFailure כשcallback נכשל בשני הניסיונות',
      () async {
        Future<void> alwaysFails() async {
          throw StateError('תמיד נכשל');
        }

        PreCloseRegistry.register(alwaysFails);
        try {
          await expectLater(
            PreCloseRegistry.runAll(),
            throwsA(isA<PreCloseFlushFailure>()),
            reason: 'callback שנכשל פעמיים צריך לגרום ל-PreCloseFlushFailure',
          );
        } finally {
          PreCloseRegistry.unregister(alwaysFails);
        }
      },
    );

    test('runAll ממשיך לקרוא לכל ה-callbacks גם אם אחד מהם נכשל', () async {
      var afterFailureRan = false;
      Future<void> failingCallback() async {
        throw StateError('boom');
      }

      Future<void> goodCallback() async {
        afterFailureRan = true;
      }

      PreCloseRegistry.register(failingCallback);
      PreCloseRegistry.register(goodCallback);
      try {
        await expectLater(
          PreCloseRegistry.runAll(),
          throwsA(isA<PreCloseFlushFailure>()),
        );
        expect(
          afterFailureRan,
          isTrue,
          reason:
              'callback מאוחר חייב לרוץ גם אם אחד לפניו נכשל — אחרת '
              'נאבד נתונים של HistoryBloc וכו\' כשטעות אחת בולעת את כל המסלול',
        );
      } finally {
        PreCloseRegistry.unregister(failingCallback);
        PreCloseRegistry.unregister(goodCallback);
      }
    });

    test('unregister מסיר callback ומונע ממנו לרוץ', () async {
      var calls = 0;
      Future<void> callback() async => calls++;

      PreCloseRegistry.register(callback);
      PreCloseRegistry.unregister(callback);
      await PreCloseRegistry.runAll();

      expect(
        calls,
        0,
        reason: 'אחרי unregister, ה-callback לא אמור להיקרא ב-runAll',
      );
    });

    test('runAll על registry ריק לא זורק', () async {
      await expectLater(PreCloseRegistry.runAll(), completes);
    });

    test(
      'runAll מריץ במיוחד פעולה איטית — כדי לוודא שלא מאבדים ניתוב כתיבות',
      () async {
        var ran = false;
        Future<void> slowCallback() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          ran = true;
        }

        PreCloseRegistry.register(slowCallback);
        try {
          await PreCloseRegistry.runAll();
          expect(
            ran,
            isTrue,
            reason:
                'callback איטי חייב להיגמר לפני ש-runAll חוזר — אחרת כתיבות '
                'עדיין pending כשהתהליך יוצא',
          );
        } finally {
          PreCloseRegistry.unregister(slowCallback);
        }
      },
    );
  });
}
