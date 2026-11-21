import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/plugins/plugin_constants.dart';

/// הטעינה לא התחילה לפני שתקציב ה-RPC של המתקשר נגמר.
class PluginBookContentQueueTimeout implements Exception {
  const PluginBookContentQueueTimeout();

  @override
  String toString() => 'error.timeout: book content queue is full';
}

/// מגביל את טעינות הטקסט המלא של ספרים שמקורן בתוספים, וסופר לכל תוסף את
/// קריאות `library.getBookContent` שלו לאבחון שבדוח.
///
/// הקורא של התוכנה וההדפסה לא עוברים כאן, כך שתוסף שסורק ספרייה לא מעכב אותם.
class PluginBookContentGate {
  PluginBookContentGate._();

  /// מקומות משותפים לכל התוספים: כל טעינה מחזיקה את הקובץ ואת הטקסט המפוענח,
  /// והדיסק לא מרוויח מיותר. תוסף בלי טעינה פעילה עוקף אותם עד [maxRunningLoads].
  static const int maxConcurrentLoads = 2;

  /// תקרת הטעינות שרצות בפועל, כולל תקועות ותוסף שעוקף תור של תוסף אחר.
  static const int maxRunningLoads = 4;

  /// נקרא פעם אחת לתהליך כשטעינות תקועות ממלאות את [maxRunningLoads].
  @visibleForTesting
  static void Function(Iterable<String> pluginIds) reportStalledCeiling =
      _logStalledCeiling;

  /// טעינה שרצה יותר מזה מפנה את מקומה ונספרת כתקועה עד שתסתיים.
  @visibleForTesting
  static Duration stallAfter = kPluginDefaultRpcTimeout;

  static int _slots = 0;
  static int _running = 0;
  static int _stalled = 0;
  static bool _stalledCeilingReported = false;
  static final Map<String, int> _slotsByPlugin = {};
  // תוסף עם טעינה תקועה לא מתחיל טעינה נוספת עד שהיא חוזרת.
  static final Map<String, int> _stalledByPlugin = {};
  static final Map<String, Queue<_Waiter>> _queues = {};
  // סדר הסבב בין תוספים שיש להם ממתינים.
  static final Queue<String> _turns = Queue();
  static final Map<String, _CallCounter> _calls = {};

  /// מריץ את [load] כשמתפנה מקום ל-[pluginId]. אם המקום לא התפנה תוך
  /// [timeout], נזרק [PluginBookContentQueueTimeout] בלי לטעון.
  static Future<T> runLoad<T>(
    Future<T> Function() load, {
    required String pluginId,
    required Object owner,
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) throw const PluginBookContentQueueTimeout();
    final clock = Stopwatch()..start();
    if (_canStart(pluginId)) {
      _take(pluginId);
    } else {
      final waiter = _Waiter(pluginId, owner);
      (_queues[pluginId] ??= Queue()).add(waiter);
      if (!_turns.contains(pluginId)) _turns.add(pluginId);
      waiter.expiry = Timer(timeout - clock.elapsed, () {
        if (_remove(waiter)) {
          waiter.ticket.completeError(const PluginBookContentQueueTimeout());
        }
      });
      await waiter.ticket.future;
    }
    if (clock.elapsed >= timeout) {
      _release(pluginId, stalled: false);
      throw const PluginBookContentQueueTimeout();
    }

    var stalled = false;
    final stall = Timer(stallAfter, () {
      stalled = true;
      _stalled++;
      _stalledByPlugin[pluginId] = (_stalledByPlugin[pluginId] ?? 0) + 1;
      _freeSlot(pluginId);
      if (_stalled >= maxRunningLoads && !_stalledCeilingReported) {
        _stalledCeilingReported = true;
        reportStalledCeiling(_stalledByPlugin.keys.toList());
      }
      _pump();
    });
    try {
      return await load();
    } finally {
      stall.cancel();
      _release(pluginId, stalled: stalled);
    }
  }

  /// מבטל את הממתינים של [owner] (מתאם שנסגר או שהדף שלו שוחרר).
  static void cancelWaiters(Object owner) {
    for (final queue in _queues.values.toList()) {
      for (final waiter in queue.toList()) {
        if (!identical(waiter.owner, owner) || !_remove(waiter)) continue;
        waiter.ticket.completeError(
          Exception('error.unavailable: plugin page closed'),
        );
      }
    }
  }

  // תוסף שאין לו טעינה פעילה עוקף את התור כל עוד התקרה מאפשרת.
  static bool _canStart(String pluginId) =>
      _running < maxRunningLoads &&
      !_stalledByPlugin.containsKey(pluginId) &&
      (_slots < maxConcurrentLoads || (_slotsByPlugin[pluginId] ?? 0) == 0) &&
      (_queues[pluginId]?.isEmpty ?? true);

  static void _take(String pluginId) {
    _slots++;
    _running++;
    _slotsByPlugin[pluginId] = (_slotsByPlugin[pluginId] ?? 0) + 1;
  }

  static void _freeSlot(String pluginId) {
    _slots--;
    final left = (_slotsByPlugin[pluginId] ?? 1) - 1;
    if (left <= 0) {
      _slotsByPlugin.remove(pluginId);
    } else {
      _slotsByPlugin[pluginId] = left;
    }
  }

  static void _release(String pluginId, {required bool stalled}) {
    _running--;
    if (stalled) {
      _stalled--;
      final left = _stalledByPlugin[pluginId]! - 1;
      if (left == 0) {
        _stalledByPlugin.remove(pluginId);
      } else {
        _stalledByPlugin[pluginId] = left;
      }
    } else {
      _freeSlot(pluginId);
    }
    _pump();
  }

  /// נותן מקומות בסבב בין התוספים, וקודם לתוסף שאין לו טעינה פעילה.
  static void _pump() {
    while (_running < maxRunningLoads && _turns.isNotEmpty) {
      final eligible = _turns.where((id) => !_stalledByPlugin.containsKey(id));
      final next =
          eligible.where((id) => (_slotsByPlugin[id] ?? 0) == 0).firstOrNull ??
          (_slots < maxConcurrentLoads ? eligible.firstOrNull : null);
      if (next == null) return;
      final queue = _queues[next]!;
      final waiter = queue.removeFirst();
      _turns.remove(next);
      if (queue.isEmpty) {
        _queues.remove(next);
      } else {
        _turns.add(next);
      }
      waiter.expiry?.cancel();
      _take(next);
      waiter.ticket.complete();
    }
  }

  static bool _remove(_Waiter waiter) {
    final queue = _queues[waiter.pluginId];
    if (queue == null || !queue.remove(waiter)) return false;
    waiter.expiry?.cancel();
    if (queue.isEmpty) {
      _queues.remove(waiter.pluginId);
      _turns.remove(waiter.pluginId);
    }
    return true;
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
          'activeLoads': _slots,
          'runningLoads': _running,
          'stalledLoads': _stalled,
          'queuedLoads': _queues.values.fold<int>(
            0,
            (sum, q) => sum + q.length,
          ),
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
  static int get runningLoadsForTesting => _running;

  @visibleForTesting
  static void resetForTesting() {
    for (final queue in _queues.values) {
      for (final waiter in queue) {
        waiter.expiry?.cancel();
      }
    }
    _slots = 0;
    _running = 0;
    _stalled = 0;
    _stalledCeilingReported = false;
    _slotsByPlugin.clear();
    _stalledByPlugin.clear();
    _queues.clear();
    _turns.clear();
    _calls.clear();
    stallAfter = kPluginDefaultRpcTimeout;
    reportStalledCeiling = _logStalledCeiling;
  }

  static void _logStalledCeiling(Iterable<String> pluginIds) {
    try {
      ErrorLogFile.appendInBackground(
        title: 'Plugin book loads stalled',
        error:
            'All $maxRunningLoads plugin book-content loads are stalled; '
            'getBookContent waits until one returns',
        details: {'Plugins': pluginIds.join(', ')},
      );
    } catch (_) {}
  }
}

class _Waiter {
  _Waiter(this.pluginId, this.owner);

  final String pluginId;
  final Object owner;
  final Completer<void> ticket = Completer<void>();
  Timer? expiry;
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
