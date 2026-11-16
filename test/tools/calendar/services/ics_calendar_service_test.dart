import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/services/ics_calendar_service.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('IcsCalendarService.parseIcs', () {
    test('מפענח אירוע יום שלם עם טווח רב-יומי (DTEND בלעדי)', () {
      const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:evt1@google.com
DTSTART;VALUE=DATE:20260310
DTEND;VALUE=DATE:20260312
SUMMARY:חופשה
END:VEVENT
END:VCALENDAR
''';
      final events = IcsCalendarService.parseIcs(ics);
      expect(events, hasLength(1));
      final event = events.single;
      expect(event.title, 'חופשה');
      expect(event.baseGregorianDate, DateTime(2026, 3, 10));
      expect(event.endGregorianDate, DateTime(2026, 3, 11));
      expect(event.eventTime, isNull);
      expect(event.recurrenceType, RecurrenceType.none);
    });

    test('מפענח אירוע עם שעה (זמן צף) כולל שעת סיום', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt2
DTSTART:20260415T093000
DTEND:20260415T103000
SUMMARY:פגישה
END:VEVENT
END:VCALENDAR
''';
      final event = IcsCalendarService.parseIcs(ics).single;
      expect(event.baseGregorianDate, DateTime(2026, 4, 15));
      expect(event.eventTime, const TimeOfDay(hour: 9, minute: 30));
      expect(event.endTime, const TimeOfDay(hour: 10, minute: 30));
      expect(event.endGregorianDate, isNull);
    });

    test('ממיר שעת UTC (סיומת Z) לשעה מקומית', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt-utc
DTSTART:20260415T120000Z
SUMMARY:אירוע UTC
END:VEVENT
END:VCALENDAR
''';
      final event = IcsCalendarService.parseIcs(ics).single;
      final expected = DateTime.utc(2026, 4, 15, 12).toLocal();
      expect(
        event.eventTime,
        TimeOfDay(hour: expected.hour, minute: expected.minute),
      );
    });

    test('ממיר שעה עם TZID לשעה מקומית', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt-tzid
DTSTART;TZID=Asia/Jerusalem:20260415T100000
SUMMARY:אירוע ירושלים
END:VEVENT
END:VCALENDAR
''';
      final event = IcsCalendarService.parseIcs(ics).single;
      final location = tz.getLocation('Asia/Jerusalem');
      final expected = tz.TZDateTime(location, 2026, 4, 15, 10).toLocal();
      expect(
        event.baseGregorianDate,
        DateTime(expected.year, expected.month, expected.day),
      );
      expect(
        event.eventTime,
        TimeOfDay(hour: expected.hour, minute: expected.minute),
      );
    });

    test('מפענח RRULE שנתי עם UNTIL', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt3
DTSTART;VALUE=DATE:20260101
RRULE:FREQ=YEARLY;UNTIL=20280101T000000Z
SUMMARY:יום שנה
END:VEVENT
END:VCALENDAR
''';
      final event = IcsCalendarService.parseIcs(ics).single;
      expect(event.recurrenceType, RecurrenceType.annualGregorian);
      expect(event.recurrenceEndDate, DateTime(2028, 1, 1));
    });

    test('מדלג על RRULE שאינו ניתן לייצוג מדויק במודל', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:every-other-week
DTSTART;VALUE=DATE:20260101
RRULE:FREQ=WEEKLY;INTERVAL=2
SUMMARY:כל שבועיים
END:VEVENT
END:VCALENDAR
''';

      expect(IcsCalendarService.parseIcs(ics), isEmpty);
    });

    test('קורא חזרה שבועית BYDAY לכמה ימים בלי לאבד את התאריכים', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:weekly-days
DTSTART;VALUE=DATE:20260101
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20260131
SUMMARY:שיעורים
END:VEVENT
END:VCALENDAR
''';
      final event = IcsCalendarService.parseIcs(ics).single;
      expect(event.recurrenceType, RecurrenceType.weekly);
      expect(event.weeklyDays, [DateTime.monday, DateTime.wednesday]);
      expect(event.occursOn(DateTime(2026, 1, 1)), isFalse);
      expect(event.occursOn(DateTime(2026, 1, 5)), isTrue);
      expect(event.occursOn(DateTime(2026, 1, 6)), isFalse);
      expect(event.occursOn(DateTime(2026, 1, 7)), isTrue);
      expect(event.occursOn(DateTime(2026, 2, 2)), isFalse);
    });

    test('דוחה BYDAY לא חוקי במקום לפרש אותו כחזרה ביום הלא נכון', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:bad-rule
DTSTART;VALUE=DATE:20260101
RRULE:FREQ=WEEKLY;BYDAY=1MO,WE
SUMMARY:תדירות לא נתמכת
END:VEVENT
END:VCALENDAR
''';
      expect(IcsCalendarService.parseIcs(ics), isEmpty);
    });

    for (final start in [
      'DTSTART:20261101T233000Z',
      'DTSTART;TZID=America/New_York:20261101T233000',
      'DTSTART;TZID=Asia/Jerusalem:20261101T233000',
    ]) {
      test('מדלג על BYDAY עם אזור זמן בלי לאבד אירועים תקינים: $start', () {
        final events = IcsCalendarService.parseIcs('''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:zoned
$start
RRULE:FREQ=WEEKLY;BYDAY=SU
SUMMARY:חזרה שאינה ניתנת לייצוג
END:VEVENT
BEGIN:VEVENT
UID:floating
DTSTART:20261102T013000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE
SUMMARY:שיעור מקומי
END:VEVENT
END:VCALENDAR
''');
        final event = events.single;
        expect(event.title, 'שיעור מקומי');
        expect(event.eventTime, const TimeOfDay(hour: 1, minute: 30));
        expect(event.startsOccurrenceOn(DateTime(2026, 11, 9)), isTrue);
        expect(event.startsOccurrenceOn(DateTime(2026, 11, 11)), isTrue);
        expect(event.startsOccurrenceOn(DateTime(2026, 11, 8)), isFalse);
      });

      test('שומר יבוא שבועי קיים עם אזור זמן וללא BYDAY: $start', () {
        final event = IcsCalendarService.parseIcs('''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:legacy
$start
RRULE:FREQ=WEEKLY
SUMMARY:אירוע קיים
END:VEVENT
END:VCALENDAR
''').single;
        expect(event.title, 'אירוע קיים');
        expect(event.recurrenceType, RecurrenceType.weekly);
        expect(event.weeklyDays, isNull);
      });
    }

    test('מאחה שורות מקופלות ומפענח escaping בטקסט', () {
      const ics =
          'BEGIN:VCALENDAR\r\n'
          'BEGIN:VEVENT\r\n'
          'UID:evt4\r\n'
          'DTSTART;VALUE=DATE:20260601\r\n'
          'SUMMARY:פגישה\\, חשובה\r\n'
          'DESCRIPTION:שורה ראשונה\\nשורה שנ\r\n'
          ' ייה\r\n'
          'END:VEVENT\r\n'
          'END:VCALENDAR\r\n';
      final event = IcsCalendarService.parseIcs(ics).single;
      expect(event.title, 'פגישה, חשובה');
      expect(event.description, 'שורה ראשונה\nשורה שנייה');
    });

    test('מדלג על אירוע מבוטל ועל אירוע בלי DTSTART', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:cancelled
DTSTART;VALUE=DATE:20260601
STATUS:CANCELLED
SUMMARY:מבוטל
END:VEVENT
BEGIN:VEVENT
UID:no-start
SUMMARY:חסר תאריך
END:VEVENT
END:VCALENDAR
''';
      expect(IcsCalendarService.parseIcs(ics), isEmpty);
    });

    test('מזהים יציבים ונטולי ":" — ייבוא חוזר מחליף במקום לשכפל', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt5@google.com
DTSTART;VALUE=DATE:20260601
SUMMARY:אירוע
END:VEVENT
END:VCALENDAR
''';
      final first = IcsCalendarService.parseIcs(ics).single;
      final second = IcsCalendarService.parseIcs(ics).single;
      expect(first.id, second.id);
      // ':' במזהה גורם לאירוע להיחשב אירוע plugin ולהימחק ברענון
      expect(first.id.contains(':'), isFalse);
    });

    test('sourceId מתויג על האירועים ונכנס למזהה', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt6
DTSTART;VALUE=DATE:20260601
SUMMARY:אירוע מנוי
END:VEVENT
END:VCALENDAR
''';
      final event = IcsCalendarService.parseIcs(
        ics,
        sourceId: 'icssub_1',
      ).single;
      expect(event.icsSourceId, 'icssub_1');
      expect(event.id, contains('icssub_1'));
    });
  });

  group('IcsSubscription', () {
    test('roundtrip JSON, ופריט פגום מדולג', () {
      final subscription = IcsSubscription(
        id: 'icssub_1',
        name: 'היומן שלי',
        url: 'https://example.com/cal.ics',
        lastRefresh: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final restored = IcsSubscription.fromJson(subscription.toJson());
      expect(restored, subscription);

      final list = IcsSubscription.listFromJson(
        '[{"id":"a","name":"b","url":"c"},{"broken":true},"junk"]',
      );
      expect(list, hasLength(1));
      expect(list.single.id, 'a');
    });
  });
}
