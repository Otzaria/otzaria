import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_time_format.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz_data.initializeTimeZones);

  test('clock formatting keeps its LTR isolate and seconds marker', () {
    final location = tz.getLocation('Asia/Jerusalem');
    expect(
      formatZmanTime(DateTime.utc(2026, 5, 31, 16, 43, 0), location),
      '\u206619:43.\u2069',
    );
    expect(isClockTime('\u206619:43.\u2069'), isTrue);
    expect(isClockTime('ליל שבת ט״ז לחודש 19:43'), isFalse);
  });

  test('12-hour display conversion preserves the seconds marker', () {
    expect(
      zmanTimeForDisplay('\u206619:43:\u2069', twelveHourClock: true),
      '\u20667:43:\u200e\u00a0PM\u2069',
    );
  });

  test('Hebrew night label can be formatted independently', () {
    expect(
      formatHebrewNightLabel(
        DateTime(2026, 5, 31, 20, 15, 30),
        advanceToNextDay: false,
      ),
      contains('לחודש'),
    );
  });
}
