import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_scheduler.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

class _Settings implements SettingsRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _RecordingNotifications implements NotificationService {
  final scheduledIds = <int>[];
  final scheduledDates = <DateTime>[];
  final cancelled = <int>[];

  @override
  bool get isInitialized => true;

  @override
  Future<bool> checkPermissions() async => true;

  @override
  Future<void> cancelNotification(int id) async => cancelled.add(id);

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    scheduledIds.add(id);
    scheduledDates.add(eventDate);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // The window from this date crosses the end of daylight saving time in
  // Israel (25.10.2026). The bug shows where the local time zone changes
  // its clock inside the window.
  final now = DateTime(2026, 10, 20, 9);
  const alerts = {
    'sunrise': ZmanAlertPreference(minutesBefore: 15, displayName: 'הנץ החמה'),
  };

  late _RecordingNotifications notifications;
  late CalendarAlertScheduler scheduler;

  setUp(() {
    notifications = _RecordingNotifications();
    scheduler = CalendarAlertScheduler(
      notifications: notifications,
      settings: _Settings(),
      now: () => now,
    );
  });

  test('the zman window schedules each calendar day once', () async {
    await scheduler.rescheduleZmanAlerts(alerts, 'ירושלים');

    final days = [
      for (final date in notifications.scheduledDates)
        DateTime(date.year, date.month, date.day),
    ];
    expect(days, [
      for (var i = 0; i <= 45; i++) DateTime(2026, 10, 20 + i),
    ]);
    expect(notifications.scheduledIds.toSet(), hasLength(46));
  });

  test('cancelling covers every day that was scheduled', () async {
    await scheduler.rescheduleZmanAlerts(alerts, 'ירושלים');
    final scheduled = notifications.scheduledIds.toSet();
    notifications.cancelled.clear();

    await scheduler.cancelZmanAlert('sunrise');

    expect(notifications.cancelled.toSet(), scheduled);
  });
}
