import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/utils/file/windows_library_preload.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';

/// התראות המערכת של התהליך. התוסף הנייטיבי מאותחל רק לפי דרישה, ורק אצל
/// בעלי ההתראות (`CalendarAlertsOwner`); חלון משני אינו נוגע בו.
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
  Future<bool>? _pendingInit;

  /// כל אתחול ממתין לשער הזה (חשיפת החלון הראשי), כדי שלא ייכנס לנתיב העלייה.
  /// ⚠️ ב-Windows ה-COM רץ ב-thread של הפורק; אסור לחזור לגרסה שמריצה אותו כאן (#1192).
  static Future<void> Function()? startupGate;

  /// טוען את ה-DLL של ההתראות ב-Windows לפני `initialize` של התוסף.
  @visibleForTesting
  static Future<void> Function() windowsLibraryPreload = _preloadWindowsLibrary;

  static Future<void> _preloadWindowsLibrary() async {
    if (!Platform.isWindows) return;
    try {
      await Isolate.run(
        () => preloadWindowsLibrary('flutter_local_notifications_windows.dll'),
      );
    } catch (error) {
      // אופטימיזציה בלבד: אם ה-DLL באמת חסר, initialize ידווח על כך.
      debugPrint('Notifications DLL preload failed: $error');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _permissionsGranted = false;
    _isInitialized = false;
    _pendingInit = null;
  }

  /// מאתחל את מסד אזורי הזמן וקובע את אזור הזמן המקומי.
  ///
  /// חלון משני צריך אזור זמן אך אסור לו לאתחל התראות מערכת.
  /// האתחול הראשון כבר מתבצע ב-main; אתחול התראות מאוחר לא צריך לפרוס
  /// ולפענח את כל ה-database מחדש.
  static bool _timeZoneDatabaseReady = false;

  static void initializeTimeZones() {
    if (!_timeZoneDatabaseReady || !tz.timeZoneDatabase.isInitialized) {
      tz.initializeTimeZones();
      _timeZoneDatabaseReady = true;
    }
    // Always restore the app's configured location, even on repeated calls.
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
  }

  /// מאתחל את התוסף אחרי [startupGate] ומחזיר האם הוא זמין. רק לפני תזמון
  /// או ביטול אמיתי, כדי שמי שאינו משתמש בהתראות לא ישלם על האתחול.
  Future<bool> ensureInitialized() async {
    if (_isInitialized) return true;
    // קריאות מקבילות חולקות אתחול אחד; אחרי כשל הקריאה הבאה מנסה שוב.
    final pending = _pendingInit ??= _initAfterGate();
    final initialized = await pending;
    if (!initialized && identical(_pendingInit, pending)) _pendingInit = null;
    return initialized;
  }

  Future<bool> _initAfterGate() async {
    await startupGate?.call();
    try {
      if (!_isInitialized) await init();
    } catch (error, stackTrace) {
      logFailure('אתחול שירות ההתראות נכשל', error, stackTrace);
    }
    return _isInitialized;
  }

  /// רושם כשל התראות ל-errors.txt; ב-debug רק מדפיס.
  static void logFailure(String title, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('$title: $error');
      return;
    }
    try {
      ErrorLogFile.appendInBackground(
        title: title,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      // רישום הוא best-effort.
    }
  }

  /// מוכן לבטל התראות. ב-Windows ובלינוקס הביטול דורש אתחול; בשאר
  /// הפלטפורמות לא, ושם אתחול היה מציג בקשת הרשאות.
  Future<bool> ensureReadyToCancel() async {
    if (_isInitialized || !_cancelRequiresInit) return true;
    return ensureInitialized();
  }

  static bool get _cancelRequiresInit =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// ב-Windows ובלינוקס אין הרשאת התראות לבקש, ולכן אפשר לענות בלי אתחול.
  static bool get grantsWithoutPrompt => _cancelRequiresInit;

  Future<void> init() async {
    initializeTimeZones();

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

    // ה-DynamicLibrary.open של התוסף רץ על ה-UI, וסריקת אנטי-וירוס בו תוקעת אותו;
    // אחרי טעינה ב-isolate עזר המודול כבר טעון, וה-open חוזר מיד.
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await windowsLibraryPreload();
    }

    final initialized = await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
    // ב-iOS false פירושו רק שההרשאות נדחו; ב-Windows הרישום עצמו נכשל.
    if (initialized == false &&
        defaultTargetPlatform == TargetPlatform.windows) {
      throw StateError('Windows notification registration failed');
    }

    _isInitialized = true;

    // Request permissions
    await requestPermissions();
  }

  bool get isInitialized => _isInitialized;

  /// בקשות הרשאות התראות ושעון מעורר באנדרואיד חייבות להישלח בנפרד.
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

  /// מועד ההצגה בפועל: זמן התזכורת, ואם חלון התזכורת כבר התחיל — זמן האירוע
  /// עצמו (דילוג שקט נתפס אצל משתמשים כ"התראות לא עובדות"). null = אין מה לתזמן.
  static DateTime? resolveScheduleTime({
    required DateTime eventDate,
    required int reminderMinutes,
    required DateTime now,
  }) {
    final scheduleTime = eventDate.subtract(Duration(minutes: reminderMinutes));
    if (!scheduleTime.isBefore(now)) return scheduleTime;
    if (eventDate.isAfter(now)) return eventDate;
    return null;
  }

  /// מתזמן התראה, ומאתחל לפי הצורך. זורק כשההתראה לא נמסרה למערכת, כדי
  /// שהקורא לא ירשום מזהה של התראה שאינה קיימת.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    await _requireReadyToShow();

    final scheduleTime = resolveScheduleTime(
      eventDate: eventDate,
      reminderMinutes: reminderMinutes,
      now: DateTime.now(),
    );
    if (scheduleTime == null) {
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

    // בלי audio נשמע צליל ברירת המחדל של Windows.
    final windowsDetails = WindowsNotificationDetails(
      audio: soundEnabled ? null : WindowsNotificationAudio.silent(),
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
      macOS: iOSDetails,
      linux: const LinuxNotificationDetails(),
      windows: windowsDetails,
    );

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
  }

  Future<void> _requireReadyToShow() async {
    if (!await ensureInitialized()) {
      throw StateError('Notification service not initialized');
    }
    if (!_permissionsGranted) {
      throw StateError('Notification permissions not granted');
    }
  }

  /// מציג מיד התראה של תוסף. זורק כשההתראה לא נמסרה למערכת.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await _requireReadyToShow();
    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _pluginNotificationDetails,
    );
  }

  static const _pluginDarwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  static const _pluginNotificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'plugin_channel',
      'התראות תוספים',
      channelDescription: 'התראות מתוספי אוצריא',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    ),
    iOS: _pluginDarwinDetails,
    macOS: _pluginDarwinDetails,
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  /// ביטול לפני מחיקת מזהים רשומים: הכשל חייב להגיע למי שמוחק אותם.
  Future<void> cancelNotifications(Iterable<int> ids) async {
    final notificationIds = ids.toList();
    if (notificationIds.isEmpty) return;
    if (!await ensureReadyToCancel()) {
      throw StateError('Notification service not initialized');
    }
    for (final id in notificationIds) {
      await flutterLocalNotificationsPlugin.cancel(id: id);
    }
  }

  /// מזהי ההתראות שממתינות במערכת, כולל כפילויות. דורש אתחול.
  Future<List<int>> pendingNotificationIds() async {
    if (!await ensureInitialized()) {
      throw StateError('Notification service not initialized');
    }
    final pending = await flutterLocalNotificationsPlugin
        .pendingNotificationRequests();
    return [for (final request in pending) request.id];
  }

  /// שולח התראת בדיקה למערכת ההפעלה. מחזיר האם השליחה הצליחה.
  Future<bool> sendTestNotification() async {
    if (!_isInitialized || !_permissionsGranted) {
      if (kDebugMode) {
        debugPrint(
          'Cannot send test notification: not initialized or no permissions',
        );
      }
      return false;
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
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to send test notification: $e');
      }
      return false;
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
