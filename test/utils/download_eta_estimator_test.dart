import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/download_eta_estimator.dart';

void main() {
  group('DownloadEtaEstimator', () {
    final start = DateTime(2026, 1, 1, 12, 0, 0);

    test('מחזיר null לפני שיש שתי דגימות', () {
      final estimator = DownloadEtaEstimator();
      final eta = estimator.update(
        downloadedBytes: 0,
        totalBytes: 1000,
        now: start,
      );
      expect(eta, isNull);
    });

    test('מחשב זמן נותר לפי המהירות שנמדדה', () {
      final estimator = DownloadEtaEstimator();
      // דגימה ראשונה: 0 בייטים בזמן 0
      estimator.update(downloadedBytes: 0, totalBytes: 1000, now: start);
      // דגימה שנייה: 100 בייטים אחרי שנייה אחת => 100 בייט/שנייה
      final eta = estimator.update(
        downloadedBytes: 100,
        totalBytes: 1000,
        now: start.add(const Duration(seconds: 1)),
      );
      // נותרו 900 בייטים ב-100 בייט/שנייה => 9 שניות
      expect(eta, isNotNull);
      expect(eta!.inSeconds, 9);
    });

    test('מחזיר Duration.zero כשההורדה הושלמה', () {
      final estimator = DownloadEtaEstimator();
      estimator.update(downloadedBytes: 500, totalBytes: 1000, now: start);
      final eta = estimator.update(
        downloadedBytes: 1000,
        totalBytes: 1000,
        now: start.add(const Duration(seconds: 1)),
      );
      expect(eta, Duration.zero);
    });

    test('משתמש בממוצע נע של החלון ולא בממוצע גלובלי', () {
      // חלון של 2 שניות. הורדה איטית בהתחלה ואז מהירה — ההערכה צריכה
      // לשקף את המהירות האחרונה, לא את הממוצע מתחילת ההורדה.
      // refreshInterval אפס כדי לבודד את לוגיקת החלון מה-throttling.
      final estimator = DownloadEtaEstimator(
        window: const Duration(seconds: 2),
        refreshInterval: Duration.zero,
      );
      estimator.update(downloadedBytes: 0, totalBytes: 10000, now: start);
      // איטי: 10 בייט בשנייה הראשונה
      estimator.update(
        downloadedBytes: 10,
        totalBytes: 10000,
        now: start.add(const Duration(seconds: 1)),
      );
      // מהיר: 1000 בייט נוספים בשנייה הבאה
      estimator.update(
        downloadedBytes: 1010,
        totalBytes: 10000,
        now: start.add(const Duration(seconds: 2)),
      );
      // דגימה שמגלגלת את החלון — מסירה את הדגימה מזמן 0
      final eta = estimator.update(
        downloadedBytes: 2010,
        totalBytes: 10000,
        now: start.add(const Duration(seconds: 3)),
      );
      // החלון (2 שניות אחרונות): ~1000 בייט/שנייה. נותרו ~7990 => ~8 שניות,
      // הרבה פחות מהערכת ממוצע גלובלי (שהיתה גבוהה בהרבה).
      expect(eta, isNotNull);
      expect(eta!.inSeconds, lessThan(12));
    });

    test('מגביל את קצב רענון הזמן המוצג ל-refreshInterval', () {
      // refreshInterval של 3 שניות: בין רענונים מוחזרת ההערכה הקודמת,
      // גם אם המהירות בפועל השתנתה — כדי שהשורה לא תיראה קופצנית.
      final estimator = DownloadEtaEstimator(
        refreshInterval: const Duration(seconds: 3),
      );
      estimator.update(downloadedBytes: 0, totalBytes: 10000, now: start);
      // t+1s: 100 בייט/שנייה => נותרו 9900 => ~99 שניות. דיווח ראשון.
      final first = estimator.update(
        downloadedBytes: 100,
        totalBytes: 10000,
        now: start.add(const Duration(seconds: 1)),
      );
      expect(first!.inSeconds, 99);

      // t+2s: זינוק במהירות, אבל עברה רק שנייה מהדיווח => מוחזר הערך הקודם.
      final throttled = estimator.update(
        downloadedBytes: 5000,
        totalBytes: 10000,
        now: start.add(const Duration(seconds: 2)),
      );
      expect(throttled!.inSeconds, 99);

      // t+4s: עברו 3 שניות מהדיווח האחרון => מתעדכן לערך חדש.
      final refreshed = estimator.update(
        downloadedBytes: 9000,
        totalBytes: 10000,
        now: start.add(const Duration(seconds: 4)),
      );
      expect(refreshed!.inSeconds, isNot(99));
    });
  });

  group('formatRemainingTimeHebrew', () {
    test('דקות ושניות', () {
      expect(
        formatRemainingTimeHebrew(const Duration(minutes: 7, seconds: 30)),
        'נותרו כ-7 דקות ו-30 שניות',
      );
    });

    test('שניות בלבד', () {
      expect(
        formatRemainingTimeHebrew(const Duration(seconds: 45)),
        'נותרו כ-45 שניות',
      );
    });

    test('שעות ודקות — ללא שניות', () {
      expect(
        formatRemainingTimeHebrew(
          const Duration(hours: 1, minutes: 20, seconds: 5),
        ),
        'נותרו כ-שעה ו-20 דקות',
      );
    });

    test('יחיד — דקה אחת', () {
      expect(
        formatRemainingTimeHebrew(const Duration(minutes: 1)),
        'נותרו כ-דקה',
      );
    });

    test('פחות משנייה', () {
      expect(
        formatRemainingTimeHebrew(Duration.zero),
        'נותרו רגעים אחרונים',
      );
    });

    test('מעגל לחמישיית השניות הקרובה — כלפי מעלה', () {
      // 63 שניות => 65 => דקה ו-5 שניות
      expect(
        formatRemainingTimeHebrew(const Duration(seconds: 63)),
        'נותרו כ-דקה ו-5 שניות',
      );
    });

    test('מעגל לחמישיית השניות הקרובה — כלפי מטה', () {
      // 67 שניות => 65 => דקה ו-5 שניות
      expect(
        formatRemainingTimeHebrew(const Duration(seconds: 67)),
        'נותרו כ-דקה ו-5 שניות',
      );
      // 72 שניות => 70 => דקה ו-10 שניות
      expect(
        formatRemainingTimeHebrew(const Duration(seconds: 72)),
        'נותרו כ-דקה ו-10 שניות',
      );
    });

    test('עיגול שגורם למעבר לדקה שלמה משמיט את השניות', () {
      // 58 שניות => 60 => דקה (ללא שניות)
      expect(
        formatRemainingTimeHebrew(const Duration(seconds: 58)),
        'נותרו כ-דקה',
      );
    });
  });
}
