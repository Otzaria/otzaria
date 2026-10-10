import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

class _DesktopNotifications extends FlutterLocalNotificationsPlatform
    implements
        LinuxFlutterLocalNotificationsPlugin,
        FlutterLocalNotificationsWindows {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
  }) async => throw UnimplementedError();

  final calls = <String>[];
  bool failInitialization = false;
  bool failCancellation = false;

  @override
  Future<bool> initialize({
    required Object settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    calls.add('initialize');
    if (failInitialization) throw StateError('unavailable');
    return true;
  }

  @override
  Future<void> cancel({required int id}) async {
    calls.add('cancel:$id');
    if (failCancellation) throw StateError('unavailable');
  }
}

void main({bool windows = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final plugin = _DesktopNotifications();
  final notifications = NotificationService();

  setUpAll(() {
    debugDefaultTargetPlatformOverride = windows
        ? TargetPlatform.windows
        : TargetPlatform.linux;
    FlutterLocalNotificationsPlatform.instance = plugin;
  });
  setUp(() {
    plugin.calls.clear();
    plugin.failInitialization = false;
    plugin.failCancellation = false;
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  test('רשימה ריקה אינה מאתחלת את השירות', () async {
    await notifications.cancelNotifications([]);
    expect(plugin.calls, isEmpty);
    expect(notifications.isInitialized, isFalse);
  });

  test('כשל באתחול מגיע לקורא ואפשר לנסות שוב', () async {
    plugin.failInitialization = true;
    await expectLater(notifications.cancelNotifications([7]), throwsStateError);
    expect(plugin.calls, ['initialize']);
    expect(notifications.isInitialized, isFalse);
  });

  test('ביטול במחשב מאתחל פעם אחת לפני ביטול כל המזהים', () async {
    await notifications.cancelNotifications([7, 11]);
    await notifications.cancelNotifications([12]);
    expect(plugin.calls, ['initialize', 'cancel:7', 'cancel:11', 'cancel:12']);
    expect(notifications.isInitialized, isTrue);
  });

  test('כשל ביטול מגיע לקורא ושומר את השירות מאותחל', () async {
    plugin.failCancellation = true;
    await expectLater(notifications.cancelNotifications([7]), throwsStateError);
    expect(plugin.calls, ['cancel:7']);
    expect(notifications.isInitialized, isTrue);
  });
}
