import 'package:kosher_dart/kosher_dart.dart';

/// Utility class for Hebrew text formatting and conversions.
class HebrewUtils {
  HebrewUtils._();

  /// Hebrew day and month of [date], e.g. כ״ח תשרי. The year is added when it
  /// is not the current Hebrew year.
  static String shortHebrewDate(DateTime date, {DateTime? now}) {
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    final jc = JewishCalendar.fromDateTime(date);
    final text =
        '${formatter.formatHebrewNumber(jc.getJewishDayOfMonth())} '
        '${formatter.formatMonth(jc)}';
    final current = JewishCalendar.fromDateTime(now ?? DateTime.now());
    if (jc.getJewishYear() == current.getJewishYear()) return text;
    return '$text ${formatter.formatHebrewNumber(jc.getJewishYear() % 1000)}';
  }

  /// Hebrew date followed by the Gregorian one, for tooltips.
  static String fullDate(DateTime date) {
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    final hebrew = formatter.format(JewishCalendar.fromDateTime(date));
    final gregorian =
        '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
    return '$hebrew · $gregorian';
  }

  /// Convert integer to Hebrew gematria with the standard geresh/gershayim marks.
  static String intToGematria(int number) {
    final base = intToHebrewWithoutQuotes(number);
    if (base.isEmpty) {
      return '';
    }
    return _addGershayim(base);
  }

  /// Label of a learnable item: gematria, with an amud mark for daf-type books.
  static String pageLabel(int pageNumber, String amudKey, bool isDafType) {
    final gematria = intToGematria(pageNumber);
    if (!isDafType) return gematria;
    return '$gematria${amudKey == 'b' ? ':' : '.'}';
  }

  /// Convert integer to Hebrew letters without quotation marks.
  static String intToHebrewWithoutQuotes(int number) {
    if (number <= 0) {
      return '';
    }

    int remainder = number;
    final buffer = StringBuffer();

    const hundredsMap = <int, String>{
      900: 'תתק',
      800: 'תת',
      700: 'תש',
      600: 'תר',
      500: 'תק',
      400: 'ת',
      300: 'ש',
      200: 'ר',
      100: 'ק',
    };

    for (final entry in hundredsMap.entries) {
      while (remainder >= entry.key) {
        buffer.write(entry.value);
        remainder -= entry.key;
      }
    }

    if (remainder == 15) {
      buffer.write('טו');
      return buffer.toString();
    }
    if (remainder == 16) {
      buffer.write('טז');
      return buffer.toString();
    }

    const tensMap = <int, String>{
      90: 'צ',
      80: 'פ',
      70: 'ע',
      60: 'ס',
      50: 'נ',
      40: 'מ',
      30: 'ל',
      20: 'כ',
      10: 'י',
    };

    for (final entry in tensMap.entries) {
      if (remainder >= entry.key) {
        buffer.write(entry.value);
        remainder -= entry.key;
      }
    }

    const unitsMap = <int, String>{
      9: 'ט',
      8: 'ח',
      7: 'ז',
      6: 'ו',
      5: 'ה',
      4: 'ד',
      3: 'ג',
      2: 'ב',
      1: 'א',
    };

    if (remainder > 0 && unitsMap.containsKey(remainder)) {
      buffer.write(unitsMap[remainder]);
    }

    return buffer.toString();
  }

  static String _addGershayim(String value) {
    if (value.isEmpty) {
      return '';
    }

    if (value.length == 1) {
      return '$value׳';
    }

    return '${value.substring(0, value.length - 1)}״${value.substring(value.length - 1)}';
  }
}
