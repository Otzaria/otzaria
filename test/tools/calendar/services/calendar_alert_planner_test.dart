import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_planner.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

CustomEvent _event(
  String id, {
  required DateTime date,
  RecurrenceType recurrence = RecurrenceType.none,
  TimeOfDay? time,
  int? minutes,
}) => CustomEvent(
  id: id,
  title: 'אירוע $id',
  description: 'תיאור',
  createdAt: DateTime(2026),
  baseGregorianDate: date,
  baseJewishYear: 5787,
  baseJewishMonth: 7,
  baseJewishDay: 1,
  recurrenceType: recurrence,
  recurringYears: null,
  eventTime: time,
  notificationMinutes: minutes,
);

void main() {
  tz_data.initializeTimeZones();

  int zmanId(String timeId, DateTime date) =>
      '$timeId|${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}'
          .hashCode &
      0x7fffffff;

  group('planZmanAlerts', () {
    // החלון חוצה את סוף שעון הקיץ בישראל (25.10.2026).
    final now = DateTime(2026, 10, 20, 0, 1);
    const alerts = {
      'sunrise': ZmanAlertPreference(minutesBefore: 15, displayName: 'הנץ'),
    };

    test('every calendar day of the window is planned once', () {
      final plan = CalendarAlertPlanner.planZmanAlerts(
        alerts: alerts,
        city: 'ירושלים',
        now: now,
      ).toList();

      expect(
        [for (final a in plan) DateUtils.dateOnly(a.eventDate)],
        [for (var i = 0; i <= 45; i++) DateTime(2026, 10, 20 + i)],
      );
      expect(
        plan.map((a) => a.id),
        [
          for (var i = 0; i <= 45; i++)
            zmanId('sunrise', DateTime(2026, 10, 20 + i)),
        ],
      );
    });

    test('שעת ההתראה מנוסחת לפי שעון 12 או 24 שעות', () {
      String firstBody({required bool twelveHourClock}) =>
          CalendarAlertPlanner.planZmanAlerts(
            alerts: const {
              'sunset': ZmanAlertPreference(
                minutesBefore: 10,
                displayName: 'שקיעה',
              ),
            },
            city: 'ירושלים',
            now: now,
            twelveHourClock: twelveHourClock,
          ).first.body;

      final clock = RegExp(
        r'\((\d{2}):(\d{2})\)$',
      ).firstMatch(firstBody(twelveHourClock: false))!;
      final hour = int.parse(clock[1]!);
      expect(hour, greaterThan(12));
      expect(
        firstBody(twelveHourClock: true),
        endsWith('(${hour - 12}:${clock[2]}\u200E\u00A0PM)'),
      );
    });

    test('a zman that already passed today is not planned', () {
      final plan = CalendarAlertPlanner.planZmanAlerts(
        alerts: alerts,
        city: 'ירושלים',
        now: DateTime(2026, 10, 20, 12),
      ).toList();

      expect(DateUtils.dateOnly(plan.first.eventDate), DateTime(2026, 10, 21));
    });

    test('שבת ויו״ט שומרים דקות שונות ומתוכננים רק בצאת היום המתאים', () {
      final plan = CalendarAlertPlanner.planZmanAlerts(
        alerts: const {
          'motzeiShabbos': ZmanAlertPreference(
            minutesBefore: 30,
            displayName: 'מוצאי שבת',
          ),
          'motzeiYomTov': ZmanAlertPreference(
            minutesBefore: 15,
            displayName: 'מוצאי יום טוב',
          ),
        },
        city: 'ירושלים',
        now: DateTime(2026, 4, 1),
      ).toList();

      expect(plan, isNotEmpty);
      for (final alert in plan) {
        final saturday = alert.eventDate.weekday == DateTime.saturday;
        final timeId = saturday ? 'motzeiShabbos' : 'motzeiYomTov';
        expect(alert.id, zmanId(timeId, alert.eventDate));
        expect(alert.reminderMinutes, saturday ? 30 : 15);
        if (!saturday) {
          expect(
            DateUtils.dateOnly(alert.eventDate),
            isIn([DateTime(2026, 4, 2), DateTime(2026, 4, 8)]),
          );
        }
      }
    });
  });

  group('planEventReminders', () {
    final now = DateTime(2026, 10, 20, 9);

    List<PlannedAlert> plan(List<CustomEvent> events, {bool enabled = true}) =>
        CalendarAlertPlanner.planEventReminders(
          events: events,
          enabled: enabled,
          defaultMinutes: 60,
          soundEnabled: false,
          now: now,
        );

    test('a single event keeps the id derived from its event id', () {
      final result = plan([
        _event('a', date: DateTime(2026, 10, 25), minutes: 10),
      ]);

      expect(result, [
        PlannedAlert(
          id: 'a'.hashCode,
          title: 'אירוע a',
          body: 'תיאור',
          eventDate: DateTime(2026, 10, 25, 12),
          reminderMinutes: 10,
          soundEnabled: false,
        ),
      ]);
    });

    test('a weekly event plans each occurrence in the window', () {
      final result = plan([
        _event(
          'w',
          date: DateTime(2026, 10, 1),
          recurrence: RecurrenceType.weekly,
          time: const TimeOfDay(hour: 20, minute: 0),
        ),
      ]);

      final expectedDates = [
        for (
          var d = DateTime(2026, 10, 22);
          !d.isAfter(DateTime(2026, 12, 21));
          d = DateTime(d.year, d.month, d.day + 7)
        )
          d,
      ];
      expect(result.map((a) => a.id), [
        for (final d in expectedDates) 'w${d.year}${d.month}${d.day}'.hashCode,
      ]);
      expect(result.every((a) => a.reminderMinutes == 60), isTrue);
    });

    test('past events and disabled reminders plan nothing', () {
      expect(plan([_event('p', date: DateTime(2026, 10, 1))]), isEmpty);
      expect(
        plan([_event('a', date: DateTime(2026, 10, 25))], enabled: false),
        isEmpty,
      );
    });
  });
}
