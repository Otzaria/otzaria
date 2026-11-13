import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// תוסף Windows מדומה ששומר את פרטי ה-Windows של כל התראה מתוזמנת.
class _WindowsNotifications extends FlutterLocalNotificationsPlatform
    implements FlutterLocalNotificationsWindows {
  final scheduled = <WindowsNotificationDetails?>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> initialize({
    required Object settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    Object? notificationDetails,
    String? payload,
  }) async => throw UnimplementedError();

  @override
  Future<void> periodicallyShow({
    required int id,
    required RepeatInterval repeatInterval,
    String? title,
    String? body,
    Object? notificationDetails,
    String? payload,
  }) async => throw UnimplementedError();

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    String? title,
    String? body,
    Object? notificationDetails,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async => scheduled.add(notificationDetails as WindowsNotificationDetails?);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plugin = _WindowsNotifications();
  final originalPreload = NotificationService.windowsLibraryPreload;

  setUp(() {
    plugin.scheduled.clear();
    NotificationService().resetForTesting();
    NotificationService.windowsLibraryPreload = () async {};
    FlutterLocalNotificationsPlatform.instance = plugin;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    NotificationService.windowsLibraryPreload = originalPreload;
  });

  Future<WindowsNotificationDetails?> schedule({
    required bool soundEnabled,
  }) async {
    await NotificationService().scheduleNotification(
      id: 7,
      title: 'תזכורת',
      body: 'אירוע',
      eventDate: DateTime.now().add(const Duration(days: 1)),
      reminderMinutes: 0,
      soundEnabled: soundEnabled,
    );
    return plugin.scheduled.last;
  }

  test(
    'ב-Windows "שקט" מתזמן התראה בלי צליל, ו"צליל" נשאר עם צליל המערכת (issue #3629)',
    () async {
      final sound = await schedule(soundEnabled: true);
      final silent = await schedule(soundEnabled: false);

      // בלי audio נשמע צליל ברירת המחדל של Windows.
      expect(sound, isNotNull);
      expect(sound!.audio, isNull);
      expect(silent?.audio?.isSilent, isTrue);
    },
  );
}
