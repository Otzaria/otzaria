import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';

CustomEvent _weekly({List<int>? weekdays, DateTime? until}) => CustomEvent(
  id: 'weekly',
  title: 'שיעור',
  description: '',
  createdAt: DateTime(2026, 11, 1),
  baseGregorianDate: DateTime(2026, 11, 1), // Sunday
  baseJewishYear: 5787,
  baseJewishMonth: 8,
  baseJewishDay: 21,
  recurrenceType: RecurrenceType.weekly,
  weeklyDays: weekdays,
  recurrenceEndDate: until,
);

void main() {
  test('weekly supports a chosen set of days without repeating on others', () {
    final event = _weekly(
      weekdays: [DateTime.sunday, DateTime.monday, DateTime.wednesday],
    );
    expect(event.occursOn(DateTime(2026, 11, 1)), isTrue);
    expect(event.occursOn(DateTime(2026, 11, 2)), isTrue);
    expect(event.occursOn(DateTime(2026, 11, 3)), isFalse);
    expect(event.startsOccurrenceOn(DateTime(2026, 11, 4)), isTrue);
    expect(event.startsOccurrenceOn(DateTime(2026, 11, 7)), isFalse);
    expect(event.occursOn(DateTime(2026, 11, 9)), isTrue);
    expect(event.occursOn(DateTime(2026, 10, 26)), isFalse);
  });

  test('first selected occurrence can follow DTSTART', () {
    final event = _weekly(weekdays: [DateTime.monday, DateTime.wednesday]);
    expect(event.occursOn(DateTime(2026, 11, 1)), isFalse);
    expect(event.nextOccurrenceFrom(DateTime(2026, 10, 25)), DateTime(2026, 11, 2));
    expect(event.nextOccurrenceFrom(DateTime(2026, 11, 3)), DateTime(2026, 11, 4));
  });

  test('end date applies to every selected weekday', () {
    final event = _weekly(
      weekdays: [DateTime.monday, DateTime.wednesday],
      until: DateTime(2026, 11, 9),
    );
    expect(event.occursOn(DateTime(2026, 11, 9)), isTrue);
    expect(event.occursOn(DateTime(2026, 11, 11)), isFalse);
  });

  test('legacy weekly JSON still means DTSTART weekday', () {
    final json = _weekly().toJson();
    expect(json.containsKey('weeklyDays'), isFalse);
    final restored = CustomEvent.fromJson(json);
    expect(restored.weeklyDays, isNull);
    expect(restored.occursOn(DateTime(2026, 11, 1)), isTrue);
    expect(restored.occursOn(DateTime(2026, 11, 2)), isFalse);
  });

  test('days survive JSON, copyWith and BYDAY codec', () {
    final original = _weekly(weekdays: [1, 3, 7]);
    final restored = CustomEvent.fromJson(original.toJson());
    expect(restored.weeklyDays, [1, 3, 7]);
    expect(restored, original);
    expect(restored.copyWith(weeklyDays: () => null).weeklyDays, isNull);
    expect(formatCalendarWeekdays([7, 1, 3]), 'MO,WE,SU');
    expect(parseCalendarWeekdays('MO,WE,SU'), [1, 3, 7]);
    expect(parseCalendarWeekdays('MO,MO'), isNull);
    expect(parseCalendarWeekdays('1MO'), isNull);
    expect(parseCalendarWeekdays(''), isNull);
  });

  test('invalid persisted days fall back to the original weekly day', () {
    final json = _weekly().toJson()..['weeklyDays'] = [0, 4, 8];
    final event = CustomEvent.fromJson(json);
    expect(event.weeklyDays, isNull);
    expect(event.occursOn(DateTime(2026, 11, 1)), isTrue);
  });
}
