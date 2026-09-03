import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';

auth.AccessCredentials credentialsWithScopes(List<String> scopes) =>
    auth.AccessCredentials(
      auth.AccessToken(
        'Bearer',
        'token',
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      'refresh-token',
      scopes,
    );

void main() {
  group('GoogleCalendarService scopes', () {
    test('כולל הרשאת אירועים לסנכרון', () {
      expect(
        GoogleCalendarService.scopes,
        contains(cal.CalendarApi.calendarEventsScope),
      );
    });

    // בלי scope לרשימת היומנים calendarList.list מחזיר 403 ובחירת
    // היומנים מציגה תמיד "לא נמצאו לוחות שנה" (issue #1075)
    test('כולל הרשאת קריאה לרשימת היומנים', () {
      expect(
        GoogleCalendarService.scopes,
        contains(cal.CalendarApi.calendarCalendarlistReadonlyScope),
      );
    });
  });

  group('canUseStoredCredentials', () {
    final oldToken = credentialsWithScopes([
      cal.CalendarApi.calendarEventsScope,
    ]);
    final currentToken = credentialsWithScopes(GoogleCalendarService.scopes);

    test('טוקן ישן נדחה בפעולה יזומה כדי לחדש הסכמה', () {
      expect(
        GoogleCalendarService.canUseStoredCredentials(
          oldToken,
          interactive: true,
        ),
        isFalse,
      );
    });

    test('טוקן ישן ממשיך לשמש סנכרון רקע ולא מנתק את החשבון', () {
      expect(
        GoogleCalendarService.canUseStoredCredentials(
          oldToken,
          interactive: false,
        ),
        isTrue,
      );
    });

    test('טוקן מעודכן מתקבל בשני המסלולים', () {
      expect(
        GoogleCalendarService.canUseStoredCredentials(
          currentToken,
          interactive: true,
        ),
        isTrue,
      );
      expect(
        GoogleCalendarService.canUseStoredCredentials(
          currentToken,
          interactive: false,
        ),
        isTrue,
      );
    });

    test('הרשאות רחבות יותר מהנדרש מתקבלות', () {
      final broadToken = credentialsWithScopes([
        ...GoogleCalendarService.scopes,
        'https://www.googleapis.com/auth/userinfo.email',
      ]);
      expect(
        GoogleCalendarService.canUseStoredCredentials(
          broadToken,
          interactive: true,
        ),
        isTrue,
      );
    });
  });
}
