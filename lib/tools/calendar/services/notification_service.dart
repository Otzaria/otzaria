import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/foundation.dart';

/// התראות המערכת של התהליך. התוסף הנייטיבי מאותחל רק לפי דרישה, בחלון
/// הבעלים בלבד; חלון משני מעביר אליו כל פעולה דרך [WindowBus].
class NotificationService {
  static final NotificationService _notificationService =
      NotificationService._internal();

  factory NotificationService() {
    return _notificationService;
  }

  NotificationService._internal();

  /// סוג הבקשה באפיק החלונות לפעולות התראה שחלון משני מעביר לבעלים.
  static const String busRequest = 'notifications';

  /// כל אתחול ממתין לשער הזה (חשיפת החלון הראשי), כדי שלא ייכנס לנתיב העלייה.
  /// ⚠️ ב-Windows ה-COM רץ ב-thread של הפורק; אסור לחזור לגרסה שמריצה אותו כאן (#1192).
  static Future<void> Function()? startupGate;

  static Future<Object?> Function(Map<String, Object?> request)? _ownerChannel;

  /// מנתב את כל הפעולות לחלון הבעלים: אתחול שני של התוסף באותו תהליך היה
  /// רושם את אותו מזהה אפליקציה פעמיים.
  static void forwardToOwnerWindow() {
    _ownerChannel = (request) async {
      final owner = WindowBus.instance.ownerPort;
      if (owner == null) throw StateError('Main window unavailable');
      final response = await WindowBus.instance.requestPortDetailed(
        owner,
        {'type': busRequest, ...request},
        // הבעלים עשוי להיות עסוק (טעינת קטלוג נמדדה ~2 שניות).
        timeout: const Duration(seconds: 10),
        label: 'owner notifications',
      );
      if (response.failure != null) {
        throw StateError('Main window notifications: ${response.failure}');
      }
      return response.result;
    };
  }

  @visibleForTesting
  static set ownerChannelForTesting(
    Future<Object?> Function(Map<String, Object?> request)? channel,
  ) => _ownerChannel = channel;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _permissionsGranted = false;
  bool _isInitialized = false;
  Future<bool>? _pendingInit;

  @visibleForTesting
  void resetForTesting() {
    _permissionsGranted = false;
    _isInitialized = false;
    _pendingInit = null;
  }

  /// מאתחל את מסד אזורי הזמן וקובע את אזור הזמן המקומי.
  ///
  /// חלון משני צריך אזור זמן אך אסור לו לאתחל התראות מערכת.
  static void initializeTimeZones() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
  }

  /// מאתחל את התוסף אם טרם אותחל, אחרי [startupGate]. מחזיר האם הוא זמין.
  ///
  /// קוראים לזה רק לפני תזמון או ביטול אמיתי, כדי שמי שאינו משתמש בהתראות
  /// לא ישלם על האתחול הנייטיבי.
  Future<bool> ensureInitialized() async {
    if (_ownerChannel != null) {
      return await _forward('ensureInitialized') == true;
    }
    return _ensureInitializedLocally();
  }

  Future<bool> _ensureInitializedLocally() async {
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
      _logInitFailure(error, stackTrace);
    }
    return _isInitialized;
  }

  static void _logInitFailure(Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('Notification service initialization failed: $error');
      return;
    }
    try {
      ErrorLogFile.append(
        title: 'אתחול שירות ההתראות נכשל',
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
    if (_ownerChannel != null) {
      return await _forward('ensureReadyToCancel') == true;
    }
    return _ensureReadyToCancelLocally();
  }

  static bool get _cancelRequiresInit =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  /// שולח פעולה לחלון הבעלים ומעדכן את המצב המקומי לפי תשובתו.
  Future<Object?> _forward(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    final Object? reply;
    try {
      reply = await _ownerChannel!({'op': op, ...args});
    } catch (error) {
      debugPrint('NotificationService: $op via main window failed: $error');
      if (op == 'ensureInitialized' || op == 'ensureReadyToCancel') {
        return false;
      }
      rethrow;
    }
    if (reply is! Map) throw StateError('Main window ignored notification $op');
    _isInitialized = reply['initialized'] == true;
    _permissionsGranted = reply['permissions'] == true;
    return reply['value'];
  }

  /// מבצע בחלון הבעלים פעולה שחלון משני העביר. חריגה חוזרת לשולח ככשל.
  Future<Object?> handleOwnerRequest(Map<String, dynamic> request) async {
    final Object? value;
    switch (request['op']) {
      case 'ensureInitialized':
        value = await _ensureInitializedLocally();
      case 'ensureReadyToCancel':
        value = await _ensureReadyToCancelLocally();
      case 'checkPermissions':
        value = await _checkPermissionsLocally();
      case 'requestPermissions':
        value = await _requestPermissionsLocally();
      case 'forceRequestPermissions':
        value = await _forceRequestPermissionsLocally();
      case 'schedule':
        await _scheduleLocally(
          id: request['id'] as int,
          title: request['title'] as String,
          body: request['body'] as String,
          eventDate: DateTime.fromMicrosecondsSinceEpoch(
            request['eventDate'] as int,
          ),
          reminderMinutes: request['reminderMinutes'] as int,
          soundEnabled: request['soundEnabled'] as bool,
        );
        value = true;
      case 'show':
        await _showLocally(
          id: request['id'] as int,
          title: request['title'] as String,
          body: request['body'] as String,
        );
        value = true;
      case 'cancel':
        await _cancelLocally(request['id'] as int);
        value = true;
      case 'cancelMany':
        await _cancelManyLocally((request['ids'] as List).cast<int>());
        value = true;
      case 'sendTest':
        value = await _sendTestLocally();
      default:
        throw ArgumentError.value(request['op'], 'op');
    }
    return {
      'value': value,
      'initialized': _isInitialized,
      'permissions': _permissionsGranted,
    };
  }

  Future<bool> _ensureReadyToCancelLocally() async {
    if (_isInitialized || !_cancelRequiresInit) return true;
    return _ensureInitializedLocally();
  }

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

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );

    _isInitialized = true;

    // Request permissions
    await _requestPermissionsLocally();
  }

  bool get isInitialized => _isInitialized;

  /// בקשות הרשאות התראות ושעון מעורר באנדרואיד חייבות להישלח בנפרד.
  Future<bool> requestPermissions() async {
    if (_ownerChannel != null) {
      return await _forward('requestPermissions') == true;
    }
    return _requestPermissionsLocally();
  }

  Future<bool> _requestPermissionsLocally() async {
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
    if (_ownerChannel != null) {
      return await _forward('checkPermissions') == true;
    }
    return _checkPermissionsLocally();
  }

  Future<bool> _checkPermissionsLocally() async {
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
  @visibleForTesting
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
  /// שהקורא לא ישמור מזהה של התראה שאינה קיימת.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    if (_ownerChannel != null) {
      await _forward('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'eventDate': eventDate.microsecondsSinceEpoch,
        'reminderMinutes': reminderMinutes,
        'soundEnabled': soundEnabled,
      });
      return;
    }
    await _scheduleLocally(
      id: id,
      title: title,
      body: body,
      eventDate: eventDate,
      reminderMinutes: reminderMinutes,
      soundEnabled: soundEnabled,
    );
  }

  Future<void> _scheduleLocally({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    required bool soundEnabled,
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

    const windowsDetails = WindowsNotificationDetails();

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
    if (!await _ensureInitializedLocally()) {
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
    if (_ownerChannel != null) {
      await _forward('show', {'id': id, 'title': title, 'body': body});
      return;
    }
    await _showLocally(id: id, title: title, body: body);
  }

  Future<void> _showLocally({
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

  /// ביטול שכשלונו אינו מדווח. מאתחל לפי הצורך.
  Future<void> cancelNotification(int id) async {
    try {
      if (_ownerChannel != null) {
        await _forward('cancel', {'id': id});
      } else {
        await _cancelLocally(id);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to cancel notification $id: $e');
      }
    }
  }

  Future<void> _cancelLocally(int id) => _cancelManyLocally([id]);

  /// ביטול לפני מחיקת מזהים שמורים: הכשל חייב להגיע למי שמוחק אותם.
  Future<void> cancelNotifications(Iterable<int> ids) async {
    final notificationIds = ids.toList();
    if (notificationIds.isEmpty) return;
    if (_ownerChannel != null) {
      await _forward('cancelMany', {'ids': notificationIds});
      return;
    }
    await _cancelManyLocally(notificationIds);
  }

  Future<void> _cancelManyLocally(List<int> ids) async {
    if (!await _ensureReadyToCancelLocally()) {
      throw StateError('Notification service not initialized');
    }
    for (final id in ids) {
      await flutterLocalNotificationsPlugin.cancel(id: id);
    }
  }

  /// שולח התראת בדיקה למערכת ההפעלה. מחזיר האם השליחה הצליחה.
  Future<bool> sendTestNotification() async {
    if (_ownerChannel != null) {
      try {
        return await _forward('sendTest') == true;
      } catch (_) {
        return false;
      }
    }
    return _sendTestLocally();
  }

  Future<bool> _sendTestLocally() async {
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
    if (_ownerChannel != null) {
      return await _forward('forceRequestPermissions') == true;
    }
    return _forceRequestPermissionsLocally();
  }

  Future<bool> _forceRequestPermissionsLocally() async {
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
    return await _requestPermissionsLocally();
  }
}
