import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _notificationService =
      NotificationService._internal();

  factory NotificationService() {
    return _notificationService;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _permissionsGranted = false;
  bool _isInitialized = false;

  Future<void> init() async {
    try {
      tz.initializeTimeZones();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const LinuxInitializationSettings initializationSettingsLinux =
          LinuxInitializationSettings(defaultActionName: 'Open notification');

      const DarwinInitializationSettings initializationSettingsMacOS =
          DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
        macOS: initializationSettingsMacOS,
        linux: initializationSettingsLinux,
      );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle notification tap
        },
      );

      _isInitialized = true;
      
      // Check permissions after initialization
      _permissionsGranted = await checkPermissions();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to initialize notifications: $e');
      }
      _isInitialized = false;
      _permissionsGranted = false;
    }
  }

  Future<bool> requestPermissions() async {
    if (!_isInitialized) return false;

    try {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        final bool? granted = await androidImplementation?.requestNotificationsPermission();
        _permissionsGranted = granted ?? false;
        
        // Request exact alarm permission for Android 12+ (API level 31+)
        if (_permissionsGranted) {
          try {
            final bool? exactAlarmGranted = await androidImplementation?.requestExactAlarmsPermission();
            if (kDebugMode) {
              debugPrint('Exact alarm permission granted: $exactAlarmGranted');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Failed to request exact alarm permission: $e');
            }
            // Continue without exact alarm permission - notifications will still work but may be less precise
          }
        }
      } else if (Platform.isIOS) {
        final bool? result = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
        _permissionsGranted = result ?? false;
      } else {
        _permissionsGranted = true; // Assume granted for other platforms
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to request permissions: $e');
      }
      _permissionsGranted = false;
    }

    return _permissionsGranted;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized || !_permissionsGranted) return;

    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'otzaria_channel',
        'Otzaria Notifications',
        channelDescription: 'Notifications for Otzaria app',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to show notification: $e');
      }
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    DateTime? scheduledDate,
    String? payload,
    DateTime? eventDate,
    int? reminderMinutes,
    bool? soundEnabled,
  }) async {
    if (!_isInitialized || !_permissionsGranted) return;

    try {
      DateTime scheduleTime;
      if (scheduledDate != null) {
        scheduleTime = scheduledDate;
      } else if (eventDate != null && reminderMinutes != null) {
        scheduleTime = eventDate.subtract(Duration(minutes: reminderMinutes));
      } else {
        return; // No valid schedule time
      }

      // Don't schedule notifications in the past
      if (scheduleTime.isBefore(DateTime.now())) {
        return;
      }

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'otzaria_scheduled_channel',
        'Otzaria Scheduled Notifications',
        channelDescription: 'Scheduled notifications for Otzaria app',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduleTime, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to schedule notification: $e');
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    if (!_isInitialized) return;

    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to cancel notification: $e');
      }
    }
  }

  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;

    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to cancel all notifications: $e');
      }
    }
  }

  Future<bool> checkPermissions() async {
    if (!_isInitialized) return false;

    try {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        final bool? granted = await androidImplementation?.areNotificationsEnabled();
        return granted ?? false;
      } else if (Platform.isIOS) {
        final bool? result = await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions()
            .then((permissions) => permissions != null);
        return result ?? false;
      } else {
        return true; // Assume granted for other platforms
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to check permissions: $e');
      }
      return false;
    }
  }

  bool get isInitialized => _isInitialized;
  bool get permissionsGranted => _permissionsGranted;
}