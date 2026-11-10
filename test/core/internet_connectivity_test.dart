import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/internet_connectivity.dart';

void main() {
  tearDown(() => debugSocketConnect = null);

  group('hasInternetConnection', () {
    test('יעד אחד שנענה מספיק כדי לקבוע שיש אינטרנט', () async {
      debugSocketConnect = (host, port, timeout) async => host == '8.8.8.8';

      expect(await hasInternetConnection(), isTrue);
    });

    test('הצלחה ביעד אחד אינה ממתינה ליעדים שתקועים', () async {
      final blocked = Completer<bool>();
      debugSocketConnect = (host, port, timeout) =>
          host == 'otzaria.org' ? Future.value(true) : blocked.future;

      final result = await hasInternetConnection(
        targets: kOtzariaProbeTargets,
      ).timeout(const Duration(milliseconds: 100));

      expect(result, isTrue);
      blocked.complete(false);
    });

    test('כשכל היעדים אינם נענים — אין אינטרנט', () async {
      debugSocketConnect = (host, port, timeout) async => false;

      expect(await hasInternetConnection(), isFalse);
    });

    test('חריגה ביעד אחד אינה מבטלת יעד אחר שנענה', () async {
      debugSocketConnect = (host, port, timeout) async {
        if (host == '1.1.1.1') throw const SocketExceptionStub();
        return true;
      };

      expect(await hasInternetConnection(), isTrue);
    });

    test('חריגה בכל היעדים מחזירה false — הבדיקה עצמה לא זורקת', () async {
      debugSocketConnect = (host, port, timeout) async =>
          throw const SocketExceptionStub();

      expect(await hasInternetConnection(), isFalse);
    });

    test('חריגה סינכרונית (לא Future) גם היא נבלעת', () async {
      debugSocketConnect = (host, port, timeout) =>
          throw const SocketExceptionStub();

      expect(await hasInternetConnection(), isFalse);
    });

    test('נבדקים כמה יעדים במקביל, ולא רק אחד', () async {
      final probed = <String>[];
      debugSocketConnect = (host, port, timeout) async {
        probed.add(host);
        return false;
      };

      await hasInternetConnection();

      expect(probed.length, greaterThan(1));
      expect(probed.toSet().length, probed.length, reason: 'יעדים ייחודיים');
    });

    test(
      'היעדים אינם GitHub — תקלה בשרתי העדכון תסווג כתקלה ולא כניתוק',
      () async {
        final probed = <String>[];
        debugSocketConnect = (host, port, timeout) async {
          probed.add(host);
          return false;
        };

        await hasInternetConnection();

        expect(probed.any((host) => host.contains('github')), isFalse);
      },
    );

    test(
      'ברירת המחדל אינה כוללת את otzaria.org — מסלול העדכונים לא מושפע',
      () async {
        // "מחובר" במסלול העדכונים גורר הודעת שגיאה. משתמש שרק אוצריא פתוחה
        // אצלו היה מקבל אותה בכל עלייה, על כשל מול GitHub שלא בידיו לתקן.
        final probed = <String>[];
        debugSocketConnect = (host, port, timeout) async {
          probed.add(host);
          return false;
        };

        await hasInternetConnection();

        expect(probed, isNot(contains('otzaria.org')));
      },
    );

    test('otzaria.org נבדק ביעדי הקישוריות של התוספים', () async {
      final probed = <String>[];
      debugSocketConnect = (host, port, timeout) async {
        probed.add(host);
        return false;
      };

      await hasInternetConnection(targets: kOtzariaProbeTargets);

      expect(probed, contains('otzaria.org'));
    });

    test('די ב-otzaria.org לבדו כדי לקבוע שיש רשת', () async {
      // רשת מסוננת שחוסמת את השאר — זה הרוב אצל משתמשי אוצריא.
      debugSocketConnect = (host, port, timeout) async => host == 'otzaria.org';

      expect(
        await hasInternetConnection(targets: kOtzariaProbeTargets),
        isTrue,
      );
    });

    test('תקלה ב-otzaria.org לבדו אינה מסווגת משתמש מחובר כמנותק', () async {
      debugSocketConnect = (host, port, timeout) async => host != 'otzaria.org';

      expect(
        await hasInternetConnection(targets: kOtzariaProbeTargets),
        isTrue,
      );
    });

    test('רשימת יעדים ריקה מחזירה false ולא זורקת', () async {
      debugSocketConnect = (host, port, timeout) async => true;

      expect(await hasInternetConnection(targets: const []), isFalse);
    });

    test('חיבור שנתקע מסתיים ב-timeout ולא מקפיא את הקורא', () async {
      debugSocketConnect = (host, port, timeout) =>
          Completer<bool>().future; // לעולם לא מסתיים

      expect(
        await hasInternetConnection(timeout: const Duration(milliseconds: 20)),
        isFalse,
      );
    });

    test('ה-timeout שהתקבל מועבר לחיבור עצמו', () async {
      Duration? seen;
      debugSocketConnect = (host, port, timeout) async {
        seen = timeout;
        return false;
      };

      await hasInternetConnection(timeout: const Duration(milliseconds: 250));

      expect(seen, const Duration(milliseconds: 250));
    });

    test(
      'ברירת המחדל היא timeout קצר — הבדיקה לא תתקע את זרימת הכשל',
      () async {
        Duration? seen;
        debugSocketConnect = (host, port, timeout) async {
          seen = timeout;
          return false;
        };

        await hasInternetConnection();

        expect(seen!.inSeconds, lessThanOrEqualTo(5));
        expect(seen!.inMilliseconds, greaterThan(0));
      },
    );
  });
}

/// חריגה מדומה — הבדיקה רק מוודאת שכל חריגה נבלעת, לא סוג מסוים.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
