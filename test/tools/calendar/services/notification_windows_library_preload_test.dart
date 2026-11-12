import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

class _WindowsNotifications extends FlutterLocalNotificationsPlatform
    implements
        LinuxFlutterLocalNotificationsPlugin,
        FlutterLocalNotificationsWindows {
  _WindowsNotifications(this.calls);

  final List<String> calls;
  bool initializationResult = true;

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

  @override
  Future<bool> initialize({
    required Object settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async {
    calls.add('initialize');
    return initializationResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  final originalPreload = NotificationService.windowsLibraryPreload;
  final originalGate = NotificationService.startupGate;
  late _WindowsNotifications plugin;

  setUp(() {
    calls.clear();
    NotificationService().resetForTesting();
    plugin = _WindowsNotifications(calls);
    FlutterLocalNotificationsPlatform.instance = plugin;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    NotificationService.windowsLibraryPreload = originalPreload;
    NotificationService.startupGate = originalGate;
  });

  test('ב-Windows ה-DLL נטען לפני initialize של התוסף', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final preload = Completer<void>();
    NotificationService.windowsLibraryPreload = () {
      calls.add('preload');
      return preload.future;
    };

    final init = NotificationService().init();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['preload']);

    preload.complete();
    await init;
    expect(calls, ['preload', 'initialize']);
  });

  test('הטעינה מראש של ברירת המחדל לא זורקת בשום מערכת', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await expectLater(originalPreload(), completes);
  });

  test('בלי Windows אין טעינה מראש', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    NotificationService.windowsLibraryPreload = () async {
      calls.add('preload');
    };

    await NotificationService().init();
    expect(calls, ['initialize']);
  });

  test('כשל רישום ב-Windows אינו מסמן הצלחה ומאפשר ניסיון נוסף', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    NotificationService.windowsLibraryPreload = () async {};
    plugin.initializationResult = false;
    final notifications = NotificationService();

    expect(await notifications.ensureInitialized(), isFalse);
    expect(notifications.isInitialized, isFalse);

    plugin.initializationResult = true;
    expect(await notifications.ensureInitialized(), isTrue);
    expect(notifications.isInitialized, isTrue);
    expect(calls, ['initialize', 'initialize']);
  });

  test('קריאות מקבילות חולקות רישום כושל וממתינות לחשיפת החלון', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    NotificationService.windowsLibraryPreload = () async {};
    plugin.initializationResult = false;
    final reveal = Completer<void>();
    NotificationService.startupGate = () => reveal.future;
    final notifications = NotificationService();
    final first = notifications.ensureInitialized();
    final second = notifications.ensureInitialized();
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);

    reveal.complete();
    expect(await Future.wait([first, second]), [false, false]);
    expect(calls, ['initialize']);
    expect(notifications.isInitialized, isFalse);
  });

  test('false בפלטפורמה אחרת משמר את חוזה האתחול הקיים', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    plugin.initializationResult = false;

    expect(await NotificationService().ensureInitialized(), isTrue);
    expect(calls, ['initialize']);
  });
}
