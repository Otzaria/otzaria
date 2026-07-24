import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/models/zman_definition.dart';
import 'package:timezone/timezone.dart' as tz;

class ZmanimCalendarContext {
  final ComplexZmanimCalendar zmanimCalendar;
  final tz.Location tzLocation;

  const ZmanimCalendarContext({
    required this.zmanimCalendar,
    required this.tzLocation,
  });
}

ZmanimCalendarContext? buildZmanimCalendarContext(DateTime date, String city) {
  final cityData = getCityData(city);
  if (cityData == null) return null;

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
  final tzDateTime = tz.TZDateTime(
    tzLocation,
    date.year,
    date.month,
    date.day,
    date.hour,
    date.minute,
    date.second,
    date.millisecond,
    date.microsecond,
  );
  location.setDateTime(tzDateTime);

  return ZmanimCalendarContext(
    zmanimCalendar: ComplexZmanimCalendar.intGeoLocation(location),
    tzLocation: tzLocation,
  );
}

/// מחשב את כל הזמנים ההלכתיים הרלוונטיים ליום נתון ועיר נתונה, לפי
/// ה-[kZmanimRegistry]. הרישום הוא מקור-האמת היחיד — כל זמן מחושב פעם
/// אחת מתוך פונקציית החישוב שלו, ונשמר תחת מזהה ההגדרה.
Map<String, String> calculateDailyTimes(DateTime date, String city) {
  final context = buildZmanimCalendarContext(date, city);
  if (context == null) return {};
  final zmanimCalendar = context.zmanimCalendar;
  final tzLocation = context.tzLocation;

  final bool isInIsrael = isCityInIsrael(city);
  final jewishCalendar = JewishCalendar.fromDateTime(date);
  jewishCalendar.inIsrael = isInIsrael;

  final ctx = ZmanComputeContext(
    cal: zmanimCalendar,
    jewishCalendar: jewishCalendar,
    city: city,
    date: date,
  );

  final Map<String, String> times = {};
  for (final def in kZmanimRegistry) {
    if (def.isRelevant != null && !def.isRelevant!(jewishCalendar)) continue;
    DateTime? dt;
    try {
      dt = def.compute(ctx);
    } catch (_) {
      dt = null; // חישובים מסוימים זורקים בתאריכים חריגים (קידוש לבנה)
    }
    if (dt != null) {
      if (def.showHebrewDate) {
        final label = formatKidushLevanaNight(
          dt,
          city,
          pushToTzais: def.moladPushToTzais,
        );
        if (label != null) times[def.id] = label;
      } else {
        times[def.id] = formatZmanTime(dt, tzLocation);
      }
    }
  }

  // ספירת העומר מוצגת ככפתור ייעודי (לא ככרטיס זמן), ולכן מחושבת בנפרד.
  if (jewishCalendar.getDayOfOmer() != -1) {
    final omer = zmanimCalendar.getTzais();
    if (omer != null) {
      times['omerCounting'] = formatZmanTime(omer, tzLocation);
    }
  }

  return times;
}

/// מחזיר את סימן השניות בשיטת "לוח עיתים לבינה": נקודה (`.`) כשהשניות
/// 0–29, נקודותיים (`:`) כשהן 30–59. הסימן מציין לקורא אם הזמן האמיתי
/// נופל במחצית הראשונה או השנייה של הדקה (הזמן עצמו אינו מעוגל).
String secondsMarker(DateTime dt) => dt.second < 30 ? '.' : ':';

/// תווי בידי לעטיפת השעה כיחידת LTR: LEFT-TO-RIGHT ISOLATE ו-POP.
/// בלעדיהם סימן השניות (תו ניטרלי) נדחף משמאל למספרים בהקשר RTL, כי
/// ספרות נחשבות לכיוון ימני בפתרון תווים ניטרליים. העטיפה מקבעת את סדר
/// המקטע כ-LTR ומשאירה את הסימן צמוד מימין למספרים.
const String _ltrIsolateStart = '\u2066';
const String _ltrIsolateEnd = '\u2069';

/// מעצב שעה לפורמט HH:MM עם תמיכה ב-timezone, ובסופו סימן שניות
/// ([secondsMarker]) בשיטת לוח עיתים לבינה. הזמן נחתך לדקה ואינו מעוגל,
/// והמקטע עטוף ב-LTR isolate לתצוגה תקינה ב-RTL.
String formatZmanTime(DateTime dt, tz.Location tzLocation) {
  final tzDateTime = tz.TZDateTime.from(dt, tzLocation);
  final hh = tzDateTime.hour.toString().padLeft(2, '0');
  final mm = tzDateTime.minute.toString().padLeft(2, '0');
  return '$_ltrIsolateStart$hh:$mm${secondsMarker(tzDateTime)}$_ltrIsolateEnd';
}

// תומך בעטיפת ה-LTR isolate ובסימן השניות האופציונלי (`.`/`:`).
final RegExp _clockTimePattern = RegExp(
  '^$_ltrIsolateStart?'
  r'\d{1,2}:\d{2}[.:]?'
  '$_ltrIsolateEnd?\$',
);

/// בודק אם מחרוזת זמן היא שעת-שעון (HH:MM) — שעבורה מיון לקסיקוגרפי שקול
/// למיון כרונולוגי. זמני קידוש לבנה מוצגים כתאריך עברי ("ליל ... HH:MM")
/// ואינם ברי-מיון כרונולוגי לפי מחרוזת התצוגה.
bool isClockTime(String time) => _clockTimePattern.hasMatch(time);

const List<String> _hebrewNightNames = [
  '',
  'ליל ראשון',
  'ליל שני',
  'ליל שלישי',
  'ליל רביעי',
  'ליל חמישי',
  'ליל שישי',
  'ליל שבת',
];

/// מעצב זמן קידוש לבנה כתאריך עברי לילי בזמן המקומי של העיר, למשל
/// "ליל שני ט"ו לחודש 20:02".
///
/// [rawMolad] הוא הרגע הגולמי (מולד + ימים) כפי שמחזירה kosher_dart דרך
/// `JewishCalendar` — DateTime נאיבי בזמן ירושלים סטנדרטי (GMT+2 קבוע, ללא
/// שעון קיץ). הפונקציה:
///   1. ממירה אותו ל-instant מוחלט ולזמן המקומי של העיר (תיקון אזור הזמן —
///      אחרת כל הערים היו מקבלות אותה שעה).
///   2. דוחה אותו לזמן לילי אם הוא נופל ביום (קידוש לבנה אינו נאמר ביום):
///      ל[pushToTzais] true → צאת הכוכבים (תחילת הזמן), false → עלות השחר
///      (סוף הזמן).
///   3. קובעת את ליל-השבוע ויום-החודש העברי לפי השעה בפועל (קידום ליום העברי
///      הבא רק אם הרגע חל אחרי השקיעה).
///
/// מחזירה null אם נתוני העיר או זמני היום אינם זמינים.
String? formatKidushLevanaNight(
  DateTime rawMolad,
  String city, {
  required bool pushToTzais,
}) {
  final cityData = getCityData(city);
  if (cityData == null) return null;
  final tzId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';
  final tzLocation = tz.getLocation(tzId);

  // הרגע מבוטא בזמן ירושלים סטנדרטי (GMT+2) — ממירים ל-instant ואז לזמן העיר.
  final rawInstant = DateTime.utc(
    rawMolad.year,
    rawMolad.month,
    rawMolad.day,
    rawMolad.hour,
    rawMolad.minute,
    rawMolad.second,
  ).subtract(const Duration(hours: 2));
  final localMoment = tz.TZDateTime.from(rawInstant, tzLocation);

  // בונים לוח זמנים ליום (האזרחי) שבו הרגע נופל בעיר, לחישוב עלות/צאת/שקיעה.
  final dayContext = buildZmanimCalendarContext(
    DateTime(localMoment.year, localMoment.month, localMoment.day),
    city,
  );
  final cal = dayContext?.zmanimCalendar;
  final alos = cal?.getAlosHashachar();
  final tzais = cal?.getTzais();
  final sunset = cal?.getSunset();

  tz.TZDateTime chosen = localMoment;
  tz.TZDateTime? sunsetLocal;
  if (alos != null && tzais != null && sunset != null) {
    final alosLocal = tz.TZDateTime.from(alos, tzLocation);
    final tzaisLocal = tz.TZDateTime.from(tzais, tzLocation);
    sunsetLocal = tz.TZDateTime.from(sunset, tzLocation);
    // אם הרגע נופל בשעות היום (בין עלות השחר לצאת הכוכבים) — דוחים אותו.
    if (rawInstant.isAfter(alosLocal.toUtc()) &&
        rawInstant.isBefore(tzaisLocal.toUtc())) {
      chosen = pushToTzais ? tzaisLocal : alosLocal;
    }
  }

  // הרגע שייך ליום העברי הבא רק אם הוא חל אחרי שקיעת אותו יום אזרחי.
  final isNight = sunsetLocal != null && chosen.isAfter(sunsetLocal);
  return _formatHebrewNightLabel(chosen, advanceToNextDay: isNight);
}

/// מעצב תאריך עברי לילי לתצוגה: "ליל <שבוע> <יום-חודש> לחודש HH:MM".
/// [advanceToNextDay] מקדם את היום העברי (כשהרגע חל אחרי השקיעה).
String _formatHebrewNightLabel(
  DateTime moment, {
  required bool advanceToNextDay,
}) {
  final time =
      '$_ltrIsolateStart${moment.hour.toString().padLeft(2, '0')}:${moment.minute.toString().padLeft(2, '0')}${secondsMarker(moment)}$_ltrIsolateEnd';
  final jewishDate = JewishDate.fromDateTime(
    DateTime(moment.year, moment.month, moment.day),
  );
  if (advanceToNextDay) jewishDate.forward();
  final formatter = HebrewDateFormatter()..hebrewFormat = true;
  final dayOfMonth = formatter.formatHebrewNumber(
    jewishDate.getJewishDayOfMonth(),
  );
  final dayOfWeek = jewishDate.getDayOfWeek();
  final nightName = (dayOfWeek >= 1 && dayOfWeek <= 7)
      ? _hebrewNightNames[dayOfWeek]
      : '';
  return '$nightName $dayOfMonth לחודש $time';
}

// ===========================================================================
// פונקציות חישוב מותאמות (שאינן קריאה ישירה ל-kosher_dart)
// ===========================================================================

/// חצות לילה אסטרונומי — נקודת האמצע בין שקיעת היום לזריחת המחרת.
/// מחושב ידנית בגלל באג ב-getSolarMidnight של kosher_dart 2.0.20 עם
/// TZDateTime (מסיג את התאריך ביום).
DateTime? calculateSolarMidnight(
  ComplexZmanimCalendar zmanimCalendar,
  String city,
  DateTime date,
) {
  // בקווי רוחב קיצוניים השקיעה/הזריחה עשויות להיות null (יום/לילה רצוף).
  final sunsetToday = zmanimCalendar.getSunset();
  if (sunsetToday == null) return null;

  // נפילה אחורה: חצות היום + 12 שעות כקירוב לחצות הלילה.
  DateTime? fallback() {
    final chatzos = zmanimCalendar.getChatzos();
    return chatzos?.add(const Duration(hours: 12));
  }

  final tomorrowContext = buildZmanimCalendarContext(
    date.add(const Duration(days: 1)),
    city,
  );
  final sunriseTomorrow = tomorrowContext?.zmanimCalendar.getSunrise();
  if (sunriseTomorrow == null) return fallback();

  final nightMs =
      sunriseTomorrow.millisecondsSinceEpoch -
      sunsetToday.millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(
    sunsetToday.millisecondsSinceEpoch + nightMs ~/ 2,
    isUtc: sunsetToday.isUtc,
  );
}

/// זמן הדלקת נרות — מספר הדקות לפני השקיעה משתנה לפי מנהג העיר.
DateTime? calculateCandleLightingTime(
  ComplexZmanimCalendar zmanimCalendar,
  String city,
) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;
  final minutesBefore = getCandleLightingMinutes(city);
  return sunset.subtract(Duration(minutes: minutesBefore));
}

// ===========================================================================
// פונקציות עזר לרלוונטיות (תלות-יום) של זמנים
// ===========================================================================

bool _isErevPesach(JewishCalendar jc) =>
    jc.getYomTovIndex() == JewishCalendar.EREV_PESACH;

// ב-JewishCalendar הימים ממוספרים 1=ראשון..7=שבת, כך שיום שישי = 6.
bool _isErevShabbosOrYomTov(JewishCalendar jc) =>
    jc.getDayOfWeek() == 6 || jc.isErevYomTov();

bool _isMotzeiShabbos(JewishCalendar jc) =>
    jc.isAssurBemelacha() && jc.getDayOfWeek() == 7;

bool _isMotzeiYomTov(JewishCalendar jc) =>
    jc.isAssurBemelacha() && jc.isYomTov() && jc.getDayOfWeek() != 7;

bool _isTaanisNotYomKippur(JewishCalendar jc) =>
    jc.isTaanis() && jc.getYomTovIndex() != JewishCalendar.YOM_KIPPUR;

// ===========================================================================
// רישום הזמנים המרכזי — מקור-האמת היחיד לחישוב, תצוגה והסבר.
// כל הגדרה היא זמן בודד (שורה נפרדת בטבלה + מתג). שתי הגדרות עם אותו
// pairId מוצגות יחד ככרטיס אחד בלוח (כותרת משותפת + תווית לכל ערך).
// הקטגוריות מסודרות לפי סדר הזמנים ביום.
// ===========================================================================

final List<ZmanDefinition> kZmanimRegistry = [
  // ── עלות השחר ──────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'alos72Degrees',
    title: 'עלות השחר',
    subtitle: '72 דק׳ (מעלות)',
    category: 'עלות השחר',
    explanation:
        '''כשהשמש 16 מעלות תחת האופק, 72 דק׳ בימי השיויון, ד׳ מיל של 18 דק׳.
בסוגיא דמסכת פסחים דף צ"ד מבואר שעלות השחר הוא ד׳ מיל קודם הנץ החמה. ודעת התרומת הדשן השו"ע והרמ"א ורוב הפוסקים והחזו"א, דהילוך מיל 18 דק׳, וד׳ מיל הם 72 דק׳ קודם הנץ. ויש להיזהר לא לקיים את מצוות היום קודם לזמן זה, שהוא לילה, ואם עשה כן לדעה זו לא יצא ידי חובתו. השלכות עלות השחר להלכה: לסוף זמן מצוות הנוהגות בלילה, כגון קריאת שמע של ערבית בדיעבד (ונקרא עובר ע"ד חכמים, דלכתחילה עד חצות, עי׳ או"ח רל"ה ג׳-ד׳) תפילת ערבית (מ"ב שם ס"ק ל"ד), ספירת העומר בברכה, מצוות סיפור יציאת מצרים, קריאת המגילה בלילה, תחילת שעות היום לדעת הרבה מהראשונים, ותחילת זמנן של המצוות הנוהגות ביום בדיעבד, כגון לולב, מגילה, שופר, הלל וכדו׳ (מגילה כ.), זמן תפילת שחרית בשעת הדחק, איסור לימוד והתעסקות בצרכיו ואכילה לפני התפילה (או"ח פ"ט א׳-ו׳), זמן תחילת צומות המתחילים מהיום. ועוד. קבענו שיטה זו במעלות, כשהשמש 16 מעלות תחת לאופק, שהוא בימי ניסן ותשרי 72 דק׳ קודם הנץ החמה.''',
    defaultEnabled: true,
    pairId: 'alosDeg',
    pairLabel: '72 דק׳ (מעלות)',
    compute: (c) => c.cal.getAlos16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'alos90Degrees',
    title: 'עלות השחר',
    subtitle: '90 דק׳ (מעלות)',
    category: 'עלות השחר',
    explanation:
        '''כשהשמש 19.75 מעלות תחת האופק, 90 דק׳ בימי השיויון, ד׳ מיל של 22.5 דק׳
בסוגיא דמסכת פסחים דף צ"ד מבואר שעלות השחר הוא ד׳ מיל קודם הנץ החמה. ובלוח שבספר בין השמשות להרי"מ טוקצ׳ינסקי קבע את זמן עה"ש 90 דקות במעלות קודם הנץ, וכן נערכו הלוחות בירושלים מתחילת היוסדם, לוח דברי יוסף שווארץ, לוח הנברשת, לוח הרב משה שפירא, וכן הביא המנהג בכה"ח סי׳ פ"ט אות ד׳ ["קרוב לשמינית היום"]. וזה כשיטת הרבה ראשונים שהילוך מיל הוא 22.5 דקות, וד׳ מיל הם 90 דק׳. אמנם דעת רוב הפוסקים וכן העיקר להלכה שהילוך מיל הוא 18 דק׳ וד׳ מיל הם 72 דק׳ לפני הנץ בימי השיוויון. ולכן נפקא מינה להשתמש בטור זה של 90 דק׳ רק לחומרא, כגון למהר לקרוא קריאת שמע של לילה ולהתפלל ערבית (אם לא אמרם קודם לכן) עד לזמן זה, ולספור ספירת העומר בברכה רק עד זמן זה, או להתחיל הצומות המתחילים ביום מזמן זה, וכן לחשב ממנו את אורך היום לענין זמני היום כסו"ז קריאת שמע ועוד. קבענו שיטה זו במעלות, כשהשמש 19.75 מע׳ תחת לאופק, שהוא בימי ניסן ותשרי כ-90 דק׳ קודם הנץ החמה.''',
    defaultEnabled: true,
    pairId: 'alosDeg',
    pairLabel: '90 דק׳ (מעלות)',
    compute: (c) => c.cal.getAlos19Point8Degrees(),
  ),
  ZmanDefinition(
    id: 'alos120Degrees',
    title: 'עלות השחר',
    subtitle: '120 דק׳ (מעלות)',
    category: 'עלות השחר',
    explanation:
        '''כשהשמש 25.9 מעלות תחת האופק, 120 דק׳ בימי השיויון, ה׳ מיל של 24 דק׳.
בסוגיא דמסכת פסחים דף צ"ד מבואר שלדעת רבא ועולא עלות השחר הוא ה׳ מיל קודם הנץ החמה, ואיתותב עולא. ואם אדם מהלך ביום ל מיל, יוצא אורך המיל 24 דק׳ (24=720/30), ו-5 מיל 120 דק׳. וברמב"ם מבואר שהילוך מיל הוא 24 דק׳, וכן נקט בשיטת בעל התניא הרא"ח נאה (ראה זמנים בהלכה ח"א עמ׳ קצ"ה). והנה שיטה זו לא נפסקה להלכה ולכן אין לחוש לה לדינא גם לא לחומרא. והבאנוה למעוניינים להחמיר על פיה כמה הנהגות והם: למהר לקרוא קריאת שמע של לילה ולהתפלל ערבית (אם לא אמרם קודם לכן) עד לזמן זה, ולהזדרז לספור בברכה ספירת העומר עד זמן זה, או להתחיל הצומות המתחילים ביום מזמן זה. קבענו שיטה זו במעלות, כשהשמש 25.9 מעלות תחת לאופק, שהוא בימי ניסן ותשרי 120 דק׳ קודם הנץ החמה.''',
    compute: (c) => c.cal.getAlos26Degrees(),
  ),
  ZmanDefinition(
    id: 'alos72Shavos',
    title: 'עלות השחר',
    subtitle: '72 דק׳ (שוות)',
    category: 'עלות השחר',
    explanation: '''כן נהוג בהרבה קהילות בארה"ב לונדון ופנמה
במנחת כהן (פ"ב ד"ה השנית) הוכיח כשיטת השוות מפשיטות כל הקדמונים, ובפתח הבית (סי' ח') ובמחצית השקל (רל"ה סק"ג) ובסידור דרך החיים (הל' ערב שבת) וכן בפרי מגדים (רס"א סק"ט) הביאו הביאור הלכה (שם ד"ה שהוא), כתבו שהארבעה מילין הם בשעות שוות, ולא בשעות זמניות. וכמה אחרונים הלכו בדרך זו. ולפי"ז ד' מיל לשיטה שמיל 18 דק', הם 72 דק' שוות כל השנה. והבאנו זמן זה לנוהגים כן למעשה, כמנהג החסידים בארה"ב ובלונדון וכן נהגו בפנמה (הסמוכה לקו המשווה).''',
    pairId: 'alosShavos',
    pairLabel: '72 דק׳ (שוות)',
    compute: (c) => c.cal.getAlos72(),
  ),
  ZmanDefinition(
    id: 'alos90Shavos',
    title: 'עלות השחר',
    subtitle: '90 דק׳ (שוות)',
    category: 'עלות השחר',
    explanation: '''ד' מיל של 22.5 דק' שהם 90 דק' שוות כל השנה.
בפרי מגדים (סימן רס"א) הביאו הביאור הלכה כתב שהארבעה מילין הם שעות שוות, ולא שעות זמניות. וכמה אחרונים הלכו בדרך זו. ולפי"ז ד' מיל לשיטה שמיל 22.5 דק', הם 90 דק' שוות כל השנה. ולא שמעתי על קהילה הנוהגת כן למעשה.''',
    pairId: 'alosShavos',
    pairLabel: '90 דק׳ (שוות)',
    compute: (c) => c.cal.getAlos90(),
  ),
  ZmanDefinition(
    id: 'alos120Shavos',
    title: 'עלות השחר',
    subtitle: '120 דק׳ (שוות)',
    category: 'עלות השחר',
    explanation: '''ה' מיל של 24 דק' שהם 120 דק' בכל השנה
בפרי מגדים (סימן רס"א) הביאו הביאור הלכה כתב שהארבעה מילין הם שעות שוות, ולא שעות זמניות. וכמה אחרונים הלכו בדרך זו. ולפי"ז לשיטות שעה"ש ה' מיל ולשיטה שמיל 24 דק', הם 120 דק' שוות כל השנה. ולא שמעתי על קהילה הנוהגת כן למעשה.''',
    compute: (c) => c.cal.getAlos120(),
  ),
  ZmanDefinition(
    id: 'alos72Zmanis',
    title: 'עלות השחר',
    subtitle: '72 דק׳ (זמניות)',
    category: 'עלות השחר',
    explanation:
        '''ד' מיל של 18 דק' בימות השיויון, עשירית מאורך היום שמהנץ לשקיעה
בסוגיא דמסכת פסחים דף צ"ד מבואר שעלות השחר הוא ד' מיל קודם הנץ החמה. ודעת התרומת הדשן השו"ע והרמ"א ורוב הפוסקים והחזו"א, דהילוך מיל 18 דק', וד' מיל הם 72 דק' קודם הנץ. וכן קבעו את זמן עה"ש בלוח אור החיים להלכה. ויש להיזהר לא לקיים את מצוות היום קודם לזמן זה, שהוא לילה, ואם עשה כן לדעה זו לא יצא ידי חובתו. השלכות עלות השחר להלכה: לסוף זמן מצוות הנוהגות בלילה, כגון קריאת שמע של ערבית בדיעבד (ונקרא עובר ע"ד חכמים, דלכתחילה עד חצות, עי' או"ח רל"ה ג'-ד') תפילת ערבית (מ"ב שם ס"ק ל"ד), ספירת העומר בברכה, מצוות סיפור יציאת מצרים, קריאת המגילה בלילה, תחילת שעות היום לדעת הרבה מהראשונים, ותחילת זמנן של המצוות הנוהגות ביום בדיעבד, כגון לולב, מגילה, שופר, הלל וכדו' (מגילה כ.), זמן תפילת שחרית בשעת הדחק, איסור לימוד והתעסקות בצרכיו ואכילה לפני התפילה (או"ח פ"ט א'-ו'), זמן תחילת צומות המתחילים מהיום. ועוד. קבענו שיטה זו בזמניות, שמתחשבת לפי אורך היום ו-72 דק' הם עשירית מאורך היום שבין הנץ לשקיעה בימי ניסן ותשרי שהם 720 דק', וא"כ תמיד עשירית מאורך היום קודם הנץ החמה הוא עלות השחר, וכשיטת הזמניות כן היא דעת הפרי חדש בקונטרסו דבי שמשי, והעתיקוהו אחרונים רבים, מהם הגרע"י בהליכות עולם ח"א עמ' ר"נ, בכף החיים (בציון הנ"ל, ובסי' י"ח ס"ק י"ח) והגרב"צ באור לציון (ח"ב עמ' נ"ב). אלא ששיטת "זמניות" בעלות השחר וצאת הכוכבים קשה מאד להלכה, שהחוש מכחישה, שהרי בעשירית מאורך היום בחורף לפני הנץ יותר מואר בהרבה מ-72 דק' לפני הנץ שבימות השיויון [וכן בעשירית מאורך היום בחורף אחרי השקיעה יש פחות חושך וכוכבים מאשר 72 דק' אחר השקיעה בימות השיוויון], וכבר ברמב"ם (בפירוש המשניות ברכות) ובגר"א (רס"א תנ"ט ויו"ד רס"ב) ובספר אילם לישר מקנדיא (ח"ה אות ס"ד) מבואר שיש ללכת לפי המעלות, ובמדינות הצפוניות זמנם מוקדם יותר, ועכ"פ בשו"ע כתוב עלה השחר והאיר המזרח וכן בראשונים לא הזכירו זמניות ולא כתבו שיטה איך לחשבו, ולפני שהיה שעונים עשו על פי ראיית העין שהיא מקבילה לשיטת המעלות, ולכן כשיטת המעלות יש לנהוג למעשה, ואכמ"ל.
''',
    pairId: 'alosZmanis',
    pairLabel: '72 דק׳ (זמניות)',
    compute: (c) => c.cal.getAlos72Zmanis(),
  ),
  ZmanDefinition(
    id: 'alos90Zmanis',
    title: 'עלות השחר',
    subtitle: '90 דק׳ (זמניות)',
    category: 'עלות השחר',
    explanation:
        '''ד' מיל של 22.5 דק' בימות השיויון, שמינית מאורך היום שמהנץ לשקיעה
בלוח שבספר מעשה ניסים להר"נ כ'דורי קבע את זמן עה"ש 90 דקות בזמניות קודם הנץ, וכן הביא המנהג בכה"ח סי' פ"ט אות ד' ["קרוב לשמינית היום"] וכ"כ בספר וזרח השמש (דף ל' ע"ב ופ"ג ע"ב). וזה כשיטת הרבה ראשונים שהילוך מיל הוא 22.5 דקות, וד' מיל הם 90 דק'. אמנם דעת רוב הפוסקים וכן העיקר להלכה שהילוך מיל הוא 18 דק' וד' מיל הם 72 דק' לפני הנץ בימי השיוויון. ולכן נפקא מינה להשתמש בטור זה של 90 דק' רק לחומרא, כגון למהר לקרוא קריאת שמע של לילה ולהתפלל ערבית (אם לא אמרם קודם לכן) עד לזמן זה, ולספור ספירת העומר בברכה רק עד זמן זה, או להתחיל הצומות המתחילים ביום מזמן זה, וכן לחשב ממנו את אורך היום לענין זמני היום כסו"ז קריאת שמע ועוד. קבענו שיטה זו בזמניות, שמתחשבת לפי אורך היום ו-90 דק' הם שמינית מהיום השלם של 720 דק', וא"כ תמיד שמינית מאורך היום קודם הנץ החמה הוא עלות השחר, וכשיטת הזמניות כן היא דעת הפרי חדש בקונטרסו דבי שמשי, והעתיקוהו אחרונים רבים, מהם הגרע"י בהליכות עולם ח"א עמ' ר"נ, בכף החיים (בציון הנ"ל, ובסי' י"ח ס"ק י"ח) והגרב"צ באור לציון (ח"ב עמ' נ"ב), אלא שהם סוברים כשיטת 72 דק'. אלא ששיטת "זמניות" בעלות השחר וצאת הכוכבים קשה מאד להלכה, שהחוש מכחישה, שהרי בשמינית מאורך היום בחורף לפני הנץ יותר מואר בהרבה מ90 דק' לפני הנץ שבימות השיויון [וכן בשמינית מאורך היום בחורף אחרי השקיעה יש פחות חושך וכוכבים מאשר 90 דק' אחר השקיעה בימות השיוויון], וכבר ברמב"ם (בפירוש המשניות ברכות) ובגר"א (רס"א תנ"ט ויו"ד רס"ב) ובספר אילם לישר מקנדיא (ח"ה אות ס"ד) מבואר שיש ללכת לפי המעלות, ובמדינות הצפוניות זמנם מוקדם יותר, ועכ"פ בשו"ע כתוב עלה השחר והאיר המזרח וכן בראשונים לא הזכירו זמניות ולא כתבו שיטה איך לחשבו, ולפני שהיה שעונים עשו על פי ראיית העין שהיא מקבילה לשיטת המעלות, ולכן כשיטת המעלות יש לנהוג למעשה, ואכמ"ל.''',
    pairId: 'alosZmanis',
    pairLabel: '90 דק׳ (זמניות)',
    compute: (c) => c.cal.getAlos90Zmanis(),
  ),
  ZmanDefinition(
    id: 'alos120Zmanis',
    title: 'עלות השחר',
    subtitle: '120 דק׳ (זמניות)',
    category: 'עלות השחר',
    explanation:
        '''ה' מיל של 24 דק' בימות השיויון, שישית מאורך היום שמהנץ לשקיעה
בסוגיא דמסכת פסחים דף צ"ד מבואר שלדעת רבא ועולא עלות השחר הוא ה' מיל קודם הנץ החמה, ואיתותב עולא. ואם אדם מהלך ביום ל מיל, יוצא אורך המיל 24 דק' (24=720/30), ו-5 מיל 120 דק'. וברמב"ם מבואר שהילוך מיל הוא 24 דק', וכ"ה בשו"ע הרב. והנה שיטה זו לא נפסקה להלכה ולכן אין לחוש לה לדינא גם לא לחומרא. והבאנוה למעוניינים להחמיר על פיה כמה הנהגות והם: למהר לקרוא קריאת שמע של לילה ולהתפלל ערבית (אם לא אמרם קודם לכן) עד לזמן זה, ולהזדרז לספור בברכה ספירת העומר עד זמן זה, או להתחיל הצומות המתחילים ביום מזמן זה. קבענו שיטה זו בזמניות, שמתחשבת לפי אורך היום ו-120 דק' הם ששית מהיום השלם של 720 דק', וא"כ לפי זה ששית מאורך היום קודם הנץ החמה הוא עלות השחר.''',
    compute: (c) => c.cal.getAlos120Zmanis(),
  ),

  // ── זמן ציצית ותפילין (משיכיר) ──────────────────────────────────────────
  ZmanDefinition(
    id: 'misheyakir10point2',
    title: 'זמן ציצית ותפילין',
    category: 'ציצית ותפילין',
    explanation:
        '''לחומרא, כשהשמש 10.5 מעלות תחת האופק, כשלושת רבעי שעה קודם הנץ בא"י
בשו"ע או"ח (סי' י"ח ס"ג וסי' ל' ס"א וסי' נ"ח ס"א) נפסק שמזמן שיכול אדם לראות את חבירו (הרגיל עמו קצת) בריחוק ארבע אמות ויכירנו, או שיכול להבחין בין תכלת ללבן, מותר בהנחת תפילין, עטיפת טלית בברכה, ובקריאת שמע של שחרית. אין לנו מקור למדידת זמן זה בדקות או בשעות, כך שקביעתו המדוייקת תלויה בנסיון ובמציאות הנראית לעינינו בלבד, או במנהגים הקבועים. בערים מודיעין עילית זכרון יעקב ועוד קבענו זמן זה לפי 10.5 מעלות מתחת לאופק, והוא מאוחר בכחמש דק' לזמן של 11.5 מעלות. זמן זה נקבע ע"פ בקשת הרבנים בערים אלו, שסוברים שנבדק ונמצא שרק מזמן זה ניתן להבחין בין תכלת ללבן או להכיר חבירו.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getMisheyakir10Point2Degrees(),
  ),
  ZmanDefinition(
    id: 'misheyakir11',
    title: 'זמן ציצית ותפילין',
    subtitle: '11°',
    category: 'ציצית ותפילין',
    explanation: '''כשהשמש 11 מעלות תחת האופק, וכן נהוג בצרפת ושטראסבורג
בשו"ע או"ח (סי' י"ח ס"ג וסי' ל' ס"א וסי' נ"ח ס"א) נפסק שמזמן שיכול אדם לראות את חבירו (הרגיל עמו קצת) בריחוק ארבע אמות ויכירנו, או שיכול להבחין בין תכלת ללבן, מותר בהנחת תפילין, עטיפת טלית בברכה, ובקריאת שמע של שחרית. אין לנו מקור למדידת זמן זה בדקות או בשעות, כך שקביעתו המדוייקת תלויה בנסיון ובמציאות הנראית לעינינו בלבד, או במנהגים הקבועים. בצרפת ובשטרסבורג נהגו 11 מעלות קודם הנץ, וכן כתב בספר זמנים בהלכה עמ' רי"ב בשם הרי"א ענקין כמנהג ניו יורק.''',
    compute: (c) => c.cal.getMisheyakir11Degrees(),
  ),
  ZmanDefinition(
    id: 'misheyakir11point5',
    title: 'זמן ציצית ותפילין',
    subtitle: '11.5°',
    category: 'ציצית ותפילין',
    explanation: '''כשהשמש 11.5 מעלות תחת האופק, כשעה קודם הנץ בא"י
בשו"ע או"ח (סי' י"ח ס"ג וסי' ל' ס"א וסי' נ"ח ס"א) נפסק שמזמן שיכול אדם לראות את חבירו (הרגיל עמו קצת) בריחוק ארבע אמות ויכירנו, או שיכול להבחין בין תכלת ללבן, מותר בהנחת תפילין, עטיפת טלית בברכה, ובקריאת שמע של שחרית. אין לנו מקור למדידת זמן זה בדקות או בשעות, כך שקביעתו המדוייקת תלויה בנסיון ובמציאות הנראית לעינינו בלבד, או במנהגים הקבועים. והנה בספר כף החיים למו"ז הגאון ז"ל (סי' י"ח אות י"ח) וכן בספר א"י להרימ"ט כתבו שמנהג אנשי ירושלים לשער זמן זה בכשעה קודם הנץ במשך כל ימות השנה, וקבענו כאן שהשמש 11.5 מעלות מתחת לאופק, ע"פ ספר זמני ההלכה למעשה, הוא בימות השיוויון 54 דק' קודם הנץ המישורי, והזמן נע בקיץ ובחורף בין 50 ל-60 דק'. זמן זה תואם לנסיונות ולמציאות שבו אפשר להכיר את חבירו וכמו כן להבחין בין תכלת ללבן, הגרא"י זילבר בלוח שב"יתד נאמן" כותב בזה זמן לשעת הדחק שהוא מוקדם בכ-8-7 דק' מהזמן שבלוח הזה, וזמן נוסף לכתחילה שהוא מאוחר בכ-8-7 דק' מהלוח הזה. אמנם יש פוסקים החוששים ומחמירים לאחר הזמן עוד מעט, אבל להקל ביותר מזה אין שום מקור, [ועיין בה"ל נ"ח א' ד"ה כמו שיעור, שכתב שלא כפמ"ג שהיקל בשיעור 6 דקות אחרי עה"ש (ובקיץ הוא מוקדם מהזמן שאצלנו ברבע שעה בערך), ועוד הרבה אחרונים סוברים שלא כהפמ"ג, ואפי' הפמ"ג עצמו כתב שם שצ"ע בדברים, ולא נכון עושים בלוח אור החיים שקבעו כשיטה זו לקולא].''',
    compute: (c) => c.cal.getMisheyakir11Point5Degrees(),
  ),

  // ── זריחה ──────────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'sunrise',
    title: 'הנץ הנראה',
    category: 'זריחה',
    explanation:
        '''הנץ החמה כפי שנראה מגובה המקום בניכוי X מטר, שאלו הסתרים שיש לנכותם כדי לקבל את האופק האמיתי ולקבוע על פיו את הנץ הנראה.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getSunrise(),
  ),
  ZmanDefinition(
    id: 'seaLevelSunrise',
    title: 'נץ החמה המישורי',
    category: 'זריחה',
    explanation: '''כשהמקום והאופק בגובה אחד
הנץ החמה כאשר המקום והאופק בגובה אחד, ובו תחילת היום, הן לענין השעות הזמניות והן לענין תפילה לרבים הסוברים שיש ללכת אחר הנץ המישורי. במקומות בהם המקום גבוה מהאופק ולכן הנץ נראה לעיניים לפני הזמן המישורי לכולי עלמא הולכים אחר הנץ הנראה, כגון ירושלים. ובמקומות בהם האופק גבוה מהמקום, בגלל הסתרי הרים באופק כמו ערי השפילה ומישור החוף בארץ ישראל, נחלקו החכמים אם יש לנכות ההרים ולעשות כהנץ המישורי, או להמתין עד שתראה החמה לעיניים ולהתפלל בהנץ הנראה. עיקר ההכרעה בזה [כסברת הגר"ש דביליצקי זצ"ל] שאפשר להמתין לראיית גלגל החמה, ובתנאי שלא מתעכבת יותר מ-5 דק' אחר הנץ המישורי, שעד אז עדיין אדומה היא ונקראת דמדומי חמה, אם ההסתרים גורמים לה לאיחור יותר מ-5 דק' יש להתפלל בהנץ המישורי או בהנץ בניכוי חלק מההרים המסתירים (בעיקר ההרים הקרובים שגורמים לאיחור הגדול שנחשבים כמו חומה בעלמא). השלכות הנץ המישורי להלכה: לתפילה בהץ החמה כדלעיל, ולכל הדינים שזמנם ביום דראוי לכתחילה שלא לעשותם קודם הנץ (מגילה כ'), כהלל, לולב, שופר, מגילה וכדו'. לזמן ק"ש, לתחילת חשבון שעות זמניות לדעת הגר"א, לחישוב זמן עה"ש למפרע, ולסוף זמן ק"ש של לילה לאנוס (או"ח רל"ה ד').''',
    defaultEnabled: true,
    compute: (c) => c.cal.getSeaLevelSunrise(),
  ),

  // ── סוף זמן קריאת שמע ──────────────────────────────────────────────────
  ZmanDefinition(
    id: 'sofZmanShmaMGA90Degrees',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 90 דק׳ (מעלות)',
    category: 'קריאת שמע',
    explanation: '''ג' שעות זמניות מעה"ש לצאה"כ 90 דק' במעלות
סוף זמן קריאת שמע הוא בסוף שעה שלישית מהיום, כדברי רבי יהושע עד שלש שעות שכן דרך בני מלכים (וכל ישראל בני מלכים הם) לעמוד בשלש שעות, וכן נפסק בשו"ע (או"ח סי' נ"ח ס"א) שסוף זמן ק"ש הוא עם סיום ג' שעות זמניות מתחילת היום. והנה לדעת רוב הראשונים יש למנות שעות אלו מעה"ש עד צאת הכוכבים, וכתב המג"א (נ"ח סק"א) "נ"ל דהכא לכו"ע מנינן מעה"ש" עיי"ש, וחלק עליו הגר"א (תנ"ט סק"ה), ולשיטתו מונים השעות מהנץ לשקיעה. הזמן לפי 90 דק' במעלות הוא כהכרעת הרימ"ט בלוח א"י (וכתב שהסכימו על ידו גאוני ירושלים כהר"ש סלנט ורי"ח זוננפלד ועוד) והוא נקבע בהרבה מהלוחות הנפוצים כסוף זמן ק"ש של המג"א, כגון בלוח א"י להרימ"ט וכן בלוחות הגדולים (של הרב לוק) בבתי הכנסת ועוד. דסיום הג' שעות הוא מעה"ש המוקדם להנץ ב-90 דק' במעלות, והיינו דהיום מתחיל 90 דק' קודם הנץ ומסתיים 90 דק' אחרי השקיעה לצורך חישובי השעות [הגם דלענין צאה"כ נוהגים אנו כהגאונים, ושעם הראות הכוכבים הוי לילה גמור, כתב ע"ז הרימ"ט "שאין זו צאת ג' כוכבים הנחשבת לנו לערב לדין לילה, אלא זהו צאת כל הכוכבים, זמן שכלה עמוד אחרון של האור ויצאו כל כוכבי לילה, כי עובי הרקיע אחת היא בערבית כמו בשחרית, וכשיעור שיש מעלות השחר עד הנץ כך יש מהשקיעה עד כלות העמוד האחרון"].''',
    defaultEnabled: true,
    pairId: 'shmaMgaGra',
    pairLabel: 'מג"א',
    compute: (c) => c.cal.getSofZmanShmaMGA19Point8Degrees(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaGRA',
    title: 'סוף זמן ק"ש',
    subtitle: 'גר"א',
    category: 'קריאת שמע',
    explanation: '''3 שעות זמניות מהנץ לשקיעה''',
    defaultEnabled: true,
    pairId: 'shmaMgaGra',
    pairLabel: 'גר"א',
    compute: (c) => c.cal.getSofZmanShmaGRA(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaMGA72Degrees',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 72 דק׳ (מעלות)',
    category: 'קריאת שמע',
    explanation: '''3 ג' שעות זמניות מעה"ש לצאה"כ 72 דק'
סוף זמן קריאת שמע הוא בסוף שעה שלישית מהיום, כדברי רבי יהושע עד שלש שעות שכן דרך בני מלכים (וכל ישראל בני מלכים הם) לעמו בשלש שעות, וכן נפסק בשו"ע (או"ח סי' נ"ח ס"א) שסוף זמן ק"ש הוא עם סיום ג' שעות זמניות מתחילת היום. והנה לדעת רוב הראשונים יש למנות שעות אלו מעה"ש עד צאת הכוכבים, וכתב המג"א (נ"ח סק"א) "נ"ל דהכא לכו"ע מנינן מעה"ש" עיי"ש, וחלק עליו הגר"א (תנ"ט סק"ה), ולשיטתו מונים השעות מהנץ לשקיעה. הזמן לפי עלות השחר 72 דק' במעלות הוא על פי דעת הרבה פוסקים וכ"ד השו"ע ורמ"א, שעלות השחר הוא 72 דקות קודם הנץ, ומסתיים היום 72 דק' אחר השקיעה (זמן ר"ת 72 במעלות), לצורך חישובי השעות, [הגם דלענין צאה"כ נוהגים אנו כהגאונים, ושעם הראות הכוכבים הוי לילה גמור, כתב ע"ז הרימ"ט "שאין זו צאת ג' כוכבים הנחשבת לנו לערב לדין לילה, אלא זהו צאת כל הכוכבים, זמן שכלה עמוד אחרון של האור ויצאו כל כוכבי לילה, כי עובי הרקיע אחת היא בערבית כמו בשחרית, וכשיעור שיש מעלות השחר עד הנץ כך יש מהשקיעה עד כלות העמוד האחרון"]. הזמן לשיטה של 72 הוא יותר מאוחר מלשיטה של 90, דכיון שהיום מתחיל יותר מאוחר הג' שעות הם יותר מאוחרים, והם בערך אחרי כעשר דקות מסוף זמן ק"ש של 90 דק'. ומאחר דהעיקר לדינא כדעה דעה"ש 72 דק' קודם הנץ, ראוי לדעת שהנוהג כמג"א אם איחר הזמן שלפי עה"ש של 90 המופיע בלוחות, צריך לקרוא מיד, להספיק הזמן שעל פי דעה זו שעה"ש 72 דק' קודם הנץ, וכן, אם קם ממיטתו ברגעים האחרונים וחושב שהפסיד הזמן וממילא חושב להשתהות עד סו"ז ק"ש להגר"א, לא ימתין אלא יקרא מיד כי עדיין לא עבר זמן ק"ש של המג"א העיקרי. אולם אין ראוי להתאחר בזה לכתחילה שכבר הביא המשנ"ב (סימן נ"ח סק"ד) משנות אליהו בשם הירושלמי דלכתחילה אסור להתאחר עד סוף הזמן.''',
    compute: (c) => c.cal.getSofZmanShmaMGA16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaMGA72Shavos',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 72 דק׳ (שוות)',
    category: 'קריאת שמע',
    explanation: '''ג' שעות זמניות, מעה"ש לצאה"כ 72 דק' שוות''',
    compute: (c) => c.cal.getSofZmanShmaMGA72Minutes(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaMGA72Zmanis',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 72 דק׳ (זמניות)',
    category: 'קריאת שמע',
    explanation: '''ג' שעות זמניות, מעה"ש לצאה"כ 72 דק' זמניות''',
    compute: (c) => c.cal.getSofZmanShmaMGA72MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaMGA90Shavos',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 90 דק׳ (שוות)',
    category: 'קריאת שמע',
    explanation: '''ג' שעות זמניות, מעה"ש לצאה"כ 90 דק' שוות''',
    compute: (c) => c.cal.getSofZmanShmaMGA90Minutes(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaMGA90Zmanis',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 90 דק׳ (זמניות)',
    category: 'קריאת שמע',
    explanation: '''ג' שעות זמניות, מעה"ש לצאה"כ 90 דק' זמניות''',
    compute: (c) => c.cal.getSofZmanShmaMGA90MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'sofZmanShmaMGA120Shavos',
    title: 'סוף זמן ק"ש',
    subtitle: 'מג"א 120 דק׳ (שוות)',
    category: 'קריאת שמע',
    explanation: '''ג' שעות זמניות, מעה"ש לצאה"כ 120 דק' שוות''',
    compute: (c) => c.cal.getSofZmanShmaMGA120Minutes(),
  ),

  // ── סוף זמן תפילה ──────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'sofZmanTfilaMGA90Degrees',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 90 דק׳ (מעלות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות, מעה"ש לצאה"כ 90 במעלות''',
    defaultEnabled: true,
    pairId: 'tfilaMgaGra',
    pairLabel: 'מג"א',
    compute: (c) => c.cal.getSofZmanTfilaMGA19Point8Degrees(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaGRA',
    title: 'סוף זמן תפילה',
    subtitle: 'גר"א',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות מהנץ לשקיעה''',
    defaultEnabled: true,
    pairId: 'tfilaMgaGra',
    pairLabel: 'גר"א',
    compute: (c) => c.cal.getSofZmanTfilaGRA(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaMGA72Degrees',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 72 דק׳ (מעלות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות מעה"ש לצאה"כ 72 בזמניות''',
    compute: (c) => c.cal.getSofZmanTfilaMGA16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaMGA72Shavos',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 72 דק׳ (שוות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות, מעה"ש לצאה"כ 72 דק' שוות''',
    compute: (c) => c.cal.getSofZmanTfilaMGA72Minutes(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaMGA72Zmanis',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 72 דק׳ (זמניות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות, מעה"ש לצאה"כ 72 דק' זמניות''',
    compute: (c) => c.cal.getSofZmanTfilaMGA72MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaMGA90Shavos',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 90 דק׳ (שוות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות, מעה"ש לצאה"כ 90 דק' שוות''',
    compute: (c) => c.cal.getSofZmanTfilaMGA90Minutes(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaMGA90Zmanis',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 90 דק׳ (זמניות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות, מעה"ש לצאה"כ 90 דק' זמניות''',
    compute: (c) => c.cal.getSofZmanTfilaMGA90MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'sofZmanTfilaMGA120Shavos',
    title: 'סוף זמן תפילה',
    subtitle: 'מג"א 120 דק׳ (שוות)',
    category: 'תפילה',
    explanation: '''ד' שעות זמניות, מעה"ש לצאה"כ 120 דק' שוות''',
    compute: (c) => c.cal.getSofZmanTfilaMGA120Minutes(),
  ),

  // ── חצות ──────────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'chatzos',
    title: 'חצות היום',
    category: 'חצות',
    explanation:
        '''אמצע הזמן שבין הנץ לשקיעה המישוריים. וזה הזמן שהחמה באמצע השמים ובשיא גובהה.
חצות היום ולילה - אמצע הזמן שבין הנץ לשקיעה המישוריים הוא חצות היום, וי"ב שעות אחריו הוא חצות הלילה. וזה הזמן שהחמה באמצע השמים ובשיא גובהה.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getChatzos(),
  ),
  ZmanDefinition(
    id: 'chatzosFixedLocal',
    title: 'חצות מקומי קבוע',
    category: 'חצות',
    explanation: '''חצות היום הקבוע לפי קו האורך הגיאוגרפי (ללא תלות בזריחה '
        'ובשקיעה).''',
    compute: (c) => c.cal.getFixedLocalChatzos(),
  ),
  ZmanDefinition(
    id: 'chatzosLayla',
    title: 'חצות לילה',
    category: 'חצות',
    explanation: '''חצות לילה אסטרונומי — אמצע בין שקיעת היום לזריחת המחרת.''',
    defaultEnabled: true,
    compute: (c) => calculateSolarMidnight(c.cal, c.city, c.date),
  ),

  // ── מנחה ───────────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'minchaGedolaGreater30',
    title: 'מנחה גדולה',
    subtitle: 'המאוחר',
    category: 'מנחה',
    explanation: '''המאוחר מבין חצי שעה זמנית אחרי חצות לבין 30 דקות קבועות '
        'אחרי חצות.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getMinchaGedolaGreaterThan30(),
  ),
  ZmanDefinition(
    id: 'minchaGedolaGRA',
    title: 'מנחה גדולה',
    subtitle: 'גר"א',
    category: 'מנחה',
    explanation: '''6.5 שעות זמניות מהזריחה (חצי שעה זמנית אחרי חצות).''',
    compute: (c) => c.cal.getMinchaGedola(),
  ),
  ZmanDefinition(
    id: 'minchaGedola30',
    title: 'מנחה גדולה',
    subtitle: '30 דק׳ שוות',
    category: 'מנחה',
    explanation: '''30 דקות קבועות אחרי חצות היום.''',
    compute: (c) => c.cal.getMinchaGedola30Minutes(),
  ),
  ZmanDefinition(
    id: 'minchaGedola16point1',
    title: 'מנחה גדולה',
    subtitle: '16.1°',
    category: 'מנחה',
    explanation: '''מנחה גדולה כשהיום מחושב מ-16.1° עד 16.1°.''',
    compute: (c) => c.cal.getMinchaGedola16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'minchaKetanaGRA',
    title: 'מנחה קטנה',
    subtitle: 'גר"א',
    category: 'מנחה',
    explanation: '''9.5 שעות זמניות מהנץ לשקיעה''',
    defaultEnabled: true,
    compute: (c) => c.cal.getMinchaKetana(),
  ),
  ZmanDefinition(
    id: 'minchaKetana16point1',
    title: 'מנחה קטנה',
    subtitle: '90 דק׳',
    category: 'מנחה',
    explanation: '''9.5 שעות זמניות מעה"ש לצאה"כ 90 דק' במעלות''',
    compute: (c) => c.cal.getMinchaKetana16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'minchaKetana72',
    title: 'מנחה קטנה',
    subtitle: '72 דק׳',
    category: 'מנחה',
    explanation: '''9.5 שעות זמניות מעה"ש לצאה"כ 72 דק' שוות''',
    compute: (c) => c.cal.getMinchaKetana72Minutes(),
  ),

  // ── פלג המנחה ──────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'plagGRA',
    title: 'פלג המנחה',
    subtitle: 'גר"א',
    category: 'פלג המנחה',
    explanation: '''10.75 שעות זמניות מהנץ לשקיעה''',
    defaultEnabled: true,
    compute: (c) => c.cal.getPlagHamincha(),
  ),
  ZmanDefinition(
    id: 'plag72Shavos',
    title: 'פלג המנחה',
    subtitle: '72 דק׳ (שוות)',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מ-72 דקות קבועות לפני הזריחה עד 72 אחרי '
        'השקיעה.''',
    compute: (c) => c.cal.getPlagHamincha72Minutes(),
  ),
  ZmanDefinition(
    id: 'plag90Shavos',
    title: 'פלג המנחה',
    subtitle: '90 דק׳ (שוות)',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מ-90 דקות קבועות לפני הזריחה עד 90 אחרי '
        'השקיעה.''',
    compute: (c) => c.cal.getPlagHamincha90Minutes(),
  ),
  ZmanDefinition(
    id: 'plag120Shavos',
    title: 'פלג המנחה',
    subtitle: '120 דק׳ (שוות)',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מ-120 דקות קבועות לפני הזריחה עד 120 אחרי '
        'השקיעה.''',
    compute: (c) => c.cal.getPlagHamincha120Minutes(),
  ),
  ZmanDefinition(
    id: 'plag72Zmanis',
    title: 'פלג המנחה',
    subtitle: '72 דק׳ (זמניות)',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מ-72 דקות זמניות לפני הזריחה עד 72 אחרי '
        'השקיעה.''',
    compute: (c) => c.cal.getPlagHamincha72MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'plag90Zmanis',
    title: 'פלג המנחה',
    subtitle: '90 דק׳ (זמניות)',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מ-90 דקות זמניות לפני הזריחה עד 90 אחרי '
        'השקיעה.''',
    compute: (c) => c.cal.getPlagHamincha90MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'plag120Zmanis',
    title: 'פלג המנחה',
    subtitle: '120 דק׳ (זמניות)',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מ-120 דקות זמניות לפני הזריחה עד 120 אחרי '
        'השקיעה.''',
    compute: (c) => c.cal.getPlagHamincha120MinutesZmanis(),
  ),
  ZmanDefinition(
    id: 'plag72Degrees',
    title: 'פלג המנחה',
    subtitle: '72 דק׳ (מעלות)',
    category: 'פלג המנחה',
    explanation: '''10.75 שעות זמניות מעה"ש לצאה"כ 72 דק׳ במעלות''',
    compute: (c) => c.cal.getPlagHamincha16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'plag90Degrees',
    title: 'פלג המנחה',
    subtitle: '90 דק׳ (מעלות)',
    category: 'פלג המנחה',
    explanation: '''10.75 שעות זמניות מעה"ש לצאה"כ 90 דק׳ במעלות''',
    compute: (c) => c.cal.getPlagHamincha19Point8Degrees(),
  ),
  ZmanDefinition(
    id: 'plag120Degrees',
    title: 'פלג המנחה',
    subtitle: '120 דק׳ (מעלות)',
    category: 'פלג המנחה',
    explanation: '''10.75 שעות זמניות מעה"ש לצאה"כ 120 דק׳ במעלות''',
    compute: (c) => c.cal.getPlagHamincha26Degrees(),
  ),
  ZmanDefinition(
    id: 'plagAlosToSunset',
    title: 'פלג המנחה',
    subtitle: 'מעלוה"ש עד שקיעה',
    category: 'פלג המנחה',
    explanation: '''פלג המנחה כשהיום מעלות השחר (72 דק׳) עד השקיעה.''',
    compute: (c) => c.cal.getPlagAlosToSunset(),
  ),
  ZmanDefinition(
    id: 'plagAlos16ToGeonim',
    title: 'פלג המנחה',
    subtitle: 'מ-16.1° עד גאונים 7.083°',
    category: 'פלג המנחה',
    explanation:
        '''פלג המנחה כשהיום מעלות 16.1° עד צאת הכוכבים לגאונים 7.083°.''',
    compute: (c) => c.cal.getPlagAlos16Point1ToTzaisGeonim7Point083Degrees(),
  ),

  // ── שקיעה ──────────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'sunset',
    title: 'שקיעה',
    category: 'שקיעה',
    explanation: '''השקיעה הנראית ממקום המתפלל, כולל תיקון לגובה האופק.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getSunset(),
  ),
  ZmanDefinition(
    id: 'seaLevelSunset',
    title: 'שקיעה מישורית',
    category: 'שקיעה',
    explanation: '''השקיעה ברום פני הים, ללא תיקון לגובה.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getSeaLevelSunset(),
  ),

  // ── בין השמשות (ברירת מחדל: כלום) ──────────────────────────────────────
  ZmanDefinition(
    id: 'binRT13point24',
    title: 'בין השמשות',
    subtitle: 'ר"ת 13.24°',
    category: 'בין השמשות',
    explanation: '''תחילת בין השמשות לרבנו תם — 13.24° מתחת לאופק.''',
    compute: (c) => c.cal.getBainHasmashosRT13Point24Degrees(),
  ),
  ZmanDefinition(
    id: 'binRT58point5',
    title: 'בין השמשות',
    subtitle: 'ר"ת 58.5 דק׳',
    category: 'בין השמשות',
    explanation: '''תחילת בין השמשות לרבנו תם — 58.5 דקות אחרי השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosRT58Point5Minutes(),
  ),
  ZmanDefinition(
    id: 'binRT13point5',
    title: 'בין השמשות',
    subtitle: 'ר"ת 13.5 דק׳',
    category: 'בין השמשות',
    explanation: '''תחילת בין השמשות לרבנו תם — 13.5 דקות לפני צאת הגאונים '
        '7.083°.''',
    compute: (c) =>
        c.cal.getBainHasmashosRT13Point5MinutesBefore7Point083Degrees(),
  ),
  ZmanDefinition(
    id: 'binYereim18',
    title: 'בין השמשות',
    subtitle: 'יראים 18 דק׳',
    category: 'בין השמשות',
    explanation: '''בין השמשות ליראים — 18 דקות לפני השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosYereim18Minutes(),
  ),
  ZmanDefinition(
    id: 'binYereim16point875',
    title: 'בין השמשות',
    subtitle: 'יראים 16.875 דק׳',
    category: 'בין השמשות',
    explanation: '''בין השמשות ליראים — 16.875 דקות לפני השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosYereim16Point875Minutes(),
  ),
  ZmanDefinition(
    id: 'binYereim13point5',
    title: 'בין השמשות',
    subtitle: 'יראים 13.5 דק׳',
    category: 'בין השמשות',
    explanation: '''בין השמשות ליראים — 13.5 דקות לפני השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosYereim13Point5Minutes(),
  ),
  ZmanDefinition(
    id: 'binYereim3point5',
    title: 'בין השמשות',
    subtitle: 'יראים 3.5°',
    category: 'בין השמשות',
    explanation: '''בין השמשות ליראים — 3.5° מתחת לאופק לפני השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosYereim3Point5Degrees(),
  ),
  ZmanDefinition(
    id: 'binYereim2point8',
    title: 'בין השמשות',
    subtitle: 'יראים 2.8°',
    category: 'בין השמשות',
    explanation: '''בין השמשות ליראים — 2.8° מתחת לאופק לפני השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosYereim2Point8Degrees(),
  ),
  ZmanDefinition(
    id: 'binYereim2point1',
    title: 'בין השמשות',
    subtitle: 'יראים 2.1°',
    category: 'בין השמשות',
    explanation: '''בין השמשות ליראים — 2.1° מתחת לאופק לפני השקיעה.''',
    compute: (c) => c.cal.getBainHasmashosYereim2Point1Degrees(),
  ),

  // ── צאת הכוכבים ────────────────────────────────────────────────────────
  ZmanDefinition(
    id: 'tzeitTikochinsky',
    title: 'צאת הכוכבים',
    subtitle: 'טיקוצ׳ינסקי',
    category: 'צאת הכוכבים',
    explanation: '''צאת הכוכבים לפי הרב טוקוצ׳ינסקי — 13.5 דקות אחרי השקיעה.''',
    defaultEnabled: true,
    compute: (c) =>
        c.cal.getSunset()?.add(const Duration(minutes: 13, seconds: 30)),
  ),
  ZmanDefinition(
    id: 'tzeitItimLeVina',
    title: 'צאת הכוכבים',
    subtitle: 'עיתים לבינה',
    category: 'צאת הכוכבים',
    explanation: '''צאת הכוכבים לפי לוח עיתים לבינה — 18 דקות אחרי השקיעה.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 18)),
  ),
  ZmanDefinition(
    id: 'tzeitGeonim3point65',
    title: 'צאת הכוכבים',
    subtitle: 'גאונים 3.65°',
    category: 'צאת הכוכבים',
    explanation: '''צאת הכוכבים לגאונים — 3.65° מתחת לאופק.''',
    compute: (c) => c.cal.getTzaisGeonim3Point65Degrees(),
  ),
  ZmanDefinition(
    id: 'tzeitGeonim7point083',
    title: 'צאת הכוכבים',
    subtitle: 'גאונים 7.083°',
    category: 'צאת הכוכבים',
    explanation: '''צאת הכוכבים לגאונים — 7.083° מתחת לאופק (≈ ר׳ יונה).''',
    compute: (c) => c.cal.getTzaisGeonim7Point083Degrees(),
  ),
  ZmanDefinition(
    id: 'tzeitGeonim8point5',
    title: 'צאת הכוכבים',
    subtitle: 'גאונים 8.5°',
    category: 'צאת הכוכבים',
    explanation: '''צאת הכוכבים לגאונים — 8.5° מתחת לאופק (השיטה הנפוצה).''',
    compute: (c) => c.cal.getTzaisGeonim8Point5Degrees(),
  ),
  ZmanDefinition(
    id: 'tzeitChazonIsh',
    title: 'צאת הכוכבים',
    subtitle: 'חזו"א (9.3°)',
    category: 'צאת הכוכבים',
    explanation: '''צאת הכוכבים לפי חזון איש — 9.3° מתחת לאופק (כך מחשב לוח '
        'עיתים לבינה, 9.28°).''',
    compute: (c) => c.cal.getTzaisGeonim9Point3Degrees(),
  ),

  // ── צאת הכוכבים לרבנו תם ────────────────────────────────────────────────
  ZmanDefinition(
    id: 'rt72Shavos',
    title: 'רבנו תם',
    subtitle: '72 דק׳ (שוות)',
    category: 'רבנו תם',
    explanation: '''רבנו תם — 72 דקות קבועות אחרי השקיעה.''',
    defaultEnabled: true,
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 72)),
  ),
  ZmanDefinition(
    id: 'rt72Zmanis',
    title: 'רבנו תם',
    subtitle: '72 דק׳ (זמניות)',
    category: 'רבנו תם',
    explanation:
        '''ד' מיל של 18 דק' בימות השיויון, עשירית מאורך היום שמהנץ לשקיעה''',
    compute: (c) => c.cal.getTzais72Zmanis(),
  ),
  ZmanDefinition(
    id: 'rt72Degrees',
    title: 'רבנו תם',
    subtitle: '72 דק׳ (מעלות)',
    category: 'רבנו תם',
    explanation: '''16 מעלות, שהם ד' מיל אחר השקיעה, לפי מיל של 18 דק\'''',
    compute: (c) => c.cal.getTzais16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'rt90Shavos',
    title: 'רבנו תם',
    subtitle: '90 דק׳ (שוות)',
    category: 'רבנו תם',
    explanation: '''רבנו תם — 90 דקות קבועות אחרי השקיעה.''',
    compute: (c) => c.cal.getTzais90(),
  ),
  ZmanDefinition(
    id: 'rt90Zmanis',
    title: 'רבנו תם',
    subtitle: '90 דק׳ (זמניות)',
    category: 'רבנו תם',
    explanation:
        '''ד' מיל של 22.5 דק' בימות השיויון, שמינית מאורך היום שמהנץ לשקיעה''',
    compute: (c) => c.cal.getTzais90Zmanis(),
  ),
  ZmanDefinition(
    id: 'rt90Degrees',
    title: 'רבנו תם',
    subtitle: '90 דק׳ (מעלות)',
    category: 'רבנו תם',
    explanation: '''19.75 מעלות, שהם ד' מיל אחר השקיעה, לפי מיל של 22.5 דק\'''',
    compute: (c) => c.cal.getTzais19Point8Degrees(),
  ),
  ZmanDefinition(
    id: 'rt120Shavos',
    title: 'רבנו תם',
    subtitle: '120 דק׳ (שוות)',
    category: 'רבנו תם',
    explanation: '''רבנו תם — 120 דקות קבועות אחרי השקיעה.''',
    compute: (c) => c.cal.getTzais120(),
  ),
  ZmanDefinition(
    id: 'rt120Zmanis',
    title: 'רבנו תם',
    subtitle: '120 דק׳ (זמניות)',
    category: 'רבנו תם',
    explanation:
        '''ה' מיל של 24 דק' בימות השיויון, שמינית מאורך היום שמהנץ לשקיעה''',
    compute: (c) => c.cal.getTzais120Zmanis(),
  ),
  ZmanDefinition(
    id: 'rt120Degrees',
    title: 'רבנו תם',
    subtitle: '120 דק׳ (מעלות)',
    category: 'רבנו תם',
    explanation: '''כ-26 מעלות, שהם ה מיל אחר השקיעה, לפי מיל של 24 דק\'''',
    compute: (c) => c.cal.getTzais26Degrees(),
  ),

  // ── הדלקת נרות ומוצאי שבת/חג ─────────────────────────────────────────────
  ZmanDefinition(
    id: 'candleLighting',
    title: 'הדלקת נרות',
    category: 'שבת וחג',
    explanation:
        '''זמן הדלקת נרות — מספר הדקות לפני השקיעה משתנה לפי מנהג העיר; ברירת המחדל היא 30 דקות.''',
    isRelevant: _isErevShabbosOrYomTov,
    isHolidaySpecial: true,
    defaultEnabled: true,
    compute: (c) => calculateCandleLightingTime(c.cal, c.city),
  ),
  ZmanDefinition(
    id: 'motzeiShabbos',
    title: 'מוצאי שבת',
    subtitle: 'רגיל',
    category: 'שבת וחג',
    explanation: '''צאת השבת — 34 דקות אחרי השקיעה.''',
    isRelevant: _isMotzeiShabbos,
    isHolidaySpecial: true,
    defaultEnabled: true,
    pairId: 'motzeiSh',
    pairLabel: 'רגיל',
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 34)),
  ),
  ZmanDefinition(
    id: 'motzeiShabbosChazonIsh',
    title: 'מוצאי שבת',
    subtitle: 'חזו"א',
    category: 'שבת וחג',
    explanation: '''צאת השבת לחזון איש — 38 דקות אחרי השקיעה.''',
    isRelevant: _isMotzeiShabbos,
    isHolidaySpecial: true,
    defaultEnabled: true,
    pairId: 'motzeiSh',
    pairLabel: 'חזו"א',
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 38)),
  ),
  ZmanDefinition(
    id: 'motzeiYomTov',
    title: 'מוצאי יום טוב',
    subtitle: 'רגיל',
    category: 'שבת וחג',
    explanation: '''צאת יום טוב — 34 דקות אחרי השקיעה.''',
    isRelevant: _isMotzeiYomTov,
    isHolidaySpecial: true,
    defaultEnabled: true,
    pairId: 'motzeiYT',
    pairLabel: 'רגיל',
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 34)),
  ),
  ZmanDefinition(
    id: 'motzeiYomTovChazonIsh',
    title: 'מוצאי יום טוב',
    subtitle: 'חזו"א',
    category: 'שבת וחג',
    explanation: '''צאת יום טוב לחזון איש — 38 דקות אחרי השקיעה.''',
    isRelevant: _isMotzeiYomTov,
    isHolidaySpecial: true,
    defaultEnabled: true,
    pairId: 'motzeiYT',
    pairLabel: 'חזו"א',
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 38)),
  ),

  // ── ערב פסח: אכילת וביעור חמץ ────────────────────────────────────────────
  ZmanDefinition(
    id: 'achilasChametzMGADegrees',
    title: 'סוף זמן אכילת חמץ',
    subtitle: 'מג"א (מעלות)',
    category: 'ערב פסח',
    explanation: '''סוף זמן אכילת חמץ — מג"א, 16.1° (≈72 דק׳).''',
    isRelevant: _isErevPesach,
    defaultEnabled: true,
    pairId: 'achilasChametz',
    pairLabel: 'מג"א',
    compute: (c) => c.cal.getSofZmanAchilasChametzMGA16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'achilasChametzGRA',
    title: 'סוף זמן אכילת חמץ',
    subtitle: 'גר"א',
    category: 'ערב פסח',
    explanation: '''סוף זמן אכילת חמץ — גר"א (= סוף זמן תפילה גר"א).''',
    isRelevant: _isErevPesach,
    defaultEnabled: true,
    pairId: 'achilasChametz',
    pairLabel: 'גר"א',
    compute: (c) => c.cal.getSofZmanAchilasChametzGRA(),
  ),
  ZmanDefinition(
    id: 'achilasChametzMGAShavos',
    title: 'סוף זמן אכילת חמץ',
    subtitle: 'מג"א (שוות)',
    category: 'ערב פסח',
    explanation: '''סוף זמן אכילת חמץ — מג"א, 72 דקות קבועות.''',
    isRelevant: _isErevPesach,
    compute: (c) => c.cal.getSofZmanAchilasChametzMGA72Minutes(),
  ),
  ZmanDefinition(
    id: 'biurChametzMGADegrees',
    title: 'סוף זמן ביעור חמץ',
    subtitle: 'מג"א (מעלות)',
    category: 'ערב פסח',
    explanation: '''סוף זמן ביעור חמץ — מג"א, 16.1° (≈72 דק׳).''',
    isRelevant: _isErevPesach,
    defaultEnabled: true,
    pairId: 'biurChametz',
    pairLabel: 'מג"א',
    compute: (c) => c.cal.getSofZmanBiurChametzMGA16Point1Degrees(),
  ),
  ZmanDefinition(
    id: 'biurChametzGRA',
    title: 'סוף זמן ביעור חמץ',
    subtitle: 'גר"א',
    category: 'ערב פסח',
    explanation: '''סוף זמן ביעור חמץ — גר"א.''',
    isRelevant: _isErevPesach,
    defaultEnabled: true,
    pairId: 'biurChametz',
    pairLabel: 'גר"א',
    compute: (c) => c.cal.getSofZmanBiurChametzGRA(),
  ),
  ZmanDefinition(
    id: 'biurChametzMGAShavos',
    title: 'סוף זמן ביעור חמץ',
    subtitle: 'מג"א (שוות)',
    category: 'ערב פסח',
    explanation: '''סוף זמן ביעור חמץ — מג"א, 72 דקות קבועות.''',
    isRelevant: _isErevPesach,
    compute: (c) => c.cal.getSofZmanBiurChametzMGA72Minutes(),
  ),

  // ── תעניות: יציאת הצום (כולן מופעלות כברירת מחדל) ───────────────────────
  ZmanDefinition(
    id: 'fastEndTikLenient',
    title: 'יציאת הצום',
    subtitle: 'לקולא — טיקוצ׳ינסקי',
    category: 'תעניות',
    explanation: '''סיום הצום לקולא — 13.5 דקות אחרי השקיעה (טוקוצ׳ינסקי).''',
    isRelevant: _isTaanisNotYomKippur,
    defaultEnabled: true,
    compute: (c) =>
        c.cal.getSunset()?.add(const Duration(minutes: 13, seconds: 30)),
  ),
  ZmanDefinition(
    id: 'fastEndItimLenient',
    title: 'יציאת הצום',
    subtitle: 'לקולא — עיתים לבינה',
    category: 'תעניות',
    explanation: '''סיום הצום לקולא — 18 דקות אחרי השקיעה (עיתים לבינה).''',
    isRelevant: _isTaanisNotYomKippur,
    defaultEnabled: true,
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 18)),
  ),
  ZmanDefinition(
    id: 'fastEndTikStringent',
    title: 'יציאת הצום',
    subtitle: 'לחומרא — טיקוצ׳ינסקי',
    category: 'תעניות',
    explanation: '''סיום הצום לחומרא — 18 דקות אחרי השקיעה (טוקוצ׳ינסקי).''',
    isRelevant: _isTaanisNotYomKippur,
    defaultEnabled: true,
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 18)),
  ),
  ZmanDefinition(
    id: 'fastEndItimStringent',
    title: 'יציאת הצום',
    subtitle: 'לחומרא — עיתים לבינה',
    category: 'תעניות',
    explanation: '''סיום הצום לחומרא — 22 דקות אחרי השקיעה (עיתים לבינה).''',
    isRelevant: _isTaanisNotYomKippur,
    defaultEnabled: true,
    compute: (c) => c.cal.getSunset()?.add(const Duration(minutes: 22)),
  ),

  // ── קידוש לבנה (כל החודש; ברירת מחדל לא מוצג; מציג ליל-שבוע ותאריך) ──────
  ZmanDefinition(
    id: 'tchilasKidushLevana3',
    title: 'תחילת קידוש לבנה',
    subtitle: '3 ימים',
    category: 'קידוש לבנה',
    explanation: '''הזמן המוקדם לקידוש לבנה לפי המנהג של 3 ימים אחרי המולד.''',
    showHebrewDate: true,
    compute: (c) => c.jewishCalendar.getTchilasZmanKidushLevana3Days(),
  ),
  ZmanDefinition(
    id: 'tchilasKidushLevana7',
    title: 'תחילת קידוש לבנה',
    subtitle: '7 ימים',
    category: 'קידוש לבנה',
    explanation: '''הזמן המוקדם לקידוש לבנה לפי המנהג של 7 ימים אחרי המולד.''',
    showHebrewDate: true,
    compute: (c) => c.jewishCalendar.getTchilasZmanKidushLevana7Days(),
  ),
  ZmanDefinition(
    id: 'sofKidushLevanaMoldos',
    title: 'סוף קידוש לבנה',
    subtitle: 'אמצע מולדות',
    category: 'קידוש לבנה',
    explanation: '''סוף זמן קידוש לבנה לפי אמצע החודש בין המולדות (≈ ט"ו).''',
    showHebrewDate: true,
    moladPushToTzais: false,
    compute: (c) => c.jewishCalendar.getSofZmanKidushLevanaBetweenMoldos(),
  ),
  ZmanDefinition(
    id: 'sofKidushLevana15',
    title: 'סוף קידוש לבנה',
    subtitle: '15 ימים',
    category: 'קידוש לבנה',
    explanation: '''סוף זמן קידוש לבנה לפי 15 ימים אחרי המולד.''',
    showHebrewDate: true,
    moladPushToTzais: false,
    compute: (c) => c.jewishCalendar.getSofZmanKidushLevana15Days(),
  ),
];

/// סט מזהי הזמנים המוצגים כברירת מחדל (לפני שהמשתמש משנה העדפות).
Set<String> get kDefaultEnabledZmanim => kZmanimRegistry
    .where((def) => def.defaultEnabled)
    .map((def) => def.id)
    .toSet();
