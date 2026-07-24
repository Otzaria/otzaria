// טסטים ל-calculateDailyTimes: וידוא שהמפתחות שברישום מוחזרים בפועל,
// יחסי הזמנים נכונים, וזמנים תלויי-יום (תענית) מופיעים רק כשרלוונטי.

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';

void main() {
  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
  });

  // אמצע יוני — בקיץ ההפרש בין שעות שוות לזמניות בולט (היום ארוך מ-12
  // שעות), ולכן קצה טוב להבחנה בין שיטות החישוב.
  final summerDate = DateTime(2026, 6, 15);
  const city = 'ירושלים';

  group('הדלקת נרות — דקות לפי עיר', () {
    test('קורא את מספר הדקות מטבלת הערים המקומית', () {
      expect(getCandleLightingMinutes('אופקים'), 20);
      expect(getCandleLightingMinutes('ביתר עילית'), 40);
      expect(getCandleLightingMinutes('בני ברק'), 30);
      expect(getCandleLightingMinutes('רכסים'), 25);
      expect(getCandleLightingMinutes('ברוקלין'), 18);
    });

    test('כולל ערים חדשות מהטבלה בנתוני המיקום', () {
      expect(getCityData('חריש'), isNotNull);
      expect(getCityData('מירון'), isNotNull);
      expect(getCityData('רמת בית שמש'), isNotNull);
      expect(getCityData('ברוקלין'), isNotNull);
    });

    test('רשימת בחירת הערים כוללת ערים חדשות מהטבלה', () {
      final cityNames = getCalendarCityNames();

      expect(cityNames, contains('חריש'));
      expect(cityNames, contains('מירון'));
      expect(cityNames, contains('רמת בית שמש'));
      expect(cityNames, contains('ברוקלין'));
    });

    test('מפחית מהשקיעה את מספר הדקות של העיר', () {
      final context = buildZmanimCalendarContext(
        DateTime(2026, 7, 3),
        'אופקים',
      )!;
      final sunset = context.zmanimCalendar.getSunset()!;
      final candleLighting = calculateCandleLightingTime(
        context.zmanimCalendar,
        'אופקים',
      )!;

      expect(sunset.difference(candleLighting), const Duration(minutes: 20));
    });
  });

  group('calculateDailyTimes — מפתחות עיקריים', () {
    test('מחזיר את כל וריאנטי עלות השחר (מעלות / שוות / זמניות, 72/90)', () {
      final times = calculateDailyTimes(summerDate, city);

      expect(times['alos72Degrees'], isNotNull);
      expect(times['alos90Degrees'], isNotNull);
      expect(times['alos72Shavos'], isNotNull);
      expect(times['alos90Shavos'], isNotNull);
      expect(times['alos72Zmanis'], isNotNull);
      expect(times['alos90Zmanis'], isNotNull);
    });

    test('מחזיר את משיכיר 10.2° (זמן ציצית ותפילין)', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(times['misheyakir10point2'], isNotNull);
      expect(times['misheyakir10point2'], isNot(equals('')));
    });

    test('מחזיר את ר"ת בדקות שוות ובמעלות', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(times['rt72Shavos'], isNotNull);
      expect(times['rt72Degrees'], isNotNull);
    });

    test('מחזיר את שקיעה מישורית (sea level) לצד שקיעה רגילה', () {
      final times = calculateDailyTimes(summerDate, city);

      expect(times['sunset'], isNotNull);
      expect(times['seaLevelSunset'], isNotNull);
      // בירושלים (754 מ׳) — השקיעה המתוקנת-גובה מאוחרת מהמישורית.
      expect(
        times['seaLevelSunset']!.compareTo(times['sunset']!),
        lessThan(0),
        reason: 'שקיעה מישורית צריכה להיות מוקדמת משקיעה מתוקנת-גובה',
      );
    });
  });

  group('calculateDailyTimes — פורמט וחוקיות', () {
    test('כל הזמנים בפורמט HH:MM עם סימן שניות (למעט קידוש לבנה)', () {
      final times = calculateDailyTimes(summerDate, city);
      // כל זמן עטוף ב-LTR isolate ומסתיים בסימן שניות: נקודה (0–29) או
      // נקודותיים (30–59).
      final pattern = RegExp(r'^\u2066?\d{2}:\d{2}[.:]\u2069?$');
      // קידוש לבנה מוצג עם ליל-שבוע ותאריך עברי, לא כ-HH:MM בלבד.
      const hebrewDateKeys = {
        'tchilasKidushLevana3',
        'tchilasKidushLevana7',
        'sofKidushLevanaMoldos',
        'sofKidushLevana15',
      };
      for (final entry in times.entries) {
        if (hebrewDateKeys.contains(entry.key)) continue;
        expect(
          pattern.hasMatch(entry.value),
          isTrue,
          reason: 'הזמן ${entry.key} = "${entry.value}" אינו בפורמט HH:MM',
        );
      }
    });

    test('עלות זמניות מוקדם מעלות שוות בקיץ (היום ארוך מ-12 שעות)', () {
      final times = calculateDailyTimes(summerDate, city);
      final shavos72 = times['alos72Shavos']!;
      final zmanis72 = times['alos72Zmanis']!;
      expect(
        zmanis72.compareTo(shavos72),
        lessThan(0),
        reason:
            'בקיץ עלות 72 זמניות מוקדם מ-72 שוות. '
            'zmanis=$zmanis72 shavos=$shavos72',
      );
    });

    test('עלות 90 מוקדם מעלות 72 (בכל השיטות)', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(
        times['alos90Shavos']!.compareTo(times['alos72Shavos']!),
        lessThan(0),
      );
      expect(
        times['alos90Zmanis']!.compareTo(times['alos72Zmanis']!),
        lessThan(0),
      );
      expect(
        times['alos90Degrees']!.compareTo(times['alos72Degrees']!),
        lessThan(0),
      );
    });

    test('ר"ת מאוחר מהשקיעה', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(times['rt72Degrees']!.compareTo(times['sunset']!), greaterThan(0));
      expect(times['rt72Shavos']!.compareTo(times['sunset']!), greaterThan(0));
    });
  });

  group('calculateDailyTimes — יציאת הצום (תלוי-יום)', () {
    // י"ז בתמוז 5786 = 2026-07-02 (תענית קלה).
    final fastDate = DateTime(2026, 7, 2);

    test('בתאריך תענית — מחזיר את וריאנטי יציאת הצום', () {
      final times = calculateDailyTimes(fastDate, city);
      expect(times['fastEndTikLenient'], isNotNull);
      expect(times['fastEndItimLenient'], isNotNull);
      expect(times['fastEndTikStringent'], isNotNull);
      expect(times['fastEndItimStringent'], isNotNull);
    });

    test('סדר הזמנים: קולא לפני חומרא; 18 דק׳ זהה בין השיטות', () {
      final times = calculateDailyTimes(fastDate, city);
      final tikLenient = times['fastEndTikLenient']!; // 13.5 דק׳
      final itimLenient = times['fastEndItimLenient']!; // 18 דק׳
      final tikStringent = times['fastEndTikStringent']!; // 18 דק׳
      final itimStringent = times['fastEndItimStringent']!; // 22 דק׳

      expect(tikLenient.compareTo(itimLenient), lessThan(0));
      expect(itimLenient, equals(tikStringent));
      expect(tikStringent.compareTo(itimStringent), lessThan(0));
    });

    test('ביום רגיל (לא תענית) — זמני יציאת הצום לא קיימים', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(times['fastEndTikLenient'], isNull);
      expect(times['fastEndItimLenient'], isNull);
    });
  });

  group('calculateDailyTimes — קידוש לבנה', () {
    test('זמני קידוש לבנה זמינים בכל יום (לא תלויי-יום)', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(times['tchilasKidushLevana3'], isNotNull);
      expect(times['sofKidushLevanaMoldos'], isNotNull);
    });

    test('הערך כולל ליל-שבוע, יום-חודש עברי ושעה', () {
      final times = calculateDailyTimes(summerDate, city);
      final value = times['tchilasKidushLevana3']!;
      // למשל: "ליל שני ט"ו לחודש 20:02"
      expect(value, startsWith('ליל '));
      expect(value, matches(RegExp(r'לחודש \u2066?\d{2}:\d{2}[.:]\u2069?$')));
    });

    int hourOf(String label) => int.parse(
      RegExp(r'(\d{2}):\d{2}[.:]?\u2069?$').firstMatch(label)!.group(1)!,
    );

    test('השעה מותאמת לאזור הזמן של העיר — לא זהה בין ערים', () {
      // לפני התיקון כל הערים קיבלו את אותה שעה (זמן ירושלים), כי הרגע
      // (מולד+ימים) הוצג בלי המרת timezone.
      final jerusalem = calculateDailyTimes(
        summerDate,
        'ירושלים',
      )['tchilasKidushLevana3']!;
      final newYork = calculateDailyTimes(
        summerDate,
        'ניו יורק',
      )['tchilasKidushLevana3']!;
      expect(
        jerusalem,
        isNot(equals(newYork)),
        reason: 'ירושלים=$jerusalem ניו יורק=$newYork',
      );
    });

    test('זמן שנופל ביום נדחה לשעת לילה (לא בין 07:00 ל-17:00)', () {
      // קידוש לבנה אינו נאמר ביום; רגע שנופל בשעות היום נדחה לצאת הכוכבים
      // (תחילה) או לעלות השחר (סוף). הדוגמה מהדיווח: 2026-06-15 הציג קודם
      // "ליל שני ט"ז לחודש 12:24" — שעת יום.
      final times = calculateDailyTimes(summerDate, city);
      for (final key in const [
        'tchilasKidushLevana3',
        'tchilasKidushLevana7',
        'sofKidushLevanaMoldos',
        'sofKidushLevana15',
      ]) {
        final value = times[key];
        if (value == null) continue;
        final hour = hourOf(value);
        expect(
          hour < 7 || hour >= 17,
          isTrue,
          reason: '$key = "$value" — שעת יום, היה צריך להידחות ללילה',
        );
      }
    });
  });

  group('isClockTime — אבחנת מפתח מיון', () {
    test('שעת-שעון HH:MM מזוהה כברת-מיון כרונולוגי', () {
      expect(isClockTime('02:37'), isTrue);
      expect(isClockTime('20:00'), isTrue);
      expect(isClockTime('9:05'), isTrue);
    });

    test('מחרוזת תאריך עברי (קידוש לבנה) אינה שעת-שעון', () {
      expect(isClockTime('ליל שבת ט״ז לחודש 02:37'), isFalse);
      expect(isClockTime('ליל שני ד׳ לחודש 20:00'), isFalse);
      expect(isClockTime('—'), isFalse);
      expect(isClockTime(''), isFalse);
    });

    test('מיון מעורב: שעות-שעון לפי שעה, ואחריהן זמני תאריך עברי', () {
      // מדמה את ה-comparator של הלוח/הטבלה: שעות-שעון תחילה (כרונולוגית),
      // וזמני קידוש לבנה אחריהן בסדר יציב — לא לפי המחרוזת הלקסיקוגרפית.
      final order = {'a': 0, 'kl1': 1, 'b': 2, 'kl2': 3};
      final items = [
        ('kl2', 'ליל שבת ט״ז לחודש 02:37'),
        ('b', '20:00'),
        ('kl1', 'ליל שני ד׳ לחודש 21:00'),
        ('a', '06:30'),
      ];
      items.sort((x, y) {
        final xc = isClockTime(x.$2);
        final yc = isClockTime(y.$2);
        if (xc && yc) return x.$2.compareTo(y.$2);
        if (xc != yc) return xc ? -1 : 1;
        return order[x.$1]!.compareTo(order[y.$1]!);
      });
      expect(items.map((e) => e.$1).toList(), ['a', 'b', 'kl1', 'kl2']);
    });
  });

  group('secondsMarker — סימן שניות בשיטת לוח עיתים לבינה', () {
    test('שניות 0–29 → נקודה (.)', () {
      expect(secondsMarker(DateTime(2026, 5, 31, 19, 43, 0)), '.');
      expect(secondsMarker(DateTime(2026, 5, 31, 19, 43, 29)), '.');
    });

    test('שניות 30–59 → נקודותיים (:)', () {
      expect(secondsMarker(DateTime(2026, 5, 31, 19, 43, 30)), ':');
      expect(secondsMarker(DateTime(2026, 5, 31, 19, 43, 58)), ':');
    });
  });

  group('formatZmanTime — פורמט HH:MM עם סימן שניות (ללא עיגול)', () {
    // הזמן עטוף ב-LTR isolate (\u2066…\u2069) לתצוגה תקינה ב-RTL.
    test('שקיעה 19:43:58 → "19:43:" (דקה נחתכת, נקודותיים כי 58≥30)', () {
      final jerusalem = tz.getLocation('Asia/Jerusalem');
      final t = tz.TZDateTime(jerusalem, 2026, 5, 31, 19, 43, 58);
      expect(formatZmanTime(t, jerusalem), '\u206619:43:\u2069');
    });

    test('שקיעה מישורית 19:39:10 → "19:39." (נקודה כי 10<30)', () {
      final jerusalem = tz.getLocation('Asia/Jerusalem');
      final t = tz.TZDateTime(jerusalem, 2026, 5, 31, 19, 39, 10);
      expect(formatZmanTime(t, jerusalem), '\u206619:39.\u2069');
    });
  });

  group('isClockTime — סובלנות לעטיפה ולסימן השניות', () {
    test('מזהה שעת-שעון עם/בלי עטיפת isolate וסימן שניות', () {
      expect(isClockTime('19:43.'), isTrue);
      expect(isClockTime('19:43:'), isTrue);
      expect(isClockTime('19:43'), isTrue);
      expect(isClockTime('\u206619:43:\u2069'), isTrue);
      expect(isClockTime('\u206619:39.\u2069'), isTrue);
    });
  });

  group('calculateDailyTimes — חצות לילה אסטרונומי', () {
    test('מחזיר ערך תקין לחצות לילה', () {
      final times = calculateDailyTimes(summerDate, city);
      expect(times['chatzosLayla'], isNotNull);
      expect(
        times['chatzosLayla'],
        matches(RegExp(r'^\u2066?\d{2}:\d{2}[.:]\u2069?$')),
      );
    });

    test('חצות לילה סביב חצות (00:00-02:00 בקיץ ירושלים)', () {
      final times = calculateDailyTimes(summerDate, city);
      final hour = int.parse(
        RegExp(r'(\d{2}):').firstMatch(times['chatzosLayla']!)!.group(1)!,
      );
      expect(
        hour,
        anyOf(equals(0), equals(1)),
        reason:
            'חצות לילה בקיץ בין 00:00 ל-02:00 '
            '(התקבל: ${times['chatzosLayla']})',
      );
    });
  });
}
