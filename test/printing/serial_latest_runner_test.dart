import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/printing/serial_latest_runner.dart';

void main() {
  group('SerialLatestRunner', () {
    test('מריץ משימה בודדת ושומר את תוצאתה ב-lastResult', () async {
      final runner = SerialLatestRunner<int>();
      expect(runner.lastResult, isNull);

      final result = await runner.run(
        isStale: () => false,
        task: () async => 42,
      );

      expect(result, 42);
      expect(runner.lastResult, 42);
    });

    test('מריץ משימות בסדרה — אין חפיפה בין משימות', () async {
      final runner = SerialLatestRunner<int>();
      var active = 0;
      var maxActive = 0;

      Future<int> tracked(int value) async {
        active++;
        maxActive = maxActive > active ? maxActive : active;
        await Future.delayed(const Duration(milliseconds: 10));
        active--;
        return value;
      }

      await Future.wait([
        for (var i = 0; i < 5; i++)
          runner.run(isStale: () => false, task: () => tracked(i)),
      ]);

      expect(maxActive, 1, reason: 'רק משימה אחת רצה בכל רגע');
    });

    test('שומר על סדר ה-FIFO של המשימות בתור', () async {
      final runner = SerialLatestRunner<int>();
      final order = <int>[];

      final futures = [
        for (var i = 0; i < 4; i++)
          runner.run(
            isStale: () => false,
            task: () async {
              await Future.delayed(const Duration(milliseconds: 5));
              order.add(i);
              return i;
            },
          ),
      ];
      await Future.wait(futures);

      expect(order, [0, 1, 2, 3]);
    });

    test('מדלג על משימה מיושנת ומחזיר את התוצאה הקודמת', () async {
      final runner = SerialLatestRunner<int>();
      var staleTaskRan = false;

      // משימה ראשונה תקפה — קובעת lastResult.
      await runner.run(isStale: () => false, task: () async => 1);

      // משימה שנייה מיושנת — אסור שתבצע את ה-task.
      final result = await runner.run(
        isStale: () => true,
        task: () async {
          staleTaskRan = true;
          return 2;
        },
      );

      expect(staleTaskRan, isFalse, reason: 'משימה מיושנת לא רצה');
      expect(result, 1, reason: 'מוחזרת התוצאה התקפה הקודמת');
      expect(runner.lastResult, 1);
    });

    test('מבצע משימה מיושנת כשאין עדיין תוצאה קודמת', () async {
      final runner = SerialLatestRunner<int>();
      var ran = false;

      final result = await runner.run(
        isStale: () => true,
        task: () async {
          ran = true;
          return 7;
        },
      );

      expect(ran, isTrue, reason: 'בלי תוצאה קודמת אין מה להחזיר — חייב לרוץ');
      expect(result, 7);
      expect(runner.lastResult, 7);
    });

    test('isStale נבדק רק לאחר ההמתנה בתור', () async {
      final runner = SerialLatestRunner<int>();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();

      // תוצאה קודמת קיימת כדי שדילוג יהיה אפשרי.
      await runner.run(isStale: () => false, task: () async => 100);

      // משימה ראשונה ארוכה שמחזיקה את התור.
      final first = runner.run(
        isStale: () => false,
        task: () async {
          firstStarted.complete();
          await releaseFirst.future;
          return 1;
        },
      );

      await firstStarted.future;

      // משימה שנייה נכנסת לתור בעודה לא-מיושנת, אך מתיישנת לפני שתורה מגיע.
      var secondMutableStale = false;
      var secondTaskRan = false;
      final second = runner.run(
        isStale: () => secondMutableStale,
        task: () async {
          secondTaskRan = true;
          return 2;
        },
      );

      // הופכים אותה למיושנת בזמן שהיא עדיין ממתינה בתור.
      secondMutableStale = true;
      releaseFirst.complete();

      expect(await first, 1);
      final secondResult = await second;

      expect(
        secondTaskRan,
        isFalse,
        reason: 'התיישנה בזמן ההמתנה — מדולגת אף שנכנסה תקפה',
      );
      // מוחזרת התוצאה התקפה העדכנית ביותר — של המשימה הארוכה שהשלימה לפניה (1),
      // ולא 100 שקדם לה.
      expect(secondResult, 1);
    });

    test('משימה אחרונה תקפה רצה גם כשקודמותיה מיושנות', () async {
      final runner = SerialLatestRunner<int>();
      var generation = 0;
      final ranTasks = <int>[];

      await runner.run(isStale: () => false, task: () async => -1);

      // שלוש משימות מהירות זו אחר זו; כל אחת מקדמת generation,
      // כך שהקודמות הופכות מיושנות עד שתורן מגיע — רק האחרונה רצה.
      final futures = <Future<int>>[];
      for (var i = 0; i < 3; i++) {
        final entered = ++generation;
        futures.add(
          runner.run(
            isStale: () => entered != generation,
            task: () async {
              ranTasks.add(i);
              return i;
            },
          ),
        );
      }
      await Future.wait(futures);

      expect(ranTasks, [2], reason: 'רק המשימה האחרונה (התקפה) ביצעה עבודה');
      expect(runner.lastResult, 2);
    });

    test('שגיאה במשימה משחררת את התור ולא תוקעת משימות הבאות', () async {
      final runner = SerialLatestRunner<int>();

      await expectLater(
        runner.run(
          isStale: () => false,
          task: () async => throw StateError('boom'),
        ),
        throwsStateError,
      );

      // התור חייב להשתחרר — המשימה הבאה רצה כרגיל.
      final result = await runner.run(
        isStale: () => false,
        task: () async => 5,
      );
      expect(result, 5);
      expect(runner.lastResult, 5);
    });
  });
}
