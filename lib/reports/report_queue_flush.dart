import 'dart:async';

import 'package:otzaria/core/error_log_file.dart';

/// מתזמן שליחה מהתור ומאפשר הרצת שליחה אחת בכל פעם.
class ReportQueueFlush {
  static const _interval = Duration(minutes: 5);

  Timer? _timer;
  Completer<void>? _inFlight;
  bool _failureLogged = false;

  /// מחזיר 0 אם כבר מתבצעת שליחה מהתור.
  Future<int> run(Future<int> Function() flush) async {
    if (_inFlight != null) return 0;
    final inFlight = _inFlight = Completer<void>();
    try {
      final sent = await flush();
      _failureLogged = false;
      return sent;
    } finally {
      _inFlight = null;
      inFlight.complete();
    }
  }

  /// שליחה ברקע: כשל (למשל שגיאת דיסק) נרשם ליומן פעם אחת עד לשליחה מוצלחת
  /// ואינו יוצא כשגיאה לא מטופלת; הדיווחים נשארים בתור לסבב הבא.
  void runInBackground(Future<int> Function() flush) {
    unawaited(
      flush().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (_failureLogged) return;
          _failureLogged = true;
          try {
            ErrorLogFile.appendInBackground(
              title: 'שליחת דיווחים מהתור נכשלה',
              error: error,
              stackTrace: stackTrace,
            );
          } catch (_) {}
        },
      ),
    );
  }

  /// מפעיל שליחה מיידית ואחת לחמש דקות. קריאה חוזרת אינה יוצרת טיימר נוסף.
  void start(Future<int> Function() flush) {
    if (_timer != null) return;
    runInBackground(flush);
    _timer = Timer.periodic(_interval, (_) => runInBackground(flush));
  }

  /// מבטל את הטיימר וממתין לשליחה שכבר התחילה, לפני שחזור מגיבוי.
  Future<void> suspend() async {
    _timer?.cancel();
    _timer = null;
    await _inFlight?.future;
  }
}
