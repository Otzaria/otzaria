import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class _Settings implements SettingsRepository {
  @override
  Future<Map<String, dynamic>> loadSettings() async => {
    'calendarType': 'combined',
    'selectedCity': 'ירושלים',
    'calendarEvents': '[]',
    'calendarNotificationsEnabled': false,
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
  Future<void> updateCalendarZmanAlertsJson(String json) async {}

  @override
  String getCalendarEventNotificationIdsJson() => '[]';

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String json) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Scheduled {
  _Scheduled(this.id, this.title, this.body, this.eventDate, this.minutes);

  final int id;
  final String title;
  final String body;
  final DateTime eventDate;
  final int minutes;
}

class _RecordingNotifications implements NotificationService {
  final scheduled = <_Scheduled>[];
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
    scheduled.add(_Scheduled(id, title, body, eventDate, reminderMinutes));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  late _RecordingNotifications notifications;
  late CalendarCubit cubit;

  setUp(() async {
    notifications = _RecordingNotifications();
    cubit = CalendarCubit(
      settingsRepository: _Settings(),
      notificationService: notifications,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() => cubit.close());

  test('a zman alert is scheduled for each day of the window', () async {
    await cubit.setZmanAlertPreference(
      timeId: 'sunrise',
      displayName: 'הנץ החמה',
      minutesBefore: 15,
    );

    final scheduled = notifications.scheduled;
    expect(scheduled.length, 46);
    expect(scheduled.map((s) => s.id).toSet(), hasLength(46));
    expect(scheduled.every((s) => s.title == 'תזכורת: הנץ החמה'), isTrue);
    expect(scheduled.every((s) => s.minutes == 15), isTrue);
    expect(scheduled.first.body, startsWith('בעוד 15 דקות הנץ החמה ('));

    final first = scheduled.first.eventDate as tz.TZDateTime;
    final now = DateTime.now();
    expect(first.location.name, 'Asia/Jerusalem');
    expect(
      DateTime(first.year, first.month, first.day),
      DateTime(now.year, now.month, now.day),
    );
  });

  test('cancelling a zman alert cancels the whole window', () async {
    await cubit.setZmanAlertPreference(
      timeId: 'sunrise',
      displayName: 'הנץ החמה',
      minutesBefore: 15,
    );
    final ids = notifications.scheduled.map((s) => s.id).toSet();
    notifications.cancelled.clear();

    await cubit.cancelZmanAlertPreference(timeId: 'sunrise');

    expect(notifications.cancelled.toSet(), ids);
    expect(cubit.state.zmanAlerts, isEmpty);
  });
}
