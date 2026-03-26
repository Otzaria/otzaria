import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:timezone/timezone.dart' as tz;

/// מחשב את כל הזמנים ההלכתיים ליום נתון ועיר נתונה
Map<String, String> calculateDailyTimes(DateTime date, String city) {
  final cityData = getCityData(city);
  if (cityData == null) return {};

  final latitude = cityData['lat']!;
  final longitude = cityData['lng']!;
  final elevation = cityData['elevation']!;
  final timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';

  final location = GeoLocation();
  location.setLocationName(city);
  location.setLatitude(latitude: latitude);
  location.setLongitude(longitude: longitude);
  location.setElevation(elevation > 0 ? elevation : 0);

  final tzLocation = tz.getLocation(timeZoneId);
  final tzDateTime = tz.TZDateTime.from(date, tzLocation);
  location.setDateTime(tzDateTime);

  final zmanimCalendar = ComplexZmanimCalendar.intGeoLocation(location);

  final bool isInIsrael = isCityInIsrael(city);
  final jewishCalendar = JewishCalendar.fromDateTime(date);
  jewishCalendar.inIsrael = isInIsrael;

  final Map<String, String> times = {
    'alos': formatZmanTime(zmanimCalendar.getAlosHashachar()!, tzLocation),
    'alos16point1Degrees':
        formatZmanTime(zmanimCalendar.getAlos16Point1Degrees()!, tzLocation),
    'alos19point8Degrees':
        formatZmanTime(zmanimCalendar.getAlos19Point8Degrees()!, tzLocation),
    'sunrise': formatZmanTime(zmanimCalendar.getSunrise()!, tzLocation),
    'sofZmanShmaMGA':
        formatZmanTime(zmanimCalendar.getSofZmanShmaMGA()!, tzLocation),
    'sofZmanShmaGRA':
        formatZmanTime(zmanimCalendar.getSofZmanShmaGRA()!, tzLocation),
    'sofZmanTfilaMGA':
        formatZmanTime(zmanimCalendar.getSofZmanTfilaMGA()!, tzLocation),
    'sofZmanTfilaGRA':
        formatZmanTime(zmanimCalendar.getSofZmanTfilaGRA()!, tzLocation),
    'chatzos': formatZmanTime(zmanimCalendar.getChatzos()!, tzLocation),
    'chatzosLayla':
        formatZmanTime(_calculateChatzosLayla(zmanimCalendar), tzLocation),
    'minchaGedola':
        formatZmanTime(zmanimCalendar.getMinchaGedola()!, tzLocation),
    'minchaKetana':
        formatZmanTime(zmanimCalendar.getMinchaKetana()!, tzLocation),
    'plagHamincha':
        formatZmanTime(zmanimCalendar.getPlagHamincha()!, tzLocation),
    'sunset': formatZmanTime(zmanimCalendar.getSunset()!, tzLocation),
    'sunsetRT': formatZmanTime(_calculateSunsetRT(zmanimCalendar), tzLocation),
    'tzais': formatZmanTime(zmanimCalendar.getTzais()!, tzLocation),
  };

  _addSpecialTimes(times, jewishCalendar, zmanimCalendar, city, tzLocation);
  return times;
}

/// מעצב שעה לפורמט HH:MM עם תמיכה ב-timezone
String formatZmanTime(DateTime dt, tz.Location tzLocation) {
  final tzDateTime = tz.TZDateTime.from(dt, tzLocation);
  return '${tzDateTime.hour.toString().padLeft(2, '0')}:${tzDateTime.minute.toString().padLeft(2, '0')}';
}

// חישוב חצות לילה
DateTime _calculateChatzosLayla(ComplexZmanimCalendar zmanimCalendar) {
  final chatzos = zmanimCalendar.getChatzos()!;
  return chatzos.add(const Duration(hours: 12));
}

// חישוב שקיעה לפי רבנו תם
DateTime _calculateSunsetRT(ComplexZmanimCalendar zmanimCalendar) {
  final sunset = zmanimCalendar.getSunset()!;
  return sunset.add(const Duration(minutes: 72));
}

// הוספת זמנים מיוחדים לחגים ושבת
void _addSpecialTimes(
  Map<String, String> times,
  JewishCalendar jewishCalendar,
  ComplexZmanimCalendar zmanimCalendar,
  String city,
  tz.Location tzLocation,
) {
  if (jewishCalendar.getYomTovIndex() == JewishCalendar.EREV_PESACH) {
    final sofZmanAchilasChametzMGA =
        zmanimCalendar.getSofZmanAchilasChametzMGA72Minutes();
    if (sofZmanAchilasChametzMGA != null) {
      times['sofZmanAchilasChametzMGA'] =
          formatZmanTime(sofZmanAchilasChametzMGA, tzLocation);
    }
    final sofZmanAchilasChametzGRA =
        zmanimCalendar.getSofZmanAchilasChametzGRA();
    if (sofZmanAchilasChametzGRA != null) {
      times['sofZmanAchilasChametzGRA'] =
          formatZmanTime(sofZmanAchilasChametzGRA, tzLocation);
    }
    final sofZmanBiurChametzMGA =
        zmanimCalendar.getSofZmanBiurChametzMGA72Minutes();
    if (sofZmanBiurChametzMGA != null) {
      times['sofZmanBiurChametzMGA'] =
          formatZmanTime(sofZmanBiurChametzMGA, tzLocation);
    }
    final sofZmanBiurChametzGRA = zmanimCalendar.getSofZmanBiurChametzGRA();
    if (sofZmanBiurChametzGRA != null) {
      times['sofZmanBiurChametzGRA'] =
          formatZmanTime(sofZmanBiurChametzGRA, tzLocation);
    }
  }

  if (jewishCalendar.getDayOfWeek() == 6 || jewishCalendar.isErevYomTov()) {
    final candleLighting = _calculateCandleLightingTime(zmanimCalendar, city);
    if (candleLighting != null) {
      times['candleLighting'] = formatZmanTime(candleLighting, tzLocation);
    }
  }

  if (jewishCalendar.getDayOfWeek() == 7 || jewishCalendar.isYomTov()) {
    final shabbosExitTime1 = _calculateShabbosExitTime1(zmanimCalendar);
    final shabbosExitTime2 = _calculateShabbosExitTime2(zmanimCalendar);
    if (shabbosExitTime1 != null) {
      times['shabbosExit1'] = formatZmanTime(shabbosExitTime1, tzLocation);
    }
    if (shabbosExitTime2 != null) {
      times['shabbosExit2'] = formatZmanTime(shabbosExitTime2, tzLocation);
    }
  }

  if (jewishCalendar.getDayOfOmer() != -1) {
    final omerCountingTime = zmanimCalendar.getTzais();
    if (omerCountingTime != null) {
      times['omerCounting'] = formatZmanTime(omerCountingTime, tzLocation);
    }
  }

  if (jewishCalendar.isTaanis() &&
      jewishCalendar.getYomTovIndex() != JewishCalendar.YOM_KIPPUR) {
    final fastStart = zmanimCalendar.getAlosHashachar();
    final fastEnd = zmanimCalendar.getTzais();
    if (fastStart != null) {
      times['fastStart'] = formatZmanTime(fastStart, tzLocation);
    }
    if (fastEnd != null) {
      times['fastEnd'] = formatZmanTime(fastEnd, tzLocation);
    }
  }

  if (_isKidushLevanaTime(jewishCalendar)) {
    final earliest =
        _calculateKidushLevanaEarliest(jewishCalendar, zmanimCalendar);
    final latest = _calculateKidushLevanaLatest(jewishCalendar, zmanimCalendar);
    if (earliest != null) {
      times['kidushLevanaEarliest'] = formatZmanTime(earliest, tzLocation);
    }
    if (latest != null) {
      times['kidushLevanaLatest'] = formatZmanTime(latest, tzLocation);
    }
  }

  try {
    final tchilasKidushLevana =
        zmanimCalendar.getTchilasZmanKidushLevana3Days();
    final sofZmanKidushLevana =
        zmanimCalendar.getSofZmanKidushLevanaBetweenMoldos();
    if (tchilasKidushLevana != null) {
      times['tchilasKidushLevana'] =
          formatZmanTime(tchilasKidushLevana, tzLocation);
    }
    if (sofZmanKidushLevana != null) {
      times['sofZmanKidushLevana'] =
          formatZmanTime(sofZmanKidushLevana, tzLocation);
    }
  } catch (e) {
    // Ignore errors for certain dates
  }
}

DateTime? _calculateCandleLightingTime(
    ComplexZmanimCalendar zmanimCalendar, String city) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;
  int minutesBefore;
  switch (city) {
    case 'ירושלים':
      minutesBefore = 40;
      break;
    case 'בני ברק':
      minutesBefore = 22;
      break;
    case 'מודיעין עילית':
      minutesBefore = 30;
      break;
    default:
      minutesBefore = 30;
      break;
  }
  return sunset.subtract(Duration(minutes: minutesBefore));
}

DateTime? _calculateShabbosExitTime1(ComplexZmanimCalendar zmanimCalendar) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;
  return sunset.add(const Duration(minutes: 34));
}

DateTime? _calculateShabbosExitTime2(ComplexZmanimCalendar zmanimCalendar) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;
  return sunset.add(const Duration(minutes: 38));
}

bool _isKidushLevanaTime(JewishCalendar jewishCalendar) {
  final dayOfMonth = jewishCalendar.getJewishDayOfMonth();
  return dayOfMonth >= 3 && dayOfMonth <= 15;
}

DateTime? _calculateKidushLevanaEarliest(
    JewishCalendar jewishCalendar, ComplexZmanimCalendar zmanimCalendar) {
  if (jewishCalendar.getJewishDayOfMonth() == 3) {
    return zmanimCalendar.getTzais();
  }
  return null;
}

DateTime? _calculateKidushLevanaLatest(
    JewishCalendar jewishCalendar, ComplexZmanimCalendar zmanimCalendar) {
  if (jewishCalendar.getJewishDayOfMonth() == 15) {
    return zmanimCalendar.getAlosHashachar();
  }
  return null;
}
