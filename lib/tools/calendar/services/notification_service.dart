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
    // Initialize timezone database
    tz.initializeTimeZones();
    // Set default timezone to Israel
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open');

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'אוצריא',
          appUserModelId: 'com.otzaria.app',
          guid: 'a8c49f1f-9c5d-4d8e-8b1a-2e3f4a5b6c7d',
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
          macOS: initializationSettingsIOS,
          linux: initializationSettingsLinux,
          windows: initializationSettingsWindows,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    _isInitialized = true;

    // Request permissions
    await requestPermissions();
  }

  bool get isInitialized => _isInitialized;

  /// Request notification permissions (Android 13+ and iOS)
  ///
  /// This function handles the Android permission request issue where requesting
  /// both notification and exact alarm permissions simultaneously could cause
  /// the permission dialog to freeze. The fix includes:
  /// 1. Checking existing permissions before requesting
  /// 2. Adding delay between permission requests
  /// 3. Better error handling for each permission type
  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        try {
          bool notificationGranted = true;
          bool exactAlarmGranted = true;

          // First, check if we can schedule exact notifications (this checks the permission)
          final canScheduleExact = await androidPlugin
              .canScheduleExactNotifications();
          if (kDebugMode) {
            debugPrint('Can schedule exact notifications: $canScheduleExact');
          }

          // Request notification permission for Android 13+ only if needed
          try {
            final notificationResult = await androidPlugin
                .requestNotificationsPermission();
            notificationGranted = notificationResult ?? true;

            if (kDebugMode) {
              debugPrint('Notification permission: $notificationGranted');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error requesting notification permission: $e');
            }
            notificationGranted = false;
          }

          // Add a small delay between permission requests to avoid conflicts
          await Future.delayed(const Duration(milliseconds: 500));

          // Request exact alarm permission for Android 12+ only if not already granted
          if (canScheduleExact != true) {
            try {
              final exactAlarmResult = await androidPlugin
                  .requestExactAlarmsPermission();
              exactAlarmGranted = exactAlarmResult ?? true;

              if (kDebugMode) {
                debugPrint('Exact alarm permission: $exactAlarmGranted');
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Error requesting exact alarm permission: $e');
              }
              exactAlarmGranted = false;
            }
          } else {
            exactAlarmGranted = true;
            if (kDebugMode) {
              debugPrint('Exact alarm permission already granted');
            }
          }

          _permissionsGranted = notificationGranted && exactAlarmGranted;

          if (kDebugMode) {
            debugPrint('All permissions granted: $_permissionsGranted');
          }

          return _permissionsGranted;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error requesting Android permissions: $e');
          }
          _permissionsGranted = false;
          return false;
        }
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      try {
        final iosPlugin = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

        if (iosPlugin != null) {
          if (kDebugMode) {
            debugPrint('Requesting iOS/macOS notification permissions...');
          }

          final granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

          _permissionsGranted = granted ?? false;

          if (kDebugMode) {
            debugPrint(
              'iOS/macOS notification permissions granted: $_permissionsGranted',
            );
          }

          // On macOS, sometimes we need to wait a bit and check again
          if (Platform.isMacOS && !_permissionsGranted) {
            if (kDebugMode) {
              debugPrint(
                'macOS permissions denied, waiting and trying again...',
              );
            }

            await Future.delayed(const Duration(seconds: 1));

            final secondTry = await iosPlugin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );

            _permissionsGranted = secondTry ?? false;

            if (kDebugMode) {
              debugPrint('macOS second attempt result: $_permissionsGranted');
            }
          }

          return _permissionsGranted;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error requesting iOS/macOS permissions: $e');
        }
        _permissionsGranted = false;
        return false;
      }
    }

    // Windows and Linux don't require permissions
    _permissionsGranted = true;
    return true;
  }

  bool get hasPermissions => _permissionsGranted;

  /// Check current permission status without requesting
  Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        try {
          // Check if exact alarm permission is granted
          final exactAlarmGranted = await androidPlugin
              .canScheduleExactNotifications();

          // For notification permission, we assume it's granted if we can check it
          // (there's no direct way to check notification permission status without requesting)

          _permissionsGranted = exactAlarmGranted ?? false;

          if (kDebugMode) {
            debugPrint(
              'Permission check - Can schedule exact: $exactAlarmGranted',
            );
            debugPrint('Permissions granted: $_permissionsGranted');
          }

          return _permissionsGranted;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error checking Android permissions: $e');
          }
          return false;
        }
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      // For iOS/macOS, we need to request permissions to check them
      // There's no separate check method in the plugin
      try {
        final iosPlugin = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

        if (iosPlugin != null) {
          // On macOS, we can try to get current settings
          // If this fails, permissions are likely not granted
          final granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

          _permissionsGranted = granted ?? false;

          if (kDebugMode) {
            debugPrint(
              'iOS/macOS permissions check result: $_permissionsGranted',
            );
          }

          return _permissionsGranted;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error checking iOS/macOS permissions: $e');
        }
        _permissionsGranted = false;
        return false;
      }
    }

    return _permissionsGranted;
  }

  void onDidReceiveNotificationResponse(
    NotificationResponse notificationResponse,
  ) async {
    // Handle notification tapped logic here
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    // Check if initialized before scheduling
    if (!_isInitialized) {
      if (kDebugMode) {
        debugPrint('Cannot schedule notification: service not initialized');
      }
      return;
    }

    // Check permissions before scheduling
    if (!_permissionsGranted) {
      if (kDebugMode) {
        debugPrint('Cannot schedule notification: permissions not granted');
      }
      return;
    }

    final scheduleTime = eventDate.subtract(Duration(minutes: reminderMinutes));

    // Ensure the notification is scheduled for the future
    if (scheduleTime.isBefore(DateTime.now())) {
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'calendar_channel',
      'התראות לוח שנה',
      channelDescription: 'התראות על אירועים בלוח השנה',
      importance: Importance.max,
      priority: Priority.high,
      playSound: soundEnabled,
      icon: '@mipmap/ic_launcher',
    );

    final iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
    );

    const windowsDetails = WindowsNotificationDetails();

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
      macOS: iOSDetails,
      linux: const LinuxNotificationDetails(),
      windows: windowsDetails,
    );

    try {
      // Use exact alarm if permission granted, otherwise fall back to inexact
      final canScheduleExact = Platform.isAndroid
          ? await flutterLocalNotificationsPlugin
                    .resolvePlatformSpecificImplementation<
                      AndroidFlutterLocalNotificationsPlugin
                    >()
                    ?.canScheduleExactNotifications() ??
                false
          : true;

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduleTime, tz.local),
        notificationDetails: notificationDetails,
        matchDateTimeComponents: null,
        androidScheduleMode: canScheduleExact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to schedule notification: $e');
      }
    }
  }

  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> cancelNotification(int id) async {
    if (!_isInitialized) return;
    try {
      await flutterLocalNotificationsPlugin.cancel(id: id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to cancel notification $id: $e');
      }
    }
  }

  /// Test function to verify notifications are working
  /// This sends a test notification to verify system notifications work
  Future<void> sendTestNotification() async {
    if (!_isInitialized || !_permissionsGranted) {
      if (kDebugMode) {
        debugPrint(
          'Cannot send test notification: not initialized or no permissions',
        );
      }
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'test_channel',
      'התראות בדיקה',
      channelDescription: 'התראות לבדיקת המערכת',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const windowsDetails = WindowsNotificationDetails();

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
      macOS: iOSDetails,
      linux: LinuxNotificationDetails(),
      windows: windowsDetails,
    );

    try {
      await flutterLocalNotificationsPlugin.show(
        id: 999, // Test notification ID
        title: 'בדיקת התראות',
        body: 'התראה זו מוצגת במערכת ההפעלה, לא בתוך האפליקציה',
        notificationDetails: notificationDetails,
        payload: null,
      );

      if (kDebugMode) {
        debugPrint('Test notification sent successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to send test notification: $e');
      }
    }
  }

  /// Force re-request permissions (useful for macOS troubleshooting)
  Future<bool> forceRequestPermissions() async {
    if (Platform.isMacOS) {
      if (kDebugMode) {
        debugPrint('Force requesting macOS permissions...');
      }

      final iosPlugin = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      if (iosPlugin != null) {
        try {
          // Try multiple times with different approaches
          for (int i = 0; i < 3; i++) {
            if (kDebugMode) {
              debugPrint('macOS permission attempt ${i + 1}/3');
            }

            final granted = await iosPlugin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );

            if (granted == true) {
              _permissionsGranted = true;
              if (kDebugMode) {
                debugPrint('macOS permissions granted on attempt ${i + 1}');
              }
              return true;
            }

            // Wait between attempts
            if (i < 2) {
              await Future.delayed(Duration(seconds: i + 1));
            }
          }

          if (kDebugMode) {
            debugPrint('All macOS permission attempts failed');
          }
          return false;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error in force request permissions: $e');
          }
          return false;
        }
      }
    }

    // For other platforms, use regular request
    return await requestPermissions();
  }
}
