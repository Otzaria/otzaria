import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/plugins/bridge/plugin_jewish_date_payload_builder.dart';

void main() {
  group('PluginJewishDatePayloadBuilder', () {
    test('serializes the Hebrew date and Yom Tov details', () {
      final jewishDate = JewishDate()
        ..setJewishDate(5786, JewishDate.NISSAN, 15);
      final gregorianDate = jewishDate.getGregorianCalendar();
      final calendar = JewishCalendar.fromDateTime(gregorianDate)
        ..inIsrael = true;

      final payload = PluginJewishDatePayloadBuilder.build(
        gregorianDate,
        inIsrael: true,
      );

      final formatter = HebrewDateFormatter()..hebrewFormat = true;
      expect(payload['year'], calendar.getJewishYear());
      expect(payload['month'], calendar.getJewishMonth());
      expect(payload['day'], calendar.getJewishDayOfMonth());
      expect(payload['gregorian'], gregorianDate.toIso8601String());
      expect(payload['monthName'], formatter.formatMonth(calendar));
      expect(payload['isLeapYear'], calendar.isJewishLeapYear());
      expect(payload['isShabbat'], calendar.getDayOfWeek() == 7);
      expect(payload['dafYomi'], {
        'masechet': calendar.getDafYomiBavli().getMasechta(),
        'daf': calendar.getDafYomiBavli().getDaf(),
      });
      expect(
        (payload['holidays'] as List<Map<String, String>>),
        contains(
          allOf(
            containsPair('kind', 'yomTov'),
            containsPair('text', formatter.formatYomTov(calendar)),
          ),
        ),
      );
    });

    test('returns null for dates before the first Daf Yomi cycle', () {
      final payload = PluginJewishDatePayloadBuilder.build(
        DateTime(1900, 1, 1),
        inIsrael: true,
      );

      expect(payload['dafYomi'], isNull);
    });

    test('uses the upcoming Shabbat parasha independent of the hour', () {
      final date = DateTime(2026, 3, 29, 0, 30);
      final sameDay = DateTime(2026, 3, 29, 12);

      final early = PluginJewishDatePayloadBuilder.build(
        date,
        inIsrael: true,
      );
      final midday = PluginJewishDatePayloadBuilder.build(
        sameDay,
        inIsrael: true,
      );

      expect(early['parasha'], midday['parasha']);
    });

    test('marks Rosh Chodesh distinctly', () {
      final jewishDate = JewishDate()
        ..setJewishDate(5786, JewishDate.NISSAN, 1);
      final payload = PluginJewishDatePayloadBuilder.build(
        jewishDate.getGregorianCalendar(),
        inIsrael: true,
      );

      final holidays =
          (payload['holidays'] as List).cast<Map<String, String>>();
      expect(
        holidays,
        contains(
          allOf(
            containsPair('kind', 'roshChodesh'),
            containsPair('text', isNotEmpty),
          ),
        ),
      );
    });
  });
}
