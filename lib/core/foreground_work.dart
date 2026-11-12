import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:otzaria/core/error_log_file.dart';

/// התראת השירות: [channelName] מוצג בהגדרות ההתראות של המערכת.
typedef ForegroundWorkNotice = ({
  String channelName,
  String title,
  String text,
});

/// הצד הנייטיב של [ForegroundWork] — מוזרק לבדיקות.
abstract interface class ForegroundWorkPlatform {
  /// [onTimeout] — המערכת עצרה את השירות (מכסת dataSync באנדרואיד 15);
  /// [onStartFailed] — השירות לא עלה אחרי שהבקשה התקבלה.
  void setHandlers({
    required VoidCallback onTimeout,
    required void Function(String reason) onStartFailed,
  });

  /// [requestPermission] — לבקש הרשאת התראות; רק בפעולה שהמשתמש יזם.
  Future<void> start(
    ForegroundWorkNotice notice, {
    required bool requestPermission,
  });

  Future<void> stop();
}

/// מחזיק שירות חזית באנדרואיד כל עוד יש בעלים, בלי להבטיח רשת ב-Doze.
/// כשל בהפעלת השירות אינו עוצר את העבודה — הוא נרשם ל-errors.txt בלבד.
class ForegroundWork {
  ForegroundWork({
    ForegroundWorkPlatform? platform,
    bool? isAndroid,
    void Function(String stage, Object error, StackTrace? stackTrace)?
    logFailure,
  }) : _platform = platform ?? MethodChannelForegroundWorkPlatform(),
       _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
       _logFailure = logFailure ?? _logToErrorFile;

  static final ForegroundWork instance = ForegroundWork();

  final ForegroundWorkPlatform _platform;
  final bool _isAndroid;
  final void Function(String stage, Object error, StackTrace? stackTrace)
  _logFailure;

  final Map<
    Object,
    ({
      ForegroundWorkNotice notice,
      VoidCallback? onTimeout,
      bool requestPermission,
    })
  >
  _owners = {};
  Future<void> _queue = Future.value();
  bool _running = false;
  bool _handlersSet = false;

  /// מוסיף את [owner] כבעלים; השירות עולה עם הבעלים הראשון.
  /// [userInitiated] — רק אז מבקשים הרשאת התראות (לא בעדכון אוטומטי בעלייה).
  void acquire(
    Object owner, {
    required ForegroundWorkNotice notice,
    VoidCallback? onTimeout,
    bool userInitiated = false,
  }) {
    if (!_isAndroid) return;
    _owners[owner] = (
      notice: notice,
      onTimeout: onTimeout,
      requestPermission: userInitiated,
    );
    _schedule();
  }

  /// מסיר את [owner]; השירות נעצר רק כשאין עוד בעלים.
  void release(Object owner) {
    if (!_isAndroid || _owners.remove(owner) == null) return;
    _schedule();
  }

  /// ממתין לסיום פעולות ההפעלה/העצירה שבתור — לבדיקות.
  @visibleForTesting
  Future<void> get settled => _queue;

  // סדרתי: start ו-stop שנשלחים ברצף מגיעים לנייטיב באותו סדר.
  void _schedule() => _queue = _queue.then((_) => _apply());

  Future<void> _apply() async {
    final owners = _owners.values;
    if (owners.isNotEmpty == _running) return;
    if (owners.isEmpty) {
      _running = false;
      try {
        await _platform.stop();
      } catch (e, st) {
        _logFailure('stop', e, st);
      }
      return;
    }
    if (!_handlersSet) {
      _handlersSet = true;
      _platform.setHandlers(
        onTimeout: _onTimeout,
        onStartFailed: (reason) => _onStartFailed(reason),
      );
    }
    try {
      await _platform.start(
        owners.first.notice,
        requestPermission: owners.any((o) => o.requestPermission),
      );
      _running = true;
    } catch (e, st) {
      _logFailure('start', e, st);
    }
  }

  void _onStartFailed(String reason) {
    _running = false;
    _logFailure('start', reason, null);
  }

  void _onTimeout() {
    _running = false;
    final callbacks = [for (final o in _owners.values) ?o.onTimeout];
    _owners.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  static void _logToErrorFile(String stage, Object error, StackTrace? st) {
    debugPrint('[ForegroundWork] $stage failed: $error');
    try {
      ErrorLogFile.appendInBackground(
        title: 'Foreground service ($stage) — non-fatal',
        error: error,
        stackTrace: st,
      );
    } catch (_) {}
  }
}

/// מימוש דרך `ForegroundWorkChannel.kt`.
class MethodChannelForegroundWorkPlatform implements ForegroundWorkPlatform {
  static const _channel = MethodChannel('otzaria/foreground_work');

  @override
  void setHandlers({
    required VoidCallback onTimeout,
    required void Function(String reason) onStartFailed,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'timeout':
          onTimeout();
        case 'startFailed':
          onStartFailed('${call.arguments}');
      }
    });
  }

  @override
  Future<void> start(
    ForegroundWorkNotice notice, {
    required bool requestPermission,
  }) async {
    await _channel.invokeMethod<void>('start', {
      'channelName': notice.channelName,
      'title': notice.title,
      'text': notice.text,
    });
    // לא ממתינים לדיאלוג: תשובה שלא מגיעה הייתה תוקעת את תור ההפעלה/העצירה.
    if (requestPermission) {
      unawaited(
        _requestNotificationPermission().catchError((Object e) {
          debugPrint('[ForegroundWork] notification permission failed: $e');
        }),
      );
    }
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  // בלי ההרשאה (אנדרואיד 13+) השירות עדיין רץ, רק ההתראה אינה מוצגת.
  static Future<void> _requestNotificationPermission() async {
    final android = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null || await android.areNotificationsEnabled() == true) {
      return;
    }
    await android.requestNotificationsPermission();
  }
}
