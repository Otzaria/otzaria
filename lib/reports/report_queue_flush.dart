import 'dart:async';

/// מתזמן שליחה מהתור ומאפשר הרצת שליחה אחת בכל פעם.
class ReportQueueFlush {
  static const _interval = Duration(minutes: 5);

  Timer? _timer;
  Completer<void>? _inFlight;

  /// מחזיר 0 אם כבר מתבצעת שליחה מהתור.
  Future<int> run(Future<int> Function() flush) async {
    if (_inFlight != null) return 0;
    final inFlight = _inFlight = Completer<void>();
    try {
      return await flush();
    } finally {
      _inFlight = null;
      inFlight.complete();
    }
  }

  /// מפעיל שליחה מיידית ואחת לחמש דקות. קריאה חוזרת אינה יוצרת טיימר נוסף.
  void start(Future<int> Function() flush) {
    if (_timer != null) return;
    unawaited(flush());
    _timer = Timer.periodic(_interval, (_) => unawaited(flush()));
  }

  /// מבטל את הטיימר וממתין לשליחה שכבר התחילה, לפני שחזור מגיבוי.
  Future<void> suspend() async {
    _timer?.cancel();
    _timer = null;
    await _inFlight?.future;
  }
}
