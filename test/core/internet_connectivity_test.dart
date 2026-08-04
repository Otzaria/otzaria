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
