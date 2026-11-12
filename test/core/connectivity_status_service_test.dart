import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/core/internet_connectivity.dart';

void main() {
  group('ConnectivitySnapshot', () {
    test('isOnline דורש גם היעדר מצב מנותק וגם רשת בפועל', () {
      expect(
        const ConnectivitySnapshot(
          isOfflineMode: false,
          hasNetwork: true,
        ).isOnline,
        isTrue,
      );
      expect(
        const ConnectivitySnapshot(
          isOfflineMode: false,
          hasNetwork: false,
        ).isOnline,
        isFalse,
      );
      expect(
        const ConnectivitySnapshot(
          isOfflineMode: true,
          hasNetwork: true,
        ).isOnline,
        isFalse,
      );
      expect(
        const ConnectivitySnapshot(
          isOfflineMode: true,
          hasNetwork: false,
        ).isOnline,
        isFalse,
      );
    });

    test('bootPayload ו-toJson חושפים בדיוק את אותם שדות', () {
      // סטייה ביניהם שוברת את חוזה `plugin.boot` מול `app.getConnectivity`.
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () => Completer<bool>().future,
      );

      expect(
        service.bootPayload().keys.toSet(),
        const ConnectivitySnapshot(
          isOfflineMode: false,
          hasNetwork: true,
        ).toJson().keys.toSet(),
      );
    });

    test('toJson חושף בדיוק את שלושת השדות שהתוסף מצפה להם', () {
      final json = const ConnectivitySnapshot(
        isOfflineMode: false,
        hasNetwork: true,
      ).toJson();

      expect(json, {
        'isOfflineMode': false,
        'hasNetwork': true,
        'isOnline': true,
      });
    });
  });

  group('ConnectivityStatusService — מצב מנותק', () {
    test('אינו מבצע שום בדיקת רשת', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => true,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      final snapshot = await service.snapshot();

      expect(probes, 0, reason: 'זה עיקר החיסכון — אין לגעת ברשת כלל');
      expect(snapshot.isOfflineMode, isTrue);
      expect(snapshot.hasNetwork, isFalse);
      expect(snapshot.isOnline, isFalse);
    });

    test('cached זמין מיידית ואינו מפעיל בדיקה', () {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => true,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      final cached = service.cached;

      expect(cached, isNotNull);
      expect(cached!.isOnline, isFalse);
      expect(probes, 0);
    });

    test('prewarm אינו מפעיל בדיקה', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => true,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      service.prewarm();
      await Future<void>.delayed(Duration.zero);

      expect(probes, 0);
    });

    test('כיבוי המצב תוך כדי ריצה מפעיל בדיקה אמיתית', () async {
      var offline = true;
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => offline,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      expect((await service.snapshot()).isOnline, isFalse);
      expect(probes, 0);

      offline = false;
      final after = await service.snapshot();

      expect(probes, 1, reason: '"מנותק" לא נקבע בקאש כתוצאת בדיקה');
      expect(after.isOnline, isTrue);
    });

    test('הדלקת המצב אחרי שנקבע "מחובר" מחזירה מנותק מיד', () async {
      var offline = false;
      final service = ConnectivityStatusService(
        offlineModeReader: () => offline,
        networkProbe: () async => true,
      );

      expect((await service.snapshot()).isOnline, isTrue);

      offline = true;

      expect((await service.snapshot()).isOnline, isFalse);
      expect(service.cached?.isOfflineMode, isTrue);
      expect(service.bootPayload()['isOnline'], isFalse);
    });
  });

  group('ConnectivityStatusService — חיווט ברירת המחדל', () {
    test('הבדיקה בפועל היא מול יעדי אוצריא, לא הניטרליים בלבד', () async {
      final probed = <String>[];
      debugSocketConnect = (host, port, timeout) async {
        probed.add(host);
        return false;
      };
      addTearDown(() => debugSocketConnect = null);

      // בלי networkProbe מוזרק — הנתיב שרץ בפרודקשן.
      final service = ConnectivityStatusService(offlineModeReader: () => false);
      await service.snapshot();

      expect(probed, contains('otzaria.org'));
      expect(probed.length, kOtzariaProbeTargets.length);
    });

    test('מצב מנותק חוסם גם את הנתיב הלא-מוזרק', () async {
      var probes = 0;
      debugSocketConnect = (host, port, timeout) async {
        probes++;
        return true;
      };
      addTearDown(() => debugSocketConnect = null);

      final service = ConnectivityStatusService(offlineModeReader: () => true);
      final snapshot = await service.snapshot();

      expect(probes, 0);
      expect(snapshot.isOnline, isFalse);
    });
  });

  group('ConnectivityStatusService — בדיקת רשת', () {
    test('בדיקה מוצלחת מסמנת מחובר', () async {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async => true,
      );

      final snapshot = await service.snapshot();

      expect(snapshot.isOfflineMode, isFalse);
      expect(snapshot.hasNetwork, isTrue);
      expect(snapshot.isOnline, isTrue);
    });

    test('בדיקה שנכשלה מסמנת מנותק — בלי מצב מנותק בהגדרות', () async {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async => false,
      );

      final snapshot = await service.snapshot();

      expect(snapshot.isOfflineMode, isFalse);
      expect(snapshot.hasNetwork, isFalse);
      expect(snapshot.isOnline, isFalse);
    });

    test('חריגה בבדיקה נבלעת ומסווגת כמנותק', () async {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async => throw Exception('רשת נפלה'),
      );

      final snapshot = await service.snapshot();

      expect(snapshot.hasNetwork, isFalse);
      expect(snapshot.isOnline, isFalse);
    });

    test('חריגה סינכרונית בבדיקה גם היא נבלעת', () async {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () => throw Exception('נפילה מיידית'),
      );

      expect((await service.snapshot()).isOnline, isFalse);
    });
  });

  group('ConnectivityStatusService — קאש ויציבות', () {
    test('התוצאה נשמרת בתוך חלון הקאש', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      for (var i = 0; i < 25; i++) {
        expect((await service.snapshot()).isOnline, isTrue);
      }

      expect(probes, 1, reason: 'קריאה מרינדור לא תפתח חיבור בכל פעם');
    });

    test('התשובה אינה מתהפכת בתוך חלון הקאש', () async {
      var reachable = true;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async => reachable,
      );

      expect((await service.snapshot()).isOnline, isTrue);
      reachable = false;

      expect(
        (await service.snapshot()).isOnline,
        isTrue,
        reason: 'קריאות סמוכות לא אמורות להבהב בין רינדורים',
      );
    });

    test('גם תוצאת "אין רשת" נשמרת ואינה נבדקת שוב', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return false;
        },
      );

      await service.snapshot();
      await service.snapshot();

      expect(
        probes,
        1,
        reason: 'בלי רשת הבדיקה יקרה — אין לחזור עליה בתוך חלון הקאש',
      );
    });

    test('תוצאה שפג תוקפה נבדקת מחדש', () async {
      var now = DateTime(2026);
      var reachable = false;
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return reachable;
        },
        clock: () => now,
      );

      expect((await service.snapshot()).isOnline, isFalse);
      reachable = true;
      now = now.add(const Duration(seconds: 31));

      expect((await service.snapshot()).isOnline, isTrue);
      expect(probes, 2);
    });

    test('forceRefresh מרענן גם תוצאה טרייה', () async {
      var reachable = false;
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return reachable;
        },
      );

      expect((await service.snapshot()).isOnline, isFalse);
      reachable = true;

      expect((await service.snapshot(forceRefresh: true)).isOnline, isTrue);
      expect(probes, 2);
    });

    test('forceRefresh מצטרף לבדיקה שכבר רצה', () async {
      var probes = 0;
      final completer = Completer<bool>();
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () {
          probes++;
          return completer.future;
        },
      );

      final first = service.snapshot();
      final refreshed = service.snapshot(forceRefresh: true);
      completer.complete(true);

      expect((await first).isOnline, isTrue);
      expect((await refreshed).isOnline, isTrue);
      expect(probes, 1);
    });

    test('קריאות מקבילות מתלכדות לבדיקה אחת', () async {
      var probes = 0;
      final completer = Completer<bool>();
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () {
          probes++;
          return completer.future;
        },
      );

      final pending = Future.wait([
        service.snapshot(),
        service.snapshot(),
        service.snapshot(),
      ]);
      completer.complete(true);
      final results = await pending;

      expect(probes, 1, reason: 'פתיחת כמה תוספים יחד לא תפתח כמה חיבורים');
      expect(results.every((r) => r.isOnline), isTrue);
    });

    test('בדיקה שנכשלה אינה נותנת קאש שגוי לקריאות שהמתינו לה', () async {
      final completer = Completer<bool>();
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () => completer.future,
      );

      final pending = Future.wait([service.snapshot(), service.snapshot()]);
      completer.completeError(Exception('כשל'));
      final results = await pending;

      expect(results.every((r) => r.isOnline == false), isTrue);
    });

    test('prewarm מכריע את התשובה בלי שמישהו ימתין לה', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      service.prewarm();
      expect(probes, 1);
      await Future<void>.delayed(Duration.zero);

      expect(service.cached?.isOnline, isTrue);
    });

    test('prewarm חוזר אינו מוסיף בדיקות', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      service.prewarm();
      await Future<void>.delayed(Duration.zero);
      service.prewarm();
      service.prewarm();
      await Future<void>.delayed(Duration.zero);

      expect(probes, 1);
    });

    test('cached הוא null עד שהבדיקה הוכרעה', () async {
      final completer = Completer<bool>();
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () => completer.future,
      );

      final pending = service.snapshot();
      expect(service.cached, isNull);

      completer.complete(true);
      await pending;

      expect(service.cached?.isOnline, isTrue);
    });
  });

  group('ConnectivityStatusService.bootPayload — בלי לעכב פתיחת תוסף', () {
    test('חוזר מיד עם null כשהבדיקה טרם הוכרעה', () {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () => Completer<bool>().future,
      );

      final payload = service.bootPayload();

      expect(payload['hasNetwork'], isNull);
      expect(payload['isOnline'], isNull);
      expect(payload['isOfflineMode'], isFalse);
    });

    test('אינו ממתין גם כשהבדיקה נמשכת זמן רב', () async {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () =>
            Future<bool>.delayed(const Duration(seconds: 30), () => true),
      );

      // סינכרוני לחלוטין: הקריאה מחזירה ערך בלי await ולכן לא יכולה לעכב.
      final payload = service.bootPayload();

      expect(payload['isOnline'], isNull);
    });

    test('מפעיל את הבדיקה ברקע כדי שהתוסף הבא כבר יקבל תשובה', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      expect(service.bootPayload()['isOnline'], isNull);
      await Future<void>.delayed(Duration.zero);

      expect(probes, 1);
      expect(service.bootPayload()['isOnline'], isTrue);
    });

    test('במצב מנותק מחזיר תשובה ודאית מיידית, בלי בדיקה', () {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => true,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      final payload = service.bootPayload();

      expect(payload, {
        'isOfflineMode': true,
        'hasNetwork': false,
        'isOnline': false,
      });
      expect(probes, 0);
    });

    test('אחרי הכרעה שלילית מחזיר false ולא null', () async {
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async => false,
      );

      await service.snapshot();

      expect(service.bootPayload()['isOnline'], isFalse);
      expect(service.bootPayload()['hasNetwork'], isFalse);
    });

    test('כמה קריאות רצופות אינן פותחות כמה בדיקות', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () => Completer<bool>().future.whenComplete(() {}),
      );
      final counted = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () {
          probes++;
          return Completer<bool>().future;
        },
      );
      service.bootPayload();

      counted.bootPayload();
      counted.bootPayload();
      counted.bootPayload();

      expect(probes, 1);
    });
  });

  group('ConnectivityStatusService.instance', () {
    test('resetCache מאפשר בדיקה מחדש', () async {
      var probes = 0;
      final service = ConnectivityStatusService(
        offlineModeReader: () => false,
        networkProbe: () async {
          probes++;
          return true;
        },
      );

      await service.snapshot();
      service.resetCache();
      await service.snapshot();

      expect(probes, 2);
    });
  });
}
