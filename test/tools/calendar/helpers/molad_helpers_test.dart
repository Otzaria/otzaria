import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/molad_helpers.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('calculateMoladForDate', () {
    test('returns null on a regular day (not r"ch, shabbos mevorchim, '
        'or molad day)', () {
      // 15 Sivan 5785 (Wednesday, 11 June 2025) — middle of the month.
      final date = DateTime(2025, 6, 11);
      final info = calculateMoladForDate(date, 'ירושלים');
      expect(info, isNull);
    });

    test('returns molad info on Rosh Chodesh (1 Cheshvan 5786)', () {
      final date = DateTime(2025, 10, 23); // 1 Cheshvan 5786
      final info = calculateMoladForDate(date, 'ירושלים');
      expect(info, isNotNull);
      expect(info!.reason, MoladDisplayReason.roshChodesh);
      expect(info.jewishMonth, JewishDate.CHESHVAN);
      expect(info.monthName, isNotEmpty);
      expect(info.cityName, 'ירושלים');
      expect(info.cityTimezone, 'Asia/Jerusalem');
    });

    test(
      'returns molad info on Rosh Chodesh day 30 (first day of 2-day r"ch)',
      () {
        // 30 Cheshvan 5786 = 21 November 2025 (first of 2 r"ch days for Kislev)
        final date = DateTime(2025, 11, 21);
        final info = calculateMoladForDate(date, 'ירושלים');
        expect(info, isNotNull);
        expect(info!.reason, MoladDisplayReason.roshChodesh);
        expect(info.jewishMonth, JewishDate.KISLEV);
      },
    );

    test('returns molad info on Shabbos Mevorchim for next month', () {
      // 25 Tishrei 5786 = Shabbat 18 Oct 2025.
      final date = DateTime(2025, 10, 18);
      final jc = JewishCalendar.fromDateTime(date);
      expect(jc.isShabbosMevorchim(), isTrue);

      final info = calculateMoladForDate(date, 'ירושלים');
      expect(info, isNotNull);
      expect(info!.reason, MoladDisplayReason.shabbosMevorchim);
      expect(info.jewishMonth, JewishDate.CHESHVAN);
    });

    test('announcement starts with day-of-week and uses digits', () {
      final date = DateTime(2025, 10, 23); // R"ch Cheshvan 5786
      final info = calculateMoladForDate(date, 'ירושלים')!;
      expect(info.announcementText, isNot(startsWith('מולד ')));
      expect(info.announcementText, isNot(contains('יהיה')));
      final startsWithDay =
          info.announcementText.startsWith('יום ') ||
          info.announcementText.startsWith('שבת');
      expect(startsWithDay, isTrue);
      expect(info.announcementText, matches(RegExp(r'בשעה \d{1,2} ')));
      final hasDayPart =
          info.announcementText.contains('בבוקר') ||
          info.announcementText.contains('אחר הצהריים') ||
          info.announcementText.contains('בערב') ||
          info.announcementText.contains('בלילה') ||
          info.announcementText.contains('בצהריים');
      expect(hasDayPart, isTrue);
      expect(info.announcementText, isNot(endsWith('.')));
    });

    test('visible day name and visible Hebrew date are populated', () {
      final info = calculateMoladForDate(DateTime(2025, 10, 23), 'ירושלים')!;
      expect(info.visibleDayName, isNotEmpty);
      expect(info.visibleHebrewDate, isNotEmpty);
      expect(info.visibleTimeFormatted, matches(r'^\d{2}:\d{2}:\d{2}$'));
    });
  });

  // ==========================================================================
  // P1: moladDay trigger uses the TRUE conjunction in the user's city,
  // not the mean molad date. The card must appear on the same day shown
  // inside the card.
  // ==========================================================================
  group('moladDay trigger follows the visible molad', () {
    test('Jerusalem: card shows on 21 Oct 2025 — the true conjunction day '
        '(mean molad in LMT falls on 23 Oct after midnight)', () {
      // The true conjunction is on 21 Oct 2025 ~15:25 IDT. The mean molad in
      // LMT is on 23 Oct 2025 ~00:54. Before the fix, the card would NOT have
      // shown on 21 Oct (since mean molad isn't on that day). After the fix,
      // it must.
      final info = calculateMoladForDate(DateTime(2025, 10, 21), 'ירושלים');
      expect(
        info,
        isNotNull,
        reason: 'must show on the day of the true conjunction in Jerusalem',
      );
      expect(info!.reason, MoladDisplayReason.moladDay);
      // And the shown timestamp must indeed be on 21 Oct.
      expect(info.visibleMoladInCity.day, 21);
      expect(info.visibleMoladInCity.month, 10);
    });

    test('New York: card shows on 21 Oct 2025 — same true conjunction day '
        'in NY local time (08:25 EDT)', () {
      final info = calculateMoladForDate(DateTime(2025, 10, 21), 'ניו יורק');
      expect(info, isNotNull);
      expect(info!.reason, MoladDisplayReason.moladDay);
      expect(info.visibleMoladInCity.day, 21);
    });

    test('Trigger is city-aware: Jerusalem and LA see the molad on '
        'different Gregorian days', () {
      // R"ch Nisan 5786: true conjunction 19 Mar 2026 ~01:23 UTC.
      //   - Jerusalem (UTC+2 standard, before Israel DST switch on 27 Mar):
      //     03:23 on 19 Mar — same day as R"ch itself.
      //   - Los Angeles (UTC-7 PDT, DST started 8 Mar): 18:23 on 18 Mar —
      //     the day before R"ch. 18 Mar is 29 Adar II — a regular day in
      //     Jewish terms, so the only thing that can trigger the card there
      //     is moladDay.
      //
      // The asymmetry: 18 Mar is moladDay in LA but null in Jerusalem.
      final jerusalemOn18 = calculateMoladForDate(
        DateTime(2026, 3, 18),
        'ירושלים',
      );
      final laOn18 = calculateMoladForDate(
        DateTime(2026, 3, 18),
        'לוס אנג\'לס',
      );

      expect(
        jerusalemOn18,
        isNull,
        reason:
            '18 Mar in Jerusalem: conjunction in Jerusalem is on '
            'the 19th — nothing to show on the 18th.',
      );
      expect(
        laOn18,
        isNotNull,
        reason: '18 Mar in LA: conjunction falls locally on this day',
      );
      expect(laOn18!.reason, MoladDisplayReason.moladDay);
    });
  });

  // ==========================================================================
  // Direct unit tests for formatMoladAnnouncement.
  // Covers: hour-12 boundary, singular/plural minute & chalakim, missing units.
  // ==========================================================================
  group('formatMoladAnnouncement', () {
    test('hour 12 (LMT noon) uses "בצהריים", not "אחר הצהריים"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 12,
        minutes: 0,
        chalakim: 0,
      );
      expect(text, 'יום שני בשעה 12 בצהריים');
      expect(text, isNot(contains('אחר הצהריים')));
    });

    test('hour 12:30 still says "בצהריים", with minutes appended', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 12,
        minutes: 30,
        chalakim: 0,
      );
      expect(text, 'יום שני בשעה 12 בצהריים ו-30 דקות');
    });

    test('hour 13 (1 PM) maps to "1 אחר הצהריים"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 13,
        minutes: 0,
        chalakim: 0,
      );
      expect(text, 'יום שני בשעה 1 אחר הצהריים');
    });

    test('hour 0 (midnight) maps to "12 בלילה"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 0,
        minutes: 5,
        chalakim: 0,
      );
      expect(text, 'יום שני בשעה 12 בלילה ו-5 דקות');
    });

    test('hour 18 (6 PM) maps to "6 בערב" — user-supplied example shape', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 18,
        minutes: 3,
        chalakim: 2,
      );
      expect(text, 'יום שני בשעה 6 בערב ו-3 דקות ו-2 חלקים');
    });

    test('hour 9 (morning) maps to "בבוקר"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שלישי',
        hours: 9,
        minutes: 0,
        chalakim: 0,
      );
      expect(text, 'יום שלישי בשעה 9 בבוקר');
    });

    test('hour 3 (pre-dawn) maps to "בלילה"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שישי',
        hours: 3,
        minutes: 0,
        chalakim: 0,
      );
      expect(text, 'יום שישי בשעה 3 בלילה');
    });

    test('singular minute: "1 דקה" (not "1 דקות")', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 10,
        minutes: 1,
        chalakim: 0,
      );
      expect(text, 'יום שני בשעה 10 בבוקר ו-1 דקה');
      expect(text, isNot(contains('דקות')));
    });

    test('plural minutes: "2 דקות"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 10,
        minutes: 2,
        chalakim: 0,
      );
      expect(text, contains('2 דקות'));
      expect(text, isNot(contains('דקה')));
    });

    test('singular chalak: "1 חלק" (not "1 חלקים")', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 10,
        minutes: 0,
        chalakim: 1,
      );
      expect(text, 'יום שני בשעה 10 בבוקר ו-1 חלק');
      expect(text, isNot(contains('חלקים')));
    });

    test('plural chalakim: "5 חלקים"', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום שני',
        hours: 10,
        minutes: 0,
        chalakim: 5,
      );
      expect(text, contains('5 חלקים'));
      // The standalone "חלק" should not appear (only inside "חלקים").
      expect(text.replaceAll('חלקים', ''), isNot(contains('חלק')));
    });

    test('omits zero minutes / zero chalakim', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'שבת קודש',
        hours: 7,
        minutes: 0,
        chalakim: 0,
      );
      expect(text, 'שבת קודש בשעה 7 בבוקר');
      expect(text, isNot(contains('דקות')));
      expect(text, isNot(contains('חלקים')));
    });

    test('non-zero minutes but zero chalakim: only minutes appended', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום ראשון',
        hours: 8,
        minutes: 15,
        chalakim: 0,
      );
      expect(text, 'יום ראשון בשעה 8 בבוקר ו-15 דקות');
    });

    test('zero minutes but non-zero chalakim: only chalakim appended', () {
      final text = formatMoladAnnouncement(
        dayOfWeekName: 'יום רביעי',
        hours: 8,
        minutes: 0,
        chalakim: 7,
      );
      expect(text, 'יום רביעי בשעה 8 בבוקר ו-7 חלקים');
    });
  });

  // ==========================================================================
  // Leap year + Adar I / Adar II.
  // ==========================================================================
  group('leap-year Adar handling', () {
    test('R"ch Adar I in leap year 5784 (10 Feb 2024)', () {
      // 1 Adar I 5784 = Saturday 10 February 2024.
      final date = DateTime(2024, 2, 10);
      final jc = JewishCalendar.fromDateTime(date);
      expect(jc.isJewishLeapYear(), isTrue);
      expect(jc.isRoshChodesh(), isTrue);

      final info = calculateMoladForDate(date, 'ירושלים');
      expect(info, isNotNull);
      expect(info!.reason, MoladDisplayReason.roshChodesh);
      // The month name should mention Adar (and either Adar I marker or
      // just "אדר" with year context — depends on kosher_dart, but it
      // must be a valid Adar variant).
      expect(info.monthName, contains('אדר'));
    });

    test('R"ch Adar II in leap year 5784 (11 Mar 2024) — distinct from '
        'Adar I', () {
      // 1 Adar II 5784 = Monday 11 March 2024.
      final date = DateTime(2024, 3, 11);
      final jc = JewishCalendar.fromDateTime(date);
      expect(jc.isJewishLeapYear(), isTrue);
      expect(jc.isRoshChodesh(), isTrue);
      // kosher_dart uses month constant ADAR_II for the second Adar.
      expect(jc.getJewishMonth(), JewishDate.ADAR_II);

      final info = calculateMoladForDate(date, 'ירושלים');
      expect(info, isNotNull);
      expect(info!.jewishMonth, JewishDate.ADAR_II);
      expect(info.monthName, contains('אדר'));
    });

    test('Shabbos Mevorchim of Adar II targets Adar II (not Adar I)', () {
      // Last Shabbat before R"ch Adar II 5784 (11 Mar 2024) → Sat 9 Mar 2024.
      final date = DateTime(2024, 3, 9);
      final jc = JewishCalendar.fromDateTime(date);
      expect(jc.isShabbosMevorchim(), isTrue);

      final info = calculateMoladForDate(date, 'ירושלים');
      expect(info, isNotNull);
      expect(info!.reason, MoladDisplayReason.shabbosMevorchim);
      expect(
        info.jewishMonth,
        JewishDate.ADAR_II,
        reason:
            'Shabbos Mevorchim of Adar should point to Adar II '
            'when next month is Adar II',
      );
    });
  });

  // ==========================================================================
  // Meeus accuracy on multiple data points (past, present, future).
  // Reference: USNO new moon UTC timestamps.
  // ==========================================================================
  group('Meeus true conjunction matches USNO across multiple dates', () {
    void checkAgainstUsno({
      required DateTime dateOnRosh,
      required DateTime expectedUtc,
      required String description,
    }) {
      final info = calculateMoladForDate(dateOnRosh, 'ירושלים');
      expect(info, isNotNull, reason: '$description: must trigger');
      final actual = info!.visibleMoladInCity.toUtc();
      final diffMinutes = actual.difference(expectedUtc).inMinutes.abs();
      expect(
        diffMinutes,
        lessThanOrEqualTo(15),
        reason:
            '$description: expected $expectedUtc, got $actual '
            '(diff ${diffMinutes}m)',
      );
    }

    test('R"ch Cheshvan 5786 — USNO 2025-10-21 12:25 UTC', () {
      checkAgainstUsno(
        dateOnRosh: DateTime(2025, 10, 23),
        expectedUtc: DateTime.utc(2025, 10, 21, 12, 25),
        description: 'Oct 2025',
      );
    });

    test('R"ch Tevet 5784 — USNO 2023-12-12 23:32 UTC (winter)', () {
      // 1 Tevet 5784 = 13 December 2023.
      checkAgainstUsno(
        dateOnRosh: DateTime(2023, 12, 13),
        expectedUtc: DateTime.utc(2023, 12, 12, 23, 32),
        description: 'Dec 2023 (winter, no DST)',
      );
    });

    test('R"ch Shevat 5780 — USNO 2020-01-24 21:42 UTC (past decade)', () {
      // 1 Shevat 5780 = 27 January 2020.
      checkAgainstUsno(
        dateOnRosh: DateTime(2020, 1, 27),
        expectedUtc: DateTime.utc(2020, 1, 24, 21, 42),
        description: 'Jan 2020',
      );
    });

    test('R"ch Av 5780 — USNO 2020-07-20 17:33 UTC (summer DST)', () {
      // 1 Av 5780 = 22 July 2020.
      checkAgainstUsno(
        dateOnRosh: DateTime(2020, 7, 22),
        expectedUtc: DateTime.utc(2020, 7, 20, 17, 33),
        description: 'Jul 2020 (summer DST)',
      );
    });
  });
}
