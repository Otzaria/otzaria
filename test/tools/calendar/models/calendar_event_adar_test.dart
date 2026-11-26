import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_planner.dart';

// kosher_dart: אדר (ואדר א' בשנה מעוברת) = 12, אדר ב' = 13.
// 5784 ו-5787 מעוברות, 5785 ו-5786 פשוטות.
DateTime _hebrew(int year, int month, int day) {
  final date = (JewishDate()..setJewishDate(year, month, day))
      .getGregorianCalendar();
  return DateTime(date.year, date.month, date.day);
}

CustomEvent _annual(int year, int month, int day, {int? leapAdarMonth}) =>
    CustomEvent(
      id: 'adar',
      title: 'אירוע באדר',
      description: '',
      createdAt: DateTime(2024),
      baseGregorianDate: _hebrew(year, month, day),
      baseJewishYear: year,
      baseJewishMonth: month,
      baseJewishDay: day,
      recurrenceType: RecurrenceType.annualHebrew,
      leapAdarMonth: leapAdarMonth,
    );

void main() {
  group('Adar I/II choice for annual Hebrew events (issue #3699)', () {
    test('אירוע מאדר בשנה פשוטה, עם בחירת אדר ב׳, חל באדר ב׳', () {
      final event = _annual(5785, 12, 14, leapAdarMonth: 13);

      expect(event.occursOn(_hebrew(5786, 12, 14)), isTrue);
      expect(event.occursOn(_hebrew(5787, 13, 14)), isTrue);
      expect(event.occursOn(_hebrew(5787, 12, 14)), isFalse);
      expect(
        event.nextOccurrenceFrom(_hebrew(5786, 12, 15)),
        _hebrew(5787, 13, 14),
      );
    });

    test('בלי בחירה (אירועים קיימים) נשאר באדר א׳', () {
      final event = _annual(5785, 12, 14);

      expect(event.occursOn(_hebrew(5787, 12, 14)), isTrue);
      expect(event.occursOn(_hebrew(5787, 13, 14)), isFalse);
    });

    test('בחירה מפורשת של אדר ב׳ חלה באדר בשנה פשוטה', () {
      final event = _annual(5784, 13, 10, leapAdarMonth: 13);

      expect(event.occursOn(_hebrew(5785, 12, 10)), isTrue);
      expect(
        event.nextOccurrenceFrom(_hebrew(5784, 13, 11)),
        _hebrew(5785, 12, 10),
      );
      expect(event.occursOn(_hebrew(5787, 13, 10)), isTrue);
      expect(event.occursOn(_hebrew(5787, 12, 10)), isFalse);
    });

    test('אירוע מאדר ב׳ עם בחירת אדר א׳ חל באדר א׳', () {
      final event = _annual(5784, 13, 10, leapAdarMonth: 12);

      expect(event.occursOn(_hebrew(5787, 12, 10)), isTrue);
      expect(event.occursOn(_hebrew(5787, 13, 10)), isFalse);
    });

    test('הבחירה לא משנה חודשים אחרים ולא חזרה חודשית', () {
      final nisan = CustomEvent(
        id: 'nisan',
        title: 'ניסן',
        description: '',
        createdAt: DateTime(2024),
        baseGregorianDate: _hebrew(5785, 1, 1),
        baseJewishYear: 5785,
        baseJewishMonth: 1,
        baseJewishDay: 1,
        recurrenceType: RecurrenceType.annualHebrew,
        leapAdarMonth: 13,
      );
      expect(nisan.occursOn(_hebrew(5787, 1, 1)), isTrue);

      final monthly = _annual(
        5785,
        12,
        14,
        leapAdarMonth: 13,
      ).copyWith(recurrenceType: RecurrenceType.monthlyHebrew);
      expect(monthly.occursOn(_hebrew(5787, 12, 14)), isTrue);
      expect(monthly.occursOn(_hebrew(5787, 13, 14)), isTrue);
    });

    test('הבחירה נשמרת ב-JSON, ו-JSON ישן נטען בלעדיה', () {
      final event = _annual(5785, 12, 14, leapAdarMonth: 13);
      final restored = CustomEvent.fromJson(event.toJson());
      expect(restored.leapAdarMonth, 13);
      expect(restored, event);

      final legacy = event.toJson()..remove('leapAdarMonth');
      expect(CustomEvent.fromJson(legacy).leapAdarMonth, isNull);
      expect(
        CustomEvent.fromJson({...legacy, 'leapAdarMonth': 7}).leapAdarMonth,
        isNull,
      );
      expect(
        event.copyWith(leapAdarMonth: () => null).leapAdarMonth,
        isNull,
      );
    });

    test('חיפוש לפני תחילת הסדרה מחזיר את אדר שנבחר', () {
      final event = _annual(5787, 12, 14, leapAdarMonth: 13);
      final actual = _hebrew(5787, 13, 14);

      expect(event.occursOn(_hebrew(5787, 12, 14)), isFalse);
      expect(event.occursOn(actual), isTrue);
      expect(event.nextOccurrenceFrom(_hebrew(5787, 11, 29)), actual);
    });

    test('בחירה באדר א׳ אינה יוצרת מופע לפני תאריך הבסיס', () {
      final event = _annual(5787, 13, 14, leapAdarMonth: 12);

      expect(event.occursOn(_hebrew(5787, 12, 14)), isFalse);
      expect(
        event.nextOccurrenceFrom(_hebrew(5787, 11, 29)),
        _hebrew(5788, 12, 14),
      );
    });

    test('חזרה לועזית שומרת על תאריך הבסיס לפני תחילת הסדרה', () {
      final event = _annual(5787, 12, 14, leapAdarMonth: 13).copyWith(
        baseGregorianDate: DateTime(2027, 3, 1),
        recurrenceType: RecurrenceType.annualGregorian,
      );

      expect(
        event.nextOccurrenceFrom(DateTime(2027, 1, 1)),
        DateTime(2027, 3, 1),
      );
      expect(
        event.nextOccurrenceFrom(DateTime(2027, 3, 2)),
        DateTime(2028, 3, 1),
      );
    });

    test('כ״ט יכול לחזור בכל אדר ול׳ יכול לחזור רק באדר א׳', () {
      final day29 = _annual(5787, 12, 29, leapAdarMonth: 13);
      expect(day29.occursOn(_hebrew(5787, 13, 29)), isTrue);
      expect(day29.occursOn(_hebrew(5788, 12, 29)), isTrue);

      final day30 = _annual(5787, 12, 30, leapAdarMonth: 12);
      final inLeap = _hebrew(5787, 11, 1);
      final inPlain = _hebrew(5788, 11, 1);
      expect(day30.occurrenceCandidate(inLeap, 0), _hebrew(5787, 12, 30));
      expect(day30.occurrenceCandidate(inPlain, 0), isNull);
      expect(day30.occursOn(_hebrew(5788, 12, 29)), isFalse);

      final invalid = day30.copyWith(leapAdarMonth: () => 13);
      expect(invalid.occurrenceCandidate(inLeap, 0), isNull);
      expect(invalid.occursOn(_hebrew(5787, 13, 29)), isFalse);
    });

    test('ההתראה נקבעת לאדר שנבחר', () {
      List<DateTime> alertDates(CustomEvent event, DateTime now) =>
          CalendarAlertPlanner.planEventReminders(
            events: [event],
            enabled: true,
            defaultMinutes: 0,
            soundEnabled: false,
            now: now,
          ).map((alert) {
            final d = alert.eventDate;
            return DateTime(d.year, d.month, d.day);
          }).toList();

      // המתכנן קובע את מופע השנה הזו ואת של השנה הבאה (5788 פשוטה).
      final leapNow = _hebrew(5787, 11, 20);
      expect(alertDates(_annual(5785, 12, 14, leapAdarMonth: 13), leapNow), [
        _hebrew(5787, 13, 14),
        _hebrew(5788, 12, 14),
      ]);
      expect(alertDates(_annual(5785, 12, 14), leapNow), [
        _hebrew(5787, 12, 14),
        _hebrew(5788, 12, 14),
      ]);
      expect(
        alertDates(
          _annual(5784, 13, 10, leapAdarMonth: 13),
          _hebrew(5785, 11, 20),
        ),
        [
          _hebrew(5785, 12, 10),
          _hebrew(5786, 12, 10),
        ],
      );
      final legacyJson = _annual(5784, 13, 10).toJson()
        ..remove('recurrenceType')
        ..['recurring'] = true
        ..['recurOnHebrew'] = true;
      final legacy = CustomEvent.fromJson(legacyJson);
      expect(legacy.toJson(), isNot(contains('leapAdarMonth')));
      expect(alertDates(legacy, _hebrew(5785, 11, 20)), isEmpty);
      expect(legacy.occursOn(_hebrew(5785, 12, 10)), isFalse);
      expect(
        legacy.nextOccurrenceFrom(_hebrew(5785, 1, 1)),
        _hebrew(5787, 13, 10),
      );
    });
  });
}
