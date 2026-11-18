import 'dart:collection';

import 'package:flutter/foundation.dart';

/// אירועי פתיחה, הצגה וכשל של חלונות Dart, בזיכרון בלבד, למפתח `windows`
/// בדוח. חלון שנתקע ונסגר לפני הדיווח עדיין מופיע כאן.
class WindowEventLog {
  WindowEventLog({this.capacity = 40, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static WindowEventLog instance = WindowEventLog();

  final int capacity;
  final DateTime Function() _now;
  final ListQueue<Map<String, Object?>> _events = ListQueue();

  void add(String event, [Map<String, Object?> details = const {}]) {
    _events.addLast({
      'at': _now().toUtc().toIso8601String(),
      'event': event,
      ...details,
    });
    while (_events.length > capacity) {
      _events.removeFirst();
    }
  }

  /// מהישן לחדש, כדי שרצף פתיחה אחת ייקרא לפי הסדר.
  List<Map<String, Object?>> collect() => _events.toList();

  @visibleForTesting
  void clear() => _events.clear();
}
