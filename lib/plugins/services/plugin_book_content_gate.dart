import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// מגביל את טעינות הטקסט המלא של ספרים שמקורן בתוספים, וסופר לכל תוסף את
/// קריאות `library.getBookContent` שלו לאבחון שבדוח.
///
/// הקורא של התוכנה לא עובר כאן, כך שתוסף שסורק ספרייה לא מעכב ספר פתוח.
class PluginBookContentGate {
  PluginBookContentGate._();

  /// כל טעינה מחזיקה בזיכרון את הקובץ ואת הטקסט המפוענח שלו; הדיסק לא מרוויח
  /// מיותר משתיים, וזה גם הגבול של קריאות ה-fallback במסד.
  static const int maxConcurrentLoads = 2;

  static int _activeLoads = 0;
  static final Queue<Completer<void>> _waiters = Queue();
  static final Map<String, _CallCounter> _calls = {};

  /// מריץ את [load] כשמתפנה מקום, ומחזיק את המקום עד שהוא מסתיים או עד תום
  /// [timeout], המוקדם מביניהם: טעינה תקועה לא חוסמת את התור לתמיד. ממתין שלא
  /// קיבל מקום עד אז יוצא מהתור עם `error.timeout`, כי קריאת ה-RPC שלו פגה.
  static Future<T> runLoad<T>(
    Future<T> Function() load, {
    required Duration timeout,
  }) async {
    final clock = Stopwatch()..start();
    if (_activeLoads < maxConcurrentLoads) {
      _activeLoads++;
    } else {
      final ticket = Completer<void>();
      _waiters.add(ticket);
      try {
        await ticket.future.timeout(timeout);
      } on TimeoutException {
        // ticket שכבר הוצא מהתור קיבל את המקום של טעינה שהסתיימה.
        if (_waiters.remove(ticket)) {
          throw Exception('error.timeout: book content queue is full');
        }
      }
    }
    var released = false;
    void release() {
      if (released) return;
      released = true;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _activeLoads--;
      }
    }

    final stall = Timer(timeout - clock.elapsed, release);
    try {
      return await load();
    } finally {
      stall.cancel();
      release();
    }
  }

  /// סופר את [call] כקריאה פעילה של [pluginId] עד שהיא מסתיימת, גם בשגיאה.
  static Future<T> trackCall<T>(
    String pluginId,
    Future<T> Function() call,
  ) async {
    final counter = _calls.putIfAbsent(pluginId, _CallCounter.new)..start();
    try {
      return await call();
    } finally {
      counter.active--;
    }
  }

  /// null עד הקריאה הראשונה מתוסף.
  static Map<String, Object>? get diagnostics => _calls.isEmpty
      ? null
      : {
          'activeLoads': _activeLoads,
          'queuedLoads': _waiters.length,
          'plugins': {
            for (final entry in _calls.entries)
              entry.key: {
                'active': entry.value.active,
                'peak': entry.value.peak,
                'calls': entry.value.calls,
              },
          },
        };

  @visibleForTesting
  static void resetForTesting() {
    _activeLoads = 0;
    _waiters.clear();
    _calls.clear();
  }
}

class _CallCounter {
  int active = 0;
  int peak = 0;
  int calls = 0;

  void start() {
    calls++;
    active++;
    if (active > peak) peak = active;
  }
}
