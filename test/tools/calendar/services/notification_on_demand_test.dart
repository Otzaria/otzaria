import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_scheduler.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

class _Settings implements SettingsRepository {
  String ids = '[]';

  @override
  String getCalendarEventNotificationIdsJson() => ids;

  @override
  Future<void> updateCalendarEventNotificationIdsJson(String value) async =>
      ids = value;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _now = DateTime(2026, 10, 20, 9);

CustomEvent _event(String id) => CustomEvent(
  id: id,
  title: 'אירוע',
  description: '',
  createdAt: _now,
  baseGregorianDate: DateTime(2026, 10, 25),
  baseJewishYear: 5787,
  baseJewishMonth: 8,
  baseJewishDay: 14,
  recurrenceType: RecurrenceType.none,
  recurringYears: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  String? failingMethod;

  late _Settings settings;
  late CalendarAlertScheduler scheduler;
  final service = NotificationService();

  Iterable<String> methods() => calls.map((call) => call.method);
  List<Object?> cancelledIds() => [
    for (final call in calls)
      if (call.method == 'cancel') call.arguments,
  ];

  Future<void> rescheduleEvents(List<CustomEvent> events) =>
      scheduler.rescheduleEventNotifications(
        events: () => events,
        enabled: () => true,
        defaultMinutes: () => 15,
        soundEnabled: () => true,
      );

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    FlutterLocalNotificationsPlatform.instance =
        MacOSFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == failingMethod) {
            throw PlatformException(code: 'unavailable');
          }
          return true;
        });
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  setUp(() {
    service.resetForTesting();
    NotificationService.startupGate = null;
    NotificationService.ownerChannelForTesting = null;
    calls.clear();
    failingMethod = null;
    settings = _Settings();
    scheduler = CalendarAlertScheduler(
      notifications: service,
      settings: settings,
      now: () => _now,
    );
  });

  test('תזכורת לאירוע חדש מאתחלת לפי דרישה ומתוזמנת בפועל', () async {
    await rescheduleEvents([_event('a')]);

    expect(methods(), containsAllInOrder(['initialize', 'zonedSchedule']));
    expect(jsonDecode(settings.ids), ['a'.hashCode]);
  });

  test('מחיקת אירוע מבטלת את ההתראה שכבר במערכת', () async {
    settings.ids = '[5]';

    await rescheduleEvents(const []);

    expect(cancelledIds(), [5]);
    expect(settings.ids, '[]');
  });

  test('חלון זמני היום מתארך גם כשההתראות טרם אותחלו', () async {
    await scheduler.rescheduleZmanAlerts(const {
      'sunrise': ZmanAlertPreference(minutesBefore: 15, displayName: 'הנץ'),
    }, 'ירושלים');

    expect(methods().where((m) => m == 'zonedSchedule'), hasLength(46));
  });

  test('בלי מה לתזמן או לבטל — אין אתחול נייטיבי', () async {
    await rescheduleEvents(const []);
    await scheduler.rescheduleZmanAlerts(const {}, 'ירושלים');

    expect(calls, isEmpty);
    expect(service.isInitialized, isFalse);
  });

  test('תזמון שנכשל אינו נשמר כמזהה', () async {
    failingMethod = 'zonedSchedule';

    await rescheduleEvents([_event('a')]);

    expect(methods(), contains('zonedSchedule'));
    expect(settings.ids, '[]');
  });

  test('האתחול ממתין לשער החשיפה, ומתבצע פעם אחת', () async {
    final reveal = Completer<void>();
    NotificationService.startupGate = () => reveal.future;

    final first = service.ensureInitialized();
    final second = service.ensureInitialized();
    await pumpEventQueue();
    expect(calls, isEmpty);

    reveal.complete();
    expect(await Future.wait([first, second]), [true, true]);
    expect(methods().where((m) => m == 'initialize'), hasLength(1));
  });

  group('חלון משני', () {
    var ownerRequests = 0;

    setUp(() {
      ownerRequests = 0;
      // אותו isolate משמש כבעלים; הסבב ב-JSON מוודא שהבקשה ניתנת לשליחה.
      NotificationService.ownerChannelForTesting = (request) async {
        ownerRequests++;
        final sent = jsonDecode(jsonEncode(request)) as Map<String, dynamic>;
        return service.handleOwnerRequest(sent);
      };
    });

    test('תזכורת מתוזמנת דרך החלון הראשי ונשמרת', () async {
      await rescheduleEvents([_event('a')]);

      expect(ownerRequests, greaterThan(0));
      expect(methods(), containsAllInOrder(['initialize', 'zonedSchedule']));
      expect(jsonDecode(settings.ids), ['a'.hashCode]);
    });

    test('ביטול מועבר לחלון הראשי', () async {
      settings.ids = '[5]';

      await rescheduleEvents(const []);

      expect(cancelledIds(), [5]);
      expect(settings.ids, '[]');
    });

    test('הבקשה עוברת באפיק החלונות האמיתי', () async {
      WindowBus.namespace = 'otzaria.test.notifications';
      WindowBus.instance.register(asOwner: true);
      WindowBus.instance.onRequest = (request) async =>
          request['type'] == NotificationService.busRequest
          ? service.handleOwnerRequest(request)
          : null;
      addTearDown(() {
        WindowBus.instance.onRequest = null;
        WindowBus.instance.unregister();
        WindowBus.namespace = 'otzaria.window';
      });
      NotificationService.forwardToOwnerWindow();

      await rescheduleEvents([_event('a')]);

      expect(methods(), containsAllInOrder(['initialize', 'zonedSchedule']));
      expect(jsonDecode(settings.ids), ['a'.hashCode]);
    });

    test('בלי חלון ראשי המזהים השמורים נשארים לניסיון הבא', () async {
      NotificationService.ownerChannelForTesting = (_) async =>
          throw StateError('Main window unavailable');
      settings.ids = '[5]';

      await rescheduleEvents([_event('a')]);

      expect(calls, isEmpty);
      expect(settings.ids, '[5]');
    });
  });
}
