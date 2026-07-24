import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/http_client_registry.dart';

void main() {
  // HttpClientRegistry קריטי לסגירת התוכנה ב-Windows admin install: socket
  // פתוח שנשאר מחזיק את ה-process בקרנל לכמה שניות (Defender real-time scan
  // של handles ביציאה). הטסטים מכסים את ההנחות שעליהן ה-callers מסתמכים:
  // הסרת רישום, אי-קריסה על closer יחיד שנכשל, ותקרת timeout מובטחת.

  setUp(() {
    HttpClientRegistry.clearForTest();
  });

  tearDown(() {
    HttpClientRegistry.clearForTest();
  });

  group('register / unregister', () {
    test('register מוסיף ל-registry; unregister מסיר', () {
      void noop() {}

      expect(HttpClientRegistry.registeredCount, 0);
      HttpClientRegistry.register(noop);
      expect(HttpClientRegistry.registeredCount, 1);
      HttpClientRegistry.unregister(noop);
      expect(HttpClientRegistry.registeredCount, 0);
    });

    test('register של אותו closer פעמיים → שני רישומים נפרדים', () {
      void noop() {}

      HttpClientRegistry.register(noop);
      HttpClientRegistry.register(noop);

      // חשוב: יש בעלים שיכולים להירשם פעמיים בטעות (למשל מופעים חוזרים של
      // אותו BLoC). השפעה רעה ביותר היא שהקריאה לסגירה תרוץ פעמיים, וזה לא
      // אמור לקרוס — Client.close() ב-package:http הוא idempotent.
      expect(HttpClientRegistry.registeredCount, 2);
    });

    test('unregister על closer שלא רשום הוא no-op', () {
      void neverRegistered() {}

      // לא אמור לזרוק.
      HttpClientRegistry.unregister(neverRegistered);
      expect(HttpClientRegistry.registeredCount, 0);
    });
  });

  group('closeAll', () {
    test('קורא לכל ה-closers שנרשמו (sync ו-async)', () async {
      var syncCalled = false;
      var asyncCalled = false;

      HttpClientRegistry.register(() => syncCalled = true);
      HttpClientRegistry.register(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        asyncCalled = true;
      });

      await HttpClientRegistry.closeAll();

      expect(syncCalled, isTrue);
      expect(
        asyncCalled,
        isTrue,
        reason: 'closer async חייב להמתין לסיומו לפני closeAll מחזיר',
      );
    });

    test('closeAll על registry ריק חוזר מיד בלי לזרוק', () async {
      final sw = Stopwatch()..start();
      await HttpClientRegistry.closeAll();
      sw.stop();
      // אם הוא ממתין סתם ל-timeout כשאין מה לסגור, זה bug.
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('closer שזורק לא חוסם את ה-closers האחרים', () async {
      var goodCalled = false;

      HttpClientRegistry.register(() => throw StateError('boom sync'));
      HttpClientRegistry.register(() async {
        throw StateError('boom async');
      });
      HttpClientRegistry.register(() => goodCalled = true);

      // closeAll לא אמור לזרוק — אסור שיציאה תיחסם על closer בודד.
      await expectLater(HttpClientRegistry.closeAll(), completes);
      expect(
        goodCalled,
        isTrue,
        reason: 'closer לאחר זורק חייב לרוץ — בידוד שגיאות הוא הליבה של החוזה',
      );
    });

    test(
      'closeAll נחתך ב-timeout כש-closer נתקע, ולא חוסם את היציאה',
      () async {
        var hangingStarted = false;
        var fastCalled = false;
        final hangingCompleter = Completer<void>();

        HttpClientRegistry.register(() async {
          hangingStarted = true;
          // לא נסיים לעולם בלי טריגר חיצוני.
          await hangingCompleter.future;
        });
        HttpClientRegistry.register(() => fastCalled = true);

        final sw = Stopwatch()..start();
        try {
          await HttpClientRegistry.closeAll(
            timeout: const Duration(milliseconds: 100),
          );
        } finally {
          // לפתוח את ה-completer כדי לא להשאיר Future מיותר ל-tearDown.
          hangingCompleter.complete();
        }
        sw.stop();

        expect(hangingStarted, isTrue);
        expect(
          fastCalled,
          isTrue,
          reason: 'closer מהיר חייב להספיק לרוץ במקביל',
        );
        // timeout 100ms + buffer של framework. עיקר הבדיקה: לא 5 שניות.
        expect(
          sw.elapsedMilliseconds,
          lessThan(800),
          reason: 'אם closer תקוע יחסום את closeAll, פג ה-timeout לא הצליח',
        );
      },
    );

    test('closeAll רץ במקביל — לא סדרתי', () async {
      // אם closers רצים סדרתית, זמן closeAll הוא סכום הזמנים שלהם.
      // אם במקביל, הוא כזמן של הארוך ביותר.
      const closerDelay = Duration(milliseconds: 60);

      for (var i = 0; i < 4; i++) {
        HttpClientRegistry.register(
          () async => await Future<void>.delayed(closerDelay),
        );
      }

      final sw = Stopwatch()..start();
      await HttpClientRegistry.closeAll(
        timeout: const Duration(milliseconds: 800),
      );
      sw.stop();

      // סדרתי = 240ms+, מקביל = 60ms+. נדרוש <150ms כדי להבטיח מקביל.
      expect(
        sw.elapsedMilliseconds,
        lessThan(150),
        reason:
            'closeAll חייב להריץ closers במקביל — סדרתי יבטל את ההנחה '
            'שסגירה כוללת תיגמר בתוך budget קצר',
      );
    });

    test(
      'snapshot של ה-closers בזמן closeAll: register במהלך הריצה לא משנה',
      () async {
        var firstCalled = false;
        var lateRegisteredCalled = false;

        void lateCloser() {
          lateRegisteredCalled = true;
        }

        HttpClientRegistry.register(() async {
          firstCalled = true;
          // רישום client חדש באמצע closeAll — סדר אופייני אם BLoC מאתחל
          // לעצמו לקוח במהלך dispose של BLoC אחר.
          HttpClientRegistry.register(lateCloser);
        });

        await HttpClientRegistry.closeAll();

        expect(firstCalled, isTrue);
        expect(
          lateRegisteredCalled,
          isFalse,
          reason:
              'closer שנרשם תוך כדי closeAll לא צריך להיקרא ב-iteration '
              'הנוכחית — אחרת iteration אינסופי אם הוא רושם עוד',
        );

        // נקה כדי לא להשפיע על tearDown.
        HttpClientRegistry.unregister(lateCloser);
      },
    );
  });
}
