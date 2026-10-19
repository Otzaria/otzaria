import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

final _now = DateTime(2026, 10, 2);

class _Settings implements SettingsRepository {
  String notificationIds = '[7]';

  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': true,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': true,
    'calendarZmanAlerts': jsonEncode({
      'sunrise': const ZmanAlertPreference(
        minutesBefore: 15,
        displayName: 'הנץ',
      ).toJson(),
    }),
    'calendarEnabledZmanim': '',
    'calendarDayTransition': 'sunset',
    'googleCalendarEnabled': false,
    'googleCalendarSelectedIds': 'primary',
    'googleCalendarSyncPastDays': 60,
    'googleCalendarSyncFutureDays': 365,
    'googleCalendarLastSync': 0,
  };

  @override
  String getCalendarEventNotificationIdsJson() => notificationIds;

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String value) async =>
      notificationIds = value;

  @override
  Future<void> updateCalendarEvents(String value) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Plugins implements CalendarPluginSource {
  @override
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> events, {
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) async => events;
}

class _Notifications implements NotificationService {
  final scheduled = <int>[];
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
  }) async => scheduled.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  late _Settings settings;
  late _Notifications notifications;

  Future<CalendarCubit> openCalendar() async {
    final cubit = CalendarCubit(
      settingsRepository: settings,
      notificationService: notifications,
      pluginCalendarAdapter: _Plugins(),
      now: () => _now,
    );
    addTearDown(cubit.close);
    await cubit.initialized;
    await pumpEventQueue();
    return cubit;
  }

  setUp(() {
    settings = _Settings();
    notifications = _Notifications();
  });

  tearDown(() => WindowRole.isSecondary = false);

  test('החלון הראשי משחזר בעלייה את התזמונים השמורים', () async {
    await openCalendar();

    expect(notifications.cancelled, contains(7));
    expect(notifications.scheduled, isNotEmpty);
    expect(settings.notificationIds, '[]');
  });

  test('חלון משני אינו משחזר בעלייה ואינו נוגע במזהים', () async {
    WindowRole.isSecondary = true;

    await openCalendar();

    expect(notifications.cancelled, isEmpty);
    expect(notifications.scheduled, isEmpty);
    expect(settings.notificationIds, '[7]');
  });

  test('אירוע שנוסף בחלון משני מתוזמן', () async {
    WindowRole.isSecondary = true;
    settings.notificationIds = '[]';
    final cubit = await openCalendar();

    await cubit.addEvent(
      title: 'שיעור',
      baseGregorianDate: DateTime(2026, 10, 5),
      recurrenceType: RecurrenceType.none,
    );
    await pumpEventQueue();

    expect(notifications.scheduled, hasLength(1));
    expect(jsonDecode(settings.notificationIds), notifications.scheduled);
  });
}
