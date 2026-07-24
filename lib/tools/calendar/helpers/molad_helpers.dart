import 'dart:math' as math;

import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:timezone/timezone.dart' as tz;

/// סיבת ההצגה של המולד ביום נתון.
enum MoladDisplayReason {
  /// היום הוא שבת מברכים — מציג מולד של החודש הבא.
  shabbosMevorchim,

  /// היום הוא ראש חודש — מציג מולד של החודש שמתחיל.
  roshChodesh,

  /// היום הוא היום הגרגוריאני שבו חל המולד.
  moladDay,
}

/// מידע מלא על מולד של חודש מסויים, להצגה בלוח השנה.
///
/// כולל את שני סוגי המולד:
/// - **המולד הממוצע (ההלכתי)** — החישוב המסורתי שעליו מכריזים בבית הכנסת.
///   מבוסס על אורך חודש ממוצע של 29 ימים, 12 שעות, ו-793 חלקים. הזמן ב-LMT
///   של הר הבית (כפי שמצוין בסידורים).
/// - **המולד הנראה (האסטרונומי)** — זמן ה-conjunction האמיתי של הירח והשמש,
///   מחושב לפי אלגוריתם Meeus. מוצג בזמן המקומי של העיר הנבחרת.
class MoladInfo {
  final int jewishYear;
  final int jewishMonth;
  final String monthName;
  final MoladDisplayReason reason;

  /// טקסט ההכרזה לתצוגה: יום בשבוע + שעה (ספרות, 12-hour clock) + חלקי היום
  /// (בבוקר / בצהריים / אחר הצהריים / בערב / בלילה) + דקות + חלקים.
  /// דוגמה: "יום שני בשעה 6 בערב ו-3 דקות ו-2 חלקים".
  final String announcementText;

  /// המולד הנראה (אסטרונומי) בזמן העיר הנבחרת.
  final tz.TZDateTime visibleMoladInCity;

  /// שם הטיים-זון של העיר.
  final String cityTimezone;

  /// שם העיר.
  final String cityName;

  const MoladInfo({
    required this.jewishYear,
    required this.jewishMonth,
    required this.monthName,
    required this.reason,
    required this.announcementText,
    required this.visibleMoladInCity,
    required this.cityTimezone,
    required this.cityName,
  });

  /// פורמט שעה+דקה+שניה של המולד הנראה.
  String get visibleTimeFormatted =>
      '${visibleMoladInCity.hour.toString().padLeft(2, '0')}:'
      '${visibleMoladInCity.minute.toString().padLeft(2, '0')}:'
      '${visibleMoladInCity.second.toString().padLeft(2, '0')}';

  /// יום בשבוע של המולד הנראה (1=ראשון, 7=שבת), לפי הזמן בעיר.
  /// שים לב: כיום הלכתי מתחיל בערב, אז 18:00 והלאה הוא היום הבא הלכתית.
  /// פה מציג את היום הלוחי הרגיל בעיר.
  String get visibleDayName {
    final dt = visibleMoladInCity;
    final weekday = dt.weekday; // 1=Mon ... 7=Sun
    // Convert Dart weekday (Mon=1..Sun=7) to Jewish (Sun=1..Sat=7)
    final jewishDayOfWeek = (weekday % 7) + 1;
    return _dayOfWeekNames[jewishDayOfWeek] ?? '';
  }

  /// תאריך עברי של המולד הנראה (לפי הזמן בעיר).
  String get visibleHebrewDate {
    final dt = visibleMoladInCity;
    final jc = JewishCalendar.fromDateTime(
      DateTime(dt.year, dt.month, dt.day),
    );
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    return '${formatter.formatHebrewNumber(jc.getJewishDayOfMonth())} '
        '${formatter.formatMonth(jc)}';
  }
}

const _dayOfWeekNames = {
  1: 'יום ראשון',
  2: 'יום שני',
  3: 'יום שלישי',
  4: 'יום רביעי',
  5: 'יום חמישי',
  6: 'יום שישי',
  7: 'שבת קודש',
};

/// LMT offset של הר הבית מ-UTC: 2 שעות + 20 דקות + 56.496 שניות.
const Duration _kJerusalemLmtOffset = Duration(
  hours: 2,
  minutes: 20,
  seconds: 56,
  milliseconds: 496,
);

/// מחשב את מידע המולד להצגה בתאריך נתון, אם הוא רלוונטי (שבת מברכים,
/// ר"ח, או היום הגרגוריאני שבו חל המולד הנראה בעיר הנבחרת).
/// מחזיר null אם אין מה להציג.
///
/// הערה: זיהוי "יום המולד" משתמש בזמן ה-true conjunction בעיר הנבחרת,
/// לא בזמן המולד הממוצע. כך הכרטיס מוצג ביום שבו באמת מופיע הזמן.
MoladInfo? calculateMoladForDate(DateTime date, String city) {
  final cityData = getCityData(city);
  if (cityData == null) return null;
  final timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';
  final tzLocation = tz.getLocation(timeZoneId);

  final jc = JewishCalendar.fromDateTime(date);

  // שלב 1: זיהוי לאיזה חודש המולד שייך + סיבת ההצגה.
  JewishCalendar? targetMonth;
  MoladDisplayReason? reason;
  tz.TZDateTime? precomputedVisible;

  if (jc.isShabbosMevorchim()) {
    targetMonth = _cloneForNextMonth(jc);
    reason = MoladDisplayReason.shabbosMevorchim;
  } else if (jc.isRoshChodesh()) {
    if (jc.getJewishDayOfMonth() == 30) {
      targetMonth = _cloneForNextMonth(jc);
    } else {
      targetMonth = JewishCalendar.fromDateTime(date);
    }
    reason = MoladDisplayReason.roshChodesh;
  } else {
    // הגירוי הוא תאריך ה-true conjunction בעיר הנבחרת — כדי שהכרטיס יוצג
    // ביום של הזמן שמופיע עליו (ולא לפי ה-mean molad).
    final candidates = [
      JewishCalendar.fromDateTime(date),
      _cloneForNextMonth(JewishCalendar.fromDateTime(date)),
    ];
    for (final candidate in candidates) {
      final visibleInCity = _computeVisibleMoladInCity(candidate, tzLocation);
      if (visibleInCity.year == date.year &&
          visibleInCity.month == date.month &&
          visibleInCity.day == date.day) {
        targetMonth = candidate;
        reason = MoladDisplayReason.moladDay;
        precomputedVisible = visibleInCity;
        break;
      }
    }
  }

  if (targetMonth == null || reason == null) return null;

  return _buildMoladInfo(
    targetMonth,
    tzLocation,
    timeZoneId,
    city,
    reason,
    precomputedVisible: precomputedVisible,
  );
}

JewishCalendar _cloneForNextMonth(JewishCalendar source) {
  final cloned = JewishCalendar.fromDateTime(source.getGregorianCalendar());
  cloned.forward(Calendar.MONTH, 1);
  return cloned;
}

/// מחשב את ה-true conjunction של החודש הנתון בזמן המקומי של העיר.
tz.TZDateTime _computeVisibleMoladInCity(
  JewishCalendar candidate,
  tz.Location tzLocation,
) {
  final molad = candidate.getMolad();
  final visibleMoladUtc = _calculateTrueConjunctionUtc(
    candidate,
    fallbackLmtMolad: _meanMoladAsUtc(molad),
  );
  return tz.TZDateTime.from(visibleMoladUtc, tzLocation);
}

MoladInfo _buildMoladInfo(
  JewishCalendar targetMonthCalendar,
  tz.Location tzLocation,
  String timeZoneId,
  String cityName,
  MoladDisplayReason reason, {
  tz.TZDateTime? precomputedVisible,
}) {
  final molad = targetMonthCalendar.getMolad();

  // ערכים גולמיים מהמולד (זמן LMT של הר הבית).
  final hours = molad.getMoladHours();
  final minutes = molad.getMoladMinutes();
  final chalakim = molad.getMoladChalakim(); // 0-17
  final dayOfWeek = molad.getDayOfWeek();
  final dayOfWeekName = _dayOfWeekNames[dayOfWeek] ?? 'יום $dayOfWeek';

  // טקסט ההכרזה.
  final formatter = HebrewDateFormatter()..hebrewFormat = true;
  final monthName = formatter.formatMonth(targetMonthCalendar);
  final announcement = formatMoladAnnouncement(
    dayOfWeekName: dayOfWeekName,
    hours: hours,
    minutes: minutes,
    chalakim: chalakim,
  );

  // המולד הנראה — או שכבר חושב (במסלול moladDay) או שמחושב כעת.
  final visibleMoladInCity =
      precomputedVisible ??
      _computeVisibleMoladInCity(targetMonthCalendar, tzLocation);

  return MoladInfo(
    jewishYear: targetMonthCalendar.getJewishYear(),
    jewishMonth: targetMonthCalendar.getJewishMonth(),
    monthName: monthName,
    reason: reason,
    announcementText: announcement,
    visibleMoladInCity: visibleMoladInCity,
    cityTimezone: timeZoneId,
    cityName: cityName,
  );
}

DateTime _meanMoladAsUtc(JewishDate molad) {
  final lmt = DateTime.utc(
    molad.getGregorianYear(),
    molad.getGregorianMonth(),
    molad.getGregorianDayOfMonth(),
    molad.getMoladHours(),
    molad.getMoladMinutes(),
    (molad.getMoladChalakim() * (10000 / 3) ~/ 1000),
  );
  return lmt.subtract(_kJerusalemLmtOffset);
}

// ============================================================================
// בניית טקסט ההכרזה
// ============================================================================

/// בונה את טקסט ההכרזה של המולד.
///
/// קלט: ערכי מולד גולמיים (LMT) — שעה 0-23, דקות 0-59, חלקים 0-17.
/// פלט: מחרוזת בנוסח `יום בשעה N חלקי-היום ו-M דקות ו-K חלקים`.
///
/// נחשף לטסטים כדי לאפשר אימות ישיר של היחיד/רבים, גבולות השעה (12,0),
/// ותיוג חלקי היום (בצהריים/אחר הצהריים/בערב/בלילה/בבוקר).
String formatMoladAnnouncement({
  required String dayOfWeekName,
  required int hours,
  required int minutes,
  required int chalakim,
}) {
  final displayHour12 = _to12HourClock(hours);
  final partOfDay = _partOfDayLabel(hours);

  final buf = StringBuffer(dayOfWeekName);
  buf.write(' בשעה ');
  buf.write(displayHour12);
  buf.write(' ');
  buf.write(partOfDay);
  if (minutes > 0) {
    buf.write(' ו-');
    buf.write(minutes);
    buf.write(minutes == 1 ? ' דקה' : ' דקות');
  }
  if (chalakim > 0) {
    buf.write(' ו-');
    buf.write(chalakim);
    buf.write(chalakim == 1 ? ' חלק' : ' חלקים');
  }
  return buf.toString();
}

/// המרת שעה 0-23 ל-12-hour-clock עברי. שעה 0 (חצות) → 12, שעה 13 → 1, וכו'.
int _to12HourClock(int hour24) {
  final mod = hour24 % 12;
  return mod == 0 ? 12 : mod;
}

/// תיאור חלקי היום לפי השעה (LMT, 0-23).
/// 12:00-12:59 → "בצהריים" (לא "אחר הצהריים", כי מקובל לומר "12 בצהריים").
String _partOfDayLabel(int hour) {
  if (hour >= 6 && hour < 12) return 'בבוקר';
  if (hour == 12) return 'בצהריים';
  if (hour > 12 && hour < 18) return 'אחר הצהריים';
  if (hour >= 18 && hour < 24) return 'בערב';
  return 'בלילה'; // 0..5
}

// ============================================================================
// חישוב true conjunction (אלגוריתם Meeus, "Astronomical Algorithms" פרק 49)
// ============================================================================

/// מחשב את הזמן האסטרונומי המדויק של ה-conjunction (מולד הנראה) בחודש העברי
/// שהקלנדר מצביע עליו. מחזיר DateTime ב-UTC.
///
/// אם החישוב נכשל מסיבה כלשהי, מחזיר את ה-fallback (המולד הממוצע).
///
/// הדיוק של האלגוריתם הוא ±~3 דקות לתאריכים בעידן הנוכחי.
DateTime _calculateTrueConjunctionUtc(
  JewishCalendar targetMonthCalendar, {
  required DateTime fallbackLmtMolad,
}) {
  try {
    // מצא את ה-lunation number k הקרוב ביותר ל-mean molad של החודש הזה.
    // k=0 מוגדר כ-conjunction של 6 בינואר 2000.
    final meanMoladUtc = fallbackLmtMolad;
    final yearFraction = _toDecimalYear(meanMoladUtc);
    final kApprox = ((yearFraction - 2000) * 12.3685).round();

    // חשב את ה-true conjunction עבור kApprox.
    final jde = _meeusConjunctionJde(kApprox);
    final result = _jdToUtc(jde);

    // אם התוצאה רחוקה יותר מ-30 ימים מ-mean molad, ננסה k שכן.
    final diff = result.difference(meanMoladUtc).inHours.abs();
    if (diff > 24 * 20) {
      for (final delta in [-1, 1]) {
        final altJde = _meeusConjunctionJde(kApprox + delta);
        final altResult = _jdToUtc(altJde);
        final altDiff = altResult.difference(meanMoladUtc).inHours.abs();
        if (altDiff < diff) return altResult;
      }
    }
    return result;
  } catch (_) {
    return fallbackLmtMolad;
  }
}

/// המרה לשנה עשרונית (לחישוב k ב-Meeus).
double _toDecimalYear(DateTime utc) {
  final yearStart = DateTime.utc(utc.year);
  final yearEnd = DateTime.utc(utc.year + 1);
  final yearLength = yearEnd.difference(yearStart).inSeconds;
  final elapsed = utc.difference(yearStart).inSeconds;
  return utc.year + (elapsed / yearLength);
}

/// חישוב JDE של ה-conjunction עבור lunation k, לפי Meeus פרק 49.
double _meeusConjunctionJde(int k) {
  final kDouble = k.toDouble();
  final t = kDouble / 1236.85;
  final t2 = t * t;
  final t3 = t2 * t;
  final t4 = t3 * t;

  // Mean time of conjunction (Meeus 49.1)
  double jde =
      2451550.09766 +
      29.530588861 * kDouble +
      0.00015437 * t2 -
      0.000000150 * t3 +
      0.00000000073 * t4;

  // Sun's mean anomaly (M)
  final m = _toRad(
    2.5534 + 29.10535670 * kDouble - 0.0000014 * t2 - 0.00000011 * t3,
  );

  // Moon's mean anomaly (M')
  final mPrime = _toRad(
    201.5643 +
        385.81693528 * kDouble +
        0.0107582 * t2 +
        0.00001238 * t3 -
        0.000000058 * t4,
  );

  // Moon's argument of latitude (F)
  final f = _toRad(
    160.7108 +
        390.67050284 * kDouble -
        0.0016118 * t2 -
        0.00000227 * t3 +
        0.000000011 * t4,
  );

  // Longitude of ascending node (Omega)
  final omega = _toRad(
    124.7746 - 1.56375588 * kDouble + 0.0020672 * t2 + 0.00000215 * t3,
  );

  // Earth orbit eccentricity factor (E)
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  final e2 = e * e;

  // Planetary corrections — main terms (Meeus 49.A)
  double corr = 0.0;
  corr += -0.40720 * math.sin(mPrime);
  corr += 0.17241 * e * math.sin(m);
  corr += 0.01608 * math.sin(2 * mPrime);
  corr += 0.01039 * math.sin(2 * f);
  corr += 0.00739 * e * math.sin(mPrime - m);
  corr += -0.00514 * e * math.sin(mPrime + m);
  corr += 0.00208 * e2 * math.sin(2 * m);
  corr += -0.00111 * math.sin(mPrime - 2 * f);
  corr += -0.00057 * math.sin(mPrime + 2 * f);
  corr += 0.00056 * e * math.sin(2 * mPrime + m);
  corr += -0.00042 * math.sin(3 * mPrime);
  corr += 0.00042 * e * math.sin(m + 2 * f);
  corr += 0.00038 * e * math.sin(m - 2 * f);
  corr += -0.00024 * e * math.sin(2 * mPrime - m);
  corr += -0.00017 * math.sin(omega);
  corr += -0.00007 * math.sin(mPrime + 2 * m);
  corr += 0.00004 * math.sin(2 * mPrime - 2 * f);
  corr += 0.00004 * math.sin(3 * m);
  corr += 0.00003 * math.sin(mPrime + m - 2 * f);
  corr += 0.00003 * math.sin(2 * mPrime + 2 * f);
  corr += -0.00003 * math.sin(mPrime + m + 2 * f);
  corr += 0.00003 * math.sin(mPrime - m + 2 * f);
  corr += -0.00002 * math.sin(mPrime - m - 2 * f);
  corr += -0.00002 * math.sin(3 * mPrime + m);
  corr += 0.00002 * math.sin(4 * mPrime);

  jde += corr;

  // המרה מ-Terrestrial Dynamical Time (TDT) ל-UT: מחסירים את delta-T.
  // לעידן הנוכחי (2000-2050) delta-T ≈ 65-90 שניות. נשתמש בקירוב פשוט.
  final deltaTSeconds = _approxDeltaT(t);
  jde -= deltaTSeconds / 86400.0;

  return jde;
}

double _toRad(double deg) => deg * (math.pi / 180.0);

/// קירוב פשוט ל-delta-T (ההפרש בין TDT ל-UT) לשנים בעידן הנוכחי.
/// נוסחה פולינומית של NASA לתקופה 2005-2050.
double _approxDeltaT(double t) {
  // t = (k / 1236.85). שנה גרגוריאנית מקורבת:
  final year = 2000.0 + t * 100.0;
  // נוסחת NASA לתקופה 2005-2050:
  final u = (year - 2000) / 100.0;
  return 62.92 + 32.217 * u + 55.89 * u * u;
}

/// המרת Julian Date ל-DateTime UTC.
DateTime _jdToUtc(double jd) {
  final jdPlus = jd + 0.5;
  final z = jdPlus.floor();
  final f = jdPlus - z;
  int a;
  if (z < 2299161) {
    a = z;
  } else {
    final alpha = ((z - 1867216.25) / 36524.25).floor();
    a = z + 1 + alpha - (alpha / 4).floor();
  }
  final b = a + 1524;
  final c = ((b - 122.1) / 365.25).floor();
  final d = (365.25 * c).floor();
  final e = ((b - d) / 30.6001).floor();
  final dayWithFraction = b - d - (30.6001 * e).floor() + f;
  final day = dayWithFraction.floor();
  final dayFraction = dayWithFraction - day;
  final month = e < 14 ? e - 1 : e - 13;
  final year = month > 2 ? c - 4716 : c - 4715;

  final totalSeconds = (dayFraction * 86400).round();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  return DateTime.utc(year, month, day, hours, minutes, seconds);
}
