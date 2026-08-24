import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/trackpad_axis_lock.dart';

void main() {
  // שעון בקרה: מאפשר לקדם את הזמן בטסטים בלי להמתין בפועל.
  late DateTime fakeNow;
  DateTime clock() => fakeNow;

  PointerScrollEvent scrollEvent(double dx, double dy) {
    return PointerScrollEvent(
      timeStamp: Duration.zero,
      kind: PointerDeviceKind.trackpad,
      device: 1,
      position: const Offset(100, 100),
      scrollDelta: Offset(dx, dy),
    );
  }

  setUp(() {
    fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
  });

  group('TrackpadAxisLock - הכרעה ראשונית', () {
    test('מחווה כמעט-אנכית נועלת את הציר לאנכי ומאפסת את ה-dx', () {
      final lock = TrackpadAxisLock(clock: clock);
      final result = lock.apply(scrollEvent(3, 20)) as PointerScrollEvent;

      expect(lock.lockedAxis, Axis.vertical);
      expect(result.scrollDelta, const Offset(0, 20));
    });

    test('מחווה כמעט-אופקית נועלת את הציר לאופקי ומאפסת את ה-dy', () {
      final lock = TrackpadAxisLock(clock: clock);
      final result = lock.apply(scrollEvent(25, 4)) as PointerScrollEvent;

      expect(lock.lockedAxis, Axis.horizontal);
      expect(result.scrollDelta, const Offset(25, 0));
    });

    test('מחווה אלכסונית מוכרעת כחופשית ועוברת ללא קיצוץ (issue #969)', () {
      final lock = TrackpadAxisLock(clock: clock);
      final event = scrollEvent(10, 10);
      final result = lock.apply(event);

      expect(lock.lockedAxis, isNull);
      expect(lock.isFreeGesture, isTrue);
      expect(identical(result, event), isTrue);
    });

    test('מחווה בשיפוע בינוני (בין 18° ל-45°) נשארת חופשית', () {
      final lock = TrackpadAxisLock(clock: clock);
      final event = scrollEvent(10, 20);
      final result = lock.apply(event);

      expect(lock.lockedAxis, isNull);
      expect(lock.isFreeGesture, isTrue);
      expect(identical(result, event), isTrue);
    });

    test('delta אפסי לא מכריע ומוחזר כמו שהוא', () {
      final lock = TrackpadAxisLock(clock: clock);
      final event = scrollEvent(0, 0);
      final result = lock.apply(event);

      expect(lock.lockedAxis, isNull);
      expect(lock.isFreeGesture, isFalse);
      expect(identical(result, event), isTrue);
    });
  });

  group('TrackpadAxisLock - הכרעה מצטברת (לא מהאירוע הראשון)', () {
    test('אירועים קטנים מתחת לסף לא מכריעים ועוברים ללא שינוי', () {
      final lock = TrackpadAxisLock(clock: clock, decisionDistance: 8.0);
      final event = scrollEvent(1, 2);
      final result = lock.apply(event);

      expect(lock.lockedAxis, isNull);
      expect(lock.isFreeGesture, isFalse);
      expect(identical(result, event), isTrue);
    });

    test('ההכרעה מתקבלת מהכיוון המצטבר ולא מהדגימה הראשונה הרועשת', () {
      final lock = TrackpadAxisLock(clock: clock, decisionDistance: 8.0);

      // דגימה ראשונה רועשת שנוטה הצידה - לא מכריעה.
      lock.apply(scrollEvent(2, 1));
      expect(lock.lockedAxis, isNull);

      // ההמשך אנכי מובהק - הצבירה (2, 21) מכריעה לאנכי.
      fakeNow = fakeNow.add(const Duration(milliseconds: 20));
      final result = lock.apply(scrollEvent(0, 20)) as PointerScrollEvent;
      expect(lock.lockedAxis, Axis.vertical);
      expect(result.scrollDelta, const Offset(0, 20));
    });
  });

  group('TrackpadAxisLock - יציבות ההכרעה ברצף', () {
    test('אירועים רצופים שומרים על הציר הנעול גם אם הציר השני מתחזק', () {
      final lock = TrackpadAxisLock(clock: clock);

      lock.apply(scrollEvent(2, 15));
      expect(lock.lockedAxis, Axis.vertical);

      // אחרי 50ms - בתוך החלון הרציף.
      fakeNow = fakeNow.add(const Duration(milliseconds: 50));
      final result = lock.apply(scrollEvent(30, 5)) as PointerScrollEvent;

      // הציר נשאר אנכי למרות שעכשיו dx גדול יותר.
      expect(lock.lockedAxis, Axis.vertical);
      expect(result.scrollDelta, const Offset(0, 5));
    });

    test('מחווה שהוכרעה כחופשית נשארת חופשית גם כשההמשך אנכי', () {
      final lock = TrackpadAxisLock(clock: clock);

      lock.apply(scrollEvent(10, 10));
      expect(lock.isFreeGesture, isTrue);

      fakeNow = fakeNow.add(const Duration(milliseconds: 50));
      final event = scrollEvent(0, 25);
      final result = lock.apply(event);

      expect(lock.isFreeGesture, isTrue);
      expect(identical(result, event), isTrue);
    });

    test('גלילה ברצף בציר הנעול מחזירה את האירוע המקורי ללא שינוי', () {
      final lock = TrackpadAxisLock(clock: clock);
      lock.apply(scrollEvent(0, 20));

      fakeNow = fakeNow.add(const Duration(milliseconds: 30));
      final event = scrollEvent(0, 25);
      final result = lock.apply(event);

      // אין שינוי - מחזיר את אותו אירוע (אופטימיזציה).
      expect(identical(result, event), isTrue);
    });
  });

  group('TrackpadAxisLock - שחרור אחרי הפסקה', () {
    test('אחרי הפסקה > idleReset הנעילה משתחררת', () {
      final lock = TrackpadAxisLock(
        clock: clock,
        idleReset: const Duration(milliseconds: 150),
      );

      lock.apply(scrollEvent(0, 20));
      expect(lock.lockedAxis, Axis.vertical);

      // הפסקה ארוכה = הרמת אצבעות.
      fakeNow = fakeNow.add(const Duration(milliseconds: 200));
      final result = lock.apply(scrollEvent(30, 2)) as PointerScrollEvent;

      // ננעל מחדש - הפעם לאופקי.
      expect(lock.lockedAxis, Axis.horizontal);
      expect(result.scrollDelta, const Offset(30, 0));
    });

    test('אחרי הפסקה גם הכרעת "חופשי" מתאפסת', () {
      final lock = TrackpadAxisLock(
        clock: clock,
        idleReset: const Duration(milliseconds: 150),
      );

      lock.apply(scrollEvent(10, 10));
      expect(lock.isFreeGesture, isTrue);

      fakeNow = fakeNow.add(const Duration(milliseconds: 200));
      final result = lock.apply(scrollEvent(2, 20)) as PointerScrollEvent;

      expect(lock.isFreeGesture, isFalse);
      expect(lock.lockedAxis, Axis.vertical);
      expect(result.scrollDelta, const Offset(0, 20));
    });

    test('הפסקה השווה ל-idleReset בדיוק עדיין נחשבת רצף', () {
      final lock = TrackpadAxisLock(
        clock: clock,
        idleReset: const Duration(milliseconds: 150),
      );

      lock.apply(scrollEvent(0, 20));

      fakeNow = fakeNow.add(const Duration(milliseconds: 150));
      lock.apply(scrollEvent(30, 5));

      // הציר נשאר אנכי כי הפער == idleReset (לא גדול ממנו).
      expect(lock.lockedAxis, Axis.vertical);
    });
  });

  group('TrackpadAxisLock - applyDelta (מסלול מחוות ה-pan)', () {
    test('מחווה כמעט-אנכית ננעלת ומקצצת את רכיב ה-dx', () {
      final lock = TrackpadAxisLock();

      expect(lock.applyDelta(const Offset(1, 20)), const Offset(0, 20));
      expect(lock.lockedAxis, Axis.vertical);
      expect(lock.applyDelta(const Offset(6, 10)), const Offset(0, 10));
    });

    test('מחווה אלכסונית עוברת חופשי ללא קיצוץ', () {
      final lock = TrackpadAxisLock();

      expect(lock.applyDelta(const Offset(12, 15)), const Offset(12, 15));
      expect(lock.isFreeGesture, isTrue);
      expect(lock.applyDelta(const Offset(0, 9)), const Offset(0, 9));
    });

    test('תזוזות קטנות מתחת לסף ההכרעה עוברות כמו שהן', () {
      final lock = TrackpadAxisLock(decisionDistance: 8.0);

      expect(lock.applyDelta(const Offset(1, 3)), const Offset(1, 3));
      expect(lock.lockedAxis, isNull);
      expect(lock.isFreeGesture, isFalse);
    });

    test('reset() בסוף מחווה מאפשר הכרעה חדשה במחווה הבאה', () {
      final lock = TrackpadAxisLock();

      lock.applyDelta(const Offset(0, 20));
      expect(lock.lockedAxis, Axis.vertical);

      lock.reset();
      expect(lock.lockedAxis, isNull);

      expect(lock.applyDelta(const Offset(20, 1)), const Offset(20, 0));
      expect(lock.lockedAxis, Axis.horizontal);
    });
  });

  group('TrackpadAxisLock - מקרי קצה', () {
    test('Ctrl לחוץ - האירוע עובר ללא שינוי והנעילה מתאפסת', () {
      final lock = TrackpadAxisLock(clock: clock);
      lock.apply(scrollEvent(0, 20));
      expect(lock.lockedAxis, Axis.vertical);

      final event = scrollEvent(5, 15);
      final result = lock.apply(event, isControlPressed: true);

      expect(identical(result, event), isTrue);
      expect(lock.lockedAxis, isNull);
    });

    test('אירוע שאינו PointerScrollEvent מוחזר כמו שהוא', () {
      final lock = TrackpadAxisLock(clock: clock);
      final event = const PointerScaleEvent(
        position: Offset(100, 100),
        scale: 1.2,
      );

      final result = lock.apply(event);
      expect(identical(result, event), isTrue);
      expect(lock.lockedAxis, isNull);
    });

    test('reset() מאפסת את המצב הפנימי', () {
      final lock = TrackpadAxisLock(clock: clock);
      lock.apply(scrollEvent(0, 20));
      expect(lock.lockedAxis, Axis.vertical);

      lock.reset();
      expect(lock.lockedAxis, isNull);

      // האירוע הבא מכריע מחדש.
      final result = lock.apply(scrollEvent(30, 2)) as PointerScrollEvent;
      expect(lock.lockedAxis, Axis.horizontal);
      expect(result.scrollDelta, const Offset(30, 0));
    });
  });

  group('TrackpadAxisLock - תרחיש משולב', () {
    test('גלילה אנכית, הפסקה, גלילה אופקית, הפסקה, אלכסון חופשי', () {
      final lock = TrackpadAxisLock(
        clock: clock,
        idleReset: const Duration(milliseconds: 150),
      );

      // שלב 1: גלילה אנכית ארוכה - המשתמש גולל למטה ואצבעותיו זזות
      // קצת לצדדים תוך כדי. הציר נשאר נעול לאנכי.
      var result = lock.apply(scrollEvent(0, 20)) as PointerScrollEvent;
      expect(result.scrollDelta, const Offset(0, 20));

      fakeNow = fakeNow.add(const Duration(milliseconds: 30));
      result = lock.apply(scrollEvent(8, 18)) as PointerScrollEvent;
      expect(result.scrollDelta, const Offset(0, 18));

      fakeNow = fakeNow.add(const Duration(milliseconds: 30));
      result = lock.apply(scrollEvent(12, 15)) as PointerScrollEvent;
      expect(result.scrollDelta, const Offset(0, 15));

      // שלב 2: המשתמש מרים אצבעות (הפסקה ארוכה) ומתחיל גלילה אופקית.
      fakeNow = fakeNow.add(const Duration(milliseconds: 500));
      result = lock.apply(scrollEvent(25, 3)) as PointerScrollEvent;
      expect(lock.lockedAxis, Axis.horizontal);
      expect(result.scrollDelta, const Offset(25, 0));

      // שלב 3: שוב הרמת אצבעות, והפעם תנועה אלכסונית - חופשית לגמרי.
      fakeNow = fakeNow.add(const Duration(milliseconds: 500));
      final diagonal = scrollEvent(15, 18);
      final freeResult = lock.apply(diagonal);
      expect(lock.isFreeGesture, isTrue);
      expect(identical(freeResult, diagonal), isTrue);
    });
  });
}
