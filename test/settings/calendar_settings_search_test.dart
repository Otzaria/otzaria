import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/panels/calendar_settings_panel.dart';
import 'package:otzaria/settings/search/settings_search_index.g.dart';

void main() {
  test('חיפוש התראות, ICS ו-Google מפנה לכרטיס אירועים ותזכורות', () {
    for (final id in [
      'tools.calendar.notifications',
      'tools.calendar.test_notification',
      'tools.calendar.ics_import',
      'tools.calendar.google_calendar',
    ]) {
      final entry = kGeneratedSettingsSearchEntries.singleWhere(
        (entry) => entry.id == id,
      );
      expect(entry.cardId, CalendarSettingsTab.eventsCardId, reason: id);
    }
  });
}
