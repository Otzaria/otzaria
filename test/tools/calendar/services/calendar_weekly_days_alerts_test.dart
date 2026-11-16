import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_planner.dart';

void main() {
  test('notifications follow selected weekdays and skip all other days', () {
    final event = CustomEvent(
      id: 'lesson',
      title: 'שיעור',
      description: '',
      createdAt: DateTime(2026, 10, 1),
      baseGregorianDate: DateTime(2026, 10, 1),
      baseJewishYear: 5787,
      baseJewishMonth: 7,
      baseJewishDay: 20,
      recurrenceType: RecurrenceType.weekly,
      weeklyDays: [DateTime.monday, DateTime.wednesday],
      eventTime: const TimeOfDay(hour: 20, minute: 0),
    );
    final alerts = CalendarAlertPlanner.planEventReminders(
      events: [event],
      enabled: true,
      defaultMinutes: 60,
      soundEnabled: false,
      now: DateTime(2026, 10, 20, 9),
    );
    expect(alerts, isNotEmpty);
    expect(alerts.first.eventDate, DateTime(2026, 10, 21, 20));
    expect(
      alerts.map((alert) => alert.eventDate.weekday).toSet(),
      {DateTime.monday, DateTime.wednesday},
    );
    expect(alerts.map((alert) => alert.eventDate).toList(), contains(DateTime(2026, 10, 26, 20)));
    expect(alerts.map((alert) => alert.eventDate).toList(), isNot(contains(DateTime(2026, 10, 22, 20))));
  });
}
