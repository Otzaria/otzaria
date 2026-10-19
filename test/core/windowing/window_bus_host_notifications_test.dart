import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_bus_host.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.bushost.notifications';

class _Window extends Fake implements AppWindowController, AppWindowGeometry {
  @override
  final AppWindowId id = const AppWindowId('test-window');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final methods = <String>[];

  setUp(() {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = _namespace;
    FlutterLocalNotificationsPlatform.instance =
        MacOSFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          return true;
        });
    NotificationService().resetForTesting();
    methods.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    MultiWindowService.debugSupportedOverride = null;
  });

  testWidgets('תזמון מחלון משני מבוצע על ידי WindowBusHost של הבעלים', (
    tester,
  ) async {
    final window = _Window();
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    // ⚠️ testWidgets דורש לאפס את ה-override בתוך גוף הבדיקה.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final reply = await tester.runAsync(
      () => WindowBus.instance.onRequest!({
        'type': NotificationService.busRequest,
        'op': 'schedule',
        'id': 9,
        'title': 't',
        'body': 'b',
        'eventDate': DateTime.now()
            .add(const Duration(days: 1))
            .microsecondsSinceEpoch,
        'reminderMinutes': 0,
        'soundEnabled': true,
      }),
    );

    expect(reply, containsPair('value', true));
    debugDefaultTargetPlatformOverride = null;
    expect(methods, containsAllInOrder(['initialize', 'zonedSchedule']));
  });
}
