import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

final _now = DateTime(2026, 10, 2);

class _Settings implements SettingsRepository {
  String notificationIds = '[]';
  final firstScheduleSaved = Completer<void>();
  final secondScheduleSaved = Completer<void>();

  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': jsonEncode([
      CustomEvent(
        id: 'event',
        title: 'אירוע עתידי',
        description: '',
        createdAt: _now,
        baseGregorianDate: DateTime(2026, 10, 5),
        baseJewishYear: 5787,
        baseJewishMonth: 7,
        baseJewishDay: 24,
        recurrenceType: RecurrenceType.none,
        recurringYears: null,
      ).toJson(),
    ]),
    'calendarNotificationsEnabled': true,
    'calendarNotificationTime': 60,
    'calendarNotificationSound': false,
    'calendarZmanAlerts': '{}',
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
  Future<void> updateCalendarEventNotificationIdsJson(String value) async {
    notificationIds = value;
    if (!firstScheduleSaved.isCompleted) {
      firstScheduleSaved.complete();
    } else if (!secondScheduleSaved.isCompleted) {
      secondScheduleSaved.complete();
    }
  }

  @override
  Future<void> updateCalendarEvents(String value) async {}

  @override
  Future<void> updateCalendarNotificationTime(int value) async {}

  @override
  Future<void> updateCalendarNotificationsEnabled(bool value) async {}

  @override
  Future<void> updateCalendarNotificationSound(bool value) async {}

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
  final cancellationStarted = Completer<void>();
  final releaseCancellation = Completer<void>();
  final scheduled = <({int minutes, bool sound})>[];
  bool holdCancellation = false;
  int cancellations = 0;

  @override
  bool get isInitialized => true;

  @override
  Future<bool> checkPermissions() async => true;

  @override
  Future<void> cancelNotification(int id) async {
    if (holdCancellation && ++cancellations == 1) {
      cancellationStarted.complete();
      await releaseCancellation.future;
    }
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async => scheduled.add((minutes: reminderMinutes, sound: soundEnabled));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  late _Settings settings;
  late _Notifications notifications;
  late CalendarCubit cubit;

  setUp(() async {
    settings = _Settings();
    notifications = _Notifications();
    cubit = CalendarCubit(
      settingsRepository: settings,
      notificationService: notifications,
      pluginCalendarAdapter: _Plugins(),
      now: () => _now,
    );
    await settings.firstScheduleSaved.future;
    notifications.scheduled.clear();
    notifications.holdCancellation = true;
  });

  tearDown(() async {
    if (!notifications.releaseCancellation.isCompleted) {
      notifications.releaseCancellation.complete();
    }
    await cubit.close();
  });

  test('disabling notifications during cancellation stays disabled', () async {
    final olderReschedule = cubit.changeCalendarNotificationTime(15);
    await notifications.cancellationStarted.future;
    final disabling = cubit.changeCalendarNotificationsEnabled(false);
    notifications.releaseCancellation.complete();
    await olderReschedule;
    await disabling;

    expect(cubit.state.calendarNotificationsEnabled, isFalse);
    expect(notifications.scheduled, isEmpty);
    expect(settings.notificationIds, '[]');
  });

  test(
    'deleting an event during cancellation keeps its reminder deleted',
    () async {
      final olderReschedule = cubit.changeCalendarNotificationTime(15);
      await notifications.cancellationStarted.future;
      final deleting = cubit.deleteEvent('event');
      notifications.releaseCancellation.complete();
      await olderReschedule;
      await deleting;

      expect(cubit.state.events, isEmpty);
      expect(notifications.scheduled, isEmpty);
      expect(settings.notificationIds, '[]');
    },
  );

  test('rescheduling after cancellation uses current time and sound', () async {
    final olderReschedule = cubit.changeCalendarNotificationTime(15);
    await notifications.cancellationStarted.future;
    final newer = cubit.changeCalendarNotificationTime(20);
    await cubit.changeCalendarNotificationSound(true);
    notifications.releaseCancellation.complete();
    await olderReschedule;
    await newer;

    expect(cubit.state.calendarNotificationTime, 20);
    expect(cubit.state.calendarNotificationSound, isTrue);
    // הריצה הישנה ממשיכה עם הערכים העדכניים, ואחריה הריצה הממוזגת.
    expect(notifications.scheduled, [
      (minutes: 20, sound: true),
      (minutes: 20, sound: true),
    ]);
  });
}
