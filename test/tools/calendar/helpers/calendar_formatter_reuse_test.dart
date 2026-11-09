import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

void main() {
  group('calendar formatter reuse', () {
    test('Hebrew date output matches an independent formatter across dates', () {
      final reference = HebrewDateFormatter()..hebrewFormat = true;
      final dates = [
        DateTime(2024, 2, 29),
        DateTime(2024, 4, 23),
        DateTime(2025, 1, 15),
        DateTime(2026, 11, 9),
      ];
      for (final date in dates) {
        final expected = reference.format(JewishCalendar.fromDateTime(date));
        expect(getHebrewDateFormattedAsString(date), expected);
      }
    });

    test('number and year formatting stays stable over repeated uses', () {
      final plain = HebrewDateFormatter();
      final expectedAmud = plain
          .formatHebrewNumber(33)
          .replaceAll('״', '')
          .replaceAll('׳', '');
      final initialYear = formatHebrewYear(5784);
      for (var i = 0; i < 200; i++) {
        expect(formatAmud(33), expectedAmud);
        expect(formatHebrewYear(5784), initialYear);
      }
    });
  });
}
