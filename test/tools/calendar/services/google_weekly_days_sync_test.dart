import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/repository/google_calendar_repository.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';

CustomEvent _lesson() => CustomEvent(
  id: 'lesson',
  title: 'שיעור',
  description: '',
  createdAt: DateTime(2026, 11, 1),
  baseGregorianDate: DateTime(2026, 11, 2),
  baseJewishYear: 5787,
  baseJewishMonth: 8,
  baseJewishDay: 22,
  recurrenceType: RecurrenceType.weekly,
  weeklyDays: const [DateTime.monday, DateTime.wednesday],
  googleEventId: 'series',
);

void main() {
  final repository = GoogleCalendarRepository(GoogleCalendarService());

  test('expanded instances preserve local weekdays across pages and JSON', () {
    cal.Event instance(int day) => cal.Event()
      ..id = 'series_202611$day'
      ..recurringEventId = 'series'
      ..summary = 'שיעור'
      ..start = (cal.EventDateTime()..date = DateTime(2026, 11, day))
      ..end = (cal.EventDateTime()..date = DateTime(2026, 11, day + 1))
      ..extendedProperties = (cal.EventExtendedProperties()
        ..private = {'otzaria_event_id': 'lesson'});

    final event = repository
        .mergeGoogleEventPages(
          [_lesson()],
          [
            [instance(2)],
            [instance(4)],
          ],
        )
        .single;
    final restored = CustomEvent.fromJson(event.toJson());
    expect(restored.weeklyDays, [DateTime.monday, DateTime.wednesday]);
    expect(restored.startsOccurrenceOn(DateTime(2026, 11, 9)), isTrue);
    expect(restored.startsOccurrenceOn(DateTime(2026, 11, 11)), isTrue);
    expect(restored.startsOccurrenceOn(DateTime(2026, 11, 10)), isFalse);
  });

  test('a recurring master replaces locally selected weekdays', () {
    final master = repository.toGoogleEvent(_lesson(), 'Asia/Jerusalem')
      ..id = 'series'
      ..recurrence = ['RRULE:FREQ=WEEKLY;BYDAY=TU,TH'];
    final event = repository
        .mergeGoogleEventPages(
          [_lesson()],
          [
            [master],
          ],
        )
        .single;
    expect(event.weeklyDays, [DateTime.tuesday, DateTime.thursday]);
  });

  for (final recurrence in <List<String>>[
    [],
    ['RRULE:FREQ=WEEKLY'],
  ]) {
    test(
      'an explicit recurrence without BYDAY clears selected weekdays: $recurrence',
      () {
        final master = repository.toGoogleEvent(_lesson(), 'Asia/Jerusalem')
          ..id = 'series'
          ..recurrence = recurrence;
        final event = repository
            .mergeGoogleEventPages(
              [_lesson()],
              [
                [master],
              ],
            )
            .single;
        expect(event.weeklyDays, isNull);
      },
    );
  }
}
