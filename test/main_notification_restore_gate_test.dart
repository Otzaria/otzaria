import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/main.dart';

void main() {
  group('hasScheduledNotificationsToRestore', () {
    test('בלי התראות שמורות — אין סיבה לאתחל את התוסף', () {
      expect(
        hasScheduledNotificationsToRestore(
          zmanAlertsJson: '{}',
          eventNotificationIdsJson: '[]',
        ),
        isFalse,
      );
    });

    test('ערכים ריקים או פגומים נחשבים כאין-מה-לשחזר', () {
      for (final empty in ['', '  ', 'null', '[]', '{}']) {
        expect(
          hasScheduledNotificationsToRestore(
            zmanAlertsJson: empty,
            eventNotificationIdsJson: empty,
          ),
          isFalse,
          reason: 'ערך "$empty" אינו מצדיק אתחול',
        );
      }
    });

    test('התראת זמן שמורה מחייבת אתחול', () {
      expect(
        hasScheduledNotificationsToRestore(
          zmanAlertsJson: '{"sunrise":{"minutesBefore":10}}',
          eventNotificationIdsJson: '[]',
        ),
        isTrue,
      );
    });

    test('מזהי התראות אירוע שמורים מחייבים אתחול', () {
      expect(
        hasScheduledNotificationsToRestore(
          zmanAlertsJson: '{}',
          eventNotificationIdsJson: '[101,102]',
        ),
        isTrue,
      );
    });
  });
}
