import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/calendar_cubit.dart';
import 'package:otzaria/services/notification_service.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Mock SettingsRepository
class MockSettingsRepository implements SettingsRepository {
  final Map<String, dynamic> _settings = {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': true,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': true,
    'calendarZmanAlerts': '{}',
    'googleCalendarEnabled': false,
    'googleCalendarSelectedIds': 'primary',
    'googleCalendarSyncPastDays': 60,
    'googleCalendarSyncFutureDays': 365,
    'googleCalendarLastSync': 0,
  };

  @override
  Future<Map<String, dynamic>> loadSettings() async => _settings;

  @override
  Future<void> updateCalendarZmanAlertsJson(String json) async {
    _settings['calendarZmanAlerts'] = json;
  }

  @override
  Future<void> updateSelectedCity(String city) async {
    _settings['selectedCity'] = city;
  }

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  // Stubs for other methods to comply with interface
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Mock NotificationService
class MockNotificationService implements NotificationService {
  final List<ScheduledNotification> scheduledNotifications = [];

  @override
  bool get isInitialized => true;

  @override
  Future<bool> checkPermissions() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    scheduledNotifications.add(ScheduledNotification(
      id: id,
      title: title,
      body: body,
      eventDate: eventDate,
      reminderMinutes: reminderMinutes,
    ));
  }

  @override
  Future<void> cancelNotification(int id) async {
    scheduledNotifications.removeWhere((n) => n.id == id);
  }

  // Stubs
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ScheduledNotification {
  final int id;
  final String title;
  final String body;
  final dynamic eventDate; // Can be DateTime or TZDateTime
  final int reminderMinutes;

  ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.eventDate,
    required this.reminderMinutes,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalendarCubit Timezone Tests', () {
    late CalendarCubit calendarCubit;
    late MockSettingsRepository mockSettingsRepository;
    late MockNotificationService mockNotificationService;

    setUp(() {
      tz.initializeTimeZones();
      // Set a default global location to something else to prove we are not just using default
      tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));

      mockSettingsRepository = MockSettingsRepository();
      mockNotificationService = MockNotificationService();
    });

    test('Zman alert is scheduled with correct New York timezone', () async {
      // 1. Initialize Cubit
      calendarCubit = CalendarCubit(
        settingsRepository: mockSettingsRepository,
        notificationService: mockNotificationService,
      );

      // Wait for initialization
      await Future.delayed(const Duration(milliseconds: 100));

      // 2. Change city to New York (Timezone: America/New_York)
      // This should trigger _rescheduleZmanAlerts, but we haven't set any alerts yet.
      await calendarCubit.changeCity('ניו יורק');

      // 3. Set a Zman alert (e.g., sunset)
      await calendarCubit.setZmanAlertPreference(
        timeId: 'sunset',
        displayName: 'שקיעה',
        minutesBefore: 15,
      );

      // Allow async operations to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // 4. Verify notification is scheduled
      // We expect 46 notifications (today + 45 days ahead)
      expect(mockNotificationService.scheduledNotifications.isNotEmpty, true,
          reason: 'Notifications should be scheduled');

      final notification = mockNotificationService.scheduledNotifications.first;

      // 5. Verify the timezone of the scheduled event
      expect(notification.eventDate, isA<tz.TZDateTime>(),
          reason: 'Event date should be TZDateTime');

      final tzDate = notification.eventDate as tz.TZDateTime;
      expect(tzDate.location.name, 'America/New_York',
          reason: 'Location should be New York');

      debugPrint('Scheduled time (New York): $tzDate');
      debugPrint('Location: ${tzDate.location.name}');
    });

    test('Zman alert is scheduled with correct Jerusalem timezone', () async {
      // 1. Initialize Cubit with Jerusalem (default)
      calendarCubit = CalendarCubit(
        settingsRepository: mockSettingsRepository,
        notificationService: mockNotificationService,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // 2. Set a Zman alert
      await calendarCubit.setZmanAlertPreference(
        timeId: 'sunset',
        displayName: 'שקיעה',
        minutesBefore: 15,
      );

      // Allow async operations to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // 3. Verify notification
      expect(mockNotificationService.scheduledNotifications.isNotEmpty, true);

      final notification = mockNotificationService.scheduledNotifications.first;

      final tzDate = notification.eventDate as tz.TZDateTime;
      expect(tzDate.location.name, 'Asia/Jerusalem',
          reason: 'Location should be Jerusalem');

      debugPrint('Scheduled time (Jerusalem): $tzDate');
      debugPrint('Location: ${tzDate.location.name}');
    });
  });
}
