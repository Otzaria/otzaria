// בדיקות ללוגיקת תדירות בדיקת העדכונים האוטומטית (issue #893):
// הפונקציה הטהורה שמכריעה אם בדיקת עדכונים אוטומטית נדרשת בעלייה.

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/update_check_frequency.dart';

void main() {
  final now = DateTime(2026, 8, 31, 12);

  group('UpdateCheckFrequency.fromStorage', () {
    test('מפענח את שלושת הערכים השמורים', () {
      expect(
        UpdateCheckFrequency.fromStorage('always'),
        UpdateCheckFrequency.everyLaunch,
      );
      expect(
        UpdateCheckFrequency.fromStorage('daily'),
        UpdateCheckFrequency.daily,
      );
      expect(
        UpdateCheckFrequency.fromStorage('weekly'),
        UpdateCheckFrequency.weekly,
      );
    });

    test('ערך חסר או לא מוכר נופל ל"בכל הפעלה" - ההתנהגות ההיסטורית', () {
      expect(
        UpdateCheckFrequency.fromStorage(null),
        UpdateCheckFrequency.everyLaunch,
      );
      expect(
        UpdateCheckFrequency.fromStorage('garbage'),
        UpdateCheckFrequency.everyLaunch,
      );
    });
  });

  group('shouldCheckForUpdatesNow', () {
    test('בכל הפעלה - תמיד בודקים, גם מיד אחרי בדיקה', () {
      expect(
        shouldCheckForUpdatesNow(
          frequency: UpdateCheckFrequency.everyLaunch,
          lastSuccessfulCheck: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('ללא חותמת (טרם נבדק) - בודקים בכל תדירות', () {
      for (final frequency in UpdateCheckFrequency.values) {
        expect(
          shouldCheckForUpdatesNow(
            frequency: frequency,
            lastSuccessfulCheck: null,
            now: now,
          ),
          isTrue,
        );
      }
    });

    test('יומי - לא בודקים בתוך 24 שעות, בודקים אחריהן', () {
      expect(
        shouldCheckForUpdatesNow(
          frequency: UpdateCheckFrequency.daily,
          lastSuccessfulCheck: now.subtract(const Duration(hours: 23)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldCheckForUpdatesNow(
          frequency: UpdateCheckFrequency.daily,
          lastSuccessfulCheck: now.subtract(const Duration(hours: 25)),
          now: now,
        ),
        isTrue,
      );
    });

    test('שבועי - לא בודקים בתוך 7 ימים, בודקים אחריהם', () {
      expect(
        shouldCheckForUpdatesNow(
          frequency: UpdateCheckFrequency.weekly,
          lastSuccessfulCheck: now.subtract(const Duration(days: 6)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldCheckForUpdatesNow(
          frequency: UpdateCheckFrequency.weekly,
          lastSuccessfulCheck: now.subtract(const Duration(days: 8)),
          now: now,
        ),
        isTrue,
      );
    });

    test('חותמת עתידית (שעון שהוזז אחורה) אינה חוסמת בדיקות', () {
      expect(
        shouldCheckForUpdatesNow(
          frequency: UpdateCheckFrequency.weekly,
          lastSuccessfulCheck: now.add(const Duration(days: 3)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
