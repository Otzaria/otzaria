import 'package:kosher_dart/kosher_dart.dart';

import 'package:otzaria/utils/calendar_days.dart';

/// Converts a Gregorian date into the stable calendar payload exposed to plugins.
///
/// Keeps the Jewish-calendar library details and the plugin wire format outside
/// [PluginBridgeAdapter], so calendar serialization can be tested independently
/// from the bridge's permission and RPC lifecycle.
class PluginJewishDatePayloadBuilder {
  const PluginJewishDatePayloadBuilder._();

  static Map<String, dynamic> build(
    DateTime date, {
    required bool inIsrael,
  }) {
    final jewishCalendar = JewishCalendar.fromDateTime(date)
      ..inIsrael = inIsrael;
    final formatter = HebrewDateFormatter()..hebrewFormat = true;

    return {
      'year': jewishCalendar.getJewishYear(),
      'month': jewishCalendar.getJewishMonth(),
      'day': jewishCalendar.getJewishDayOfMonth(),
      'gregorian': date.toIso8601String(),
      'monthName': formatter.formatMonth(jewishCalendar),
      'isLeapYear': jewishCalendar.isJewishLeapYear(),
      'isShabbat': jewishCalendar.getDayOfWeek() == 7,
      'parasha': _upcomingParasha(date, inIsrael, formatter),
      'dafYomi': _buildDafYomiPayload(jewishCalendar),
      'holidays': _buildHolidayPayloads(jewishCalendar, formatter),
    };
  }

  /// Daf Yomi Bavli is null before the first cycle (18 Elul 5683).
  static Map<String, dynamic>? _buildDafYomiPayload(
    JewishCalendar jewishCalendar,
  ) {
    try {
      final daf = jewishCalendar.getDafYomiBavli();
      return {'masechet': daf.getMasechta(), 'daf': daf.getDaf()};
    } on ArgumentError {
      return null;
    }
  }

  static String _upcomingParasha(
    DateTime date,
    bool inIsrael,
    HebrewDateFormatter formatter,
  ) {
    final dayOfWeek = date.weekday;
    // Dart weekday: Mon=1 … Sat=6, Sun=7. Shabbat = Saturday = 6.
    final daysUntilShabbat = dayOfWeek == 6 ? 0 : (6 - dayOfWeek) % 7;
    final shabbatDate = addCalendarDays(date, daysUntilShabbat);
    final shabbatCalendar = JewishCalendar.fromDateTime(shabbatDate)
      ..inIsrael = inIsrael;
    return formatter.formatParsha(shabbatCalendar);
  }

  static List<Map<String, String>> _buildHolidayPayloads(
    JewishCalendar jewishCalendar,
    HebrewDateFormatter formatter,
  ) {
    final holidays = <Map<String, String>>[];
    final seenLabels = <String>{};

    void addHoliday(String label, String kind) {
      final normalizedLabel = label.trim();
      if (normalizedLabel.isEmpty || !seenLabels.add(normalizedLabel)) {
        return;
      }
      holidays.add({'text': normalizedLabel, 'kind': kind});
    }

    final yomTovLabel = formatter.formatYomTov(jewishCalendar);
    if (yomTovLabel.isNotEmpty) {
      final month = jewishCalendar.getJewishMonth();
      final day = jewishCalendar.getJewishDayOfMonth();
      final idx = jewishCalendar.getYomTovIndex();

      // Pesach days have specific labels that the library does not distinguish.
      if (idx == JewishCalendar.PESACH) {
        if (month == 1 && day == 21) {
          addHoliday('שביעי של פסח', 'yomTov');
        } else if (month == 1 && day == 22) {
          addHoliday('אחרון של פסח', 'yomTov');
        } else if (month == 1 && day == 16) {
          addHoliday('פסח שני', 'yomTov');
        } else {
          addHoliday(
            yomTovLabel,
            _holidayKindForLabel(yomTovLabel, jewishCalendar),
          );
        }
      } else {
        for (final label in yomTovLabel.split(',')) {
          addHoliday(label, _holidayKindForLabel(label, jewishCalendar));
        }
      }
    }

    if (jewishCalendar.isErevRoshChodesh()) {
      addHoliday(formatter.formatErevRoshChodesh(jewishCalendar), 'special');
    }

    if (jewishCalendar.isRoshChodesh()) {
      addHoliday(formatter.formatRoshChodesh(jewishCalendar), 'roshChodesh');
    }

    return holidays;
  }

  static String _holidayKindForLabel(
    String label,
    JewishCalendar jewishCalendar,
  ) {
    final normalizedLabel = label.trim();
    if (normalizedLabel.contains('ראש חודש') ||
        normalizedLabel.contains('ר"ח')) {
      return 'roshChodesh';
    }

    if (jewishCalendar.isTaanis() &&
        jewishCalendar.getYomTovIndex() != JewishCalendar.YOM_KIPPUR) {
      return 'taanit';
    }

    if (jewishCalendar.isYomTovAssurBemelacha()) {
      return 'yomTov';
    }

    return 'special';
  }
}
