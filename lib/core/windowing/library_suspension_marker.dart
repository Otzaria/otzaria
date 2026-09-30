import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/window_bus.dart';

/// סימון תהליכי לכך שמסד הספרייה מושעה לכתיבה חיצונית.
///
/// חלון שנפתח בזמן החלפת המסד עדיין לא קיבל `library.suspend`, ולכן הוא
/// ממתין כאן לפני שהוא פותח את הספרייה. [IsolateNameServer] הוא הרישום
/// היחיד שמשותף לכל ה-isolates בתהליך, ובדיקת השם סינכרונית וזולה.
class LibrarySuspensionMarker {
  LibrarySuspensionMarker._();

  static String get _name => WindowBus.sharedName('librarySuspended');

  static ReceivePort? _port;
  static final List<SendPort> _waiters = [];

  /// האם ה-isolate הזה מחזיק את הסימון.
  static bool get isHeldHere => _port != null;

  /// האם isolate כלשהו בתהליך (כולל זה) מחזיק את הסימון.
  static bool get isRegistered =>
      IsolateNameServer.lookupPortByName(_name) != null;

  /// האם isolate אחר בתהליך השעה את הספרייה.
  static bool get isSuspendedElsewhere =>
      _port == null && IsolateNameServer.lookupPortByName(_name) != null;

  /// רושם את הסימון. false כשהוא כבר רשום, כאן או ב-isolate אחר.
  static bool acquire() {
    if (_port != null) return false;
    final port = ReceivePort();
    if (!IsolateNameServer.registerPortWithName(port.sendPort, _name)) {
      port.close();
      return false;
    }
    port.listen((message) {
      if (message is SendPort) _waiters.add(message);
    });
    _port = port;
    return true;
  }

  /// מסיר את הסימון ומעיר את כל הממתינים.
  static void release() {
    final port = _port;
    if (port == null) return;
    IsolateNameServer.removePortNameMapping(_name);
    for (final waiter in _waiters) {
      waiter.send(true);
    }
    _waiters.clear();
    port.close();
    _port = null;
  }

  /// ממתין עד שהסימון יוסר. חוזר מיד כשאין סימון או כשהוא שלנו.
  ///
  /// [cap] מונע המתנה נצחית אם הסימון נשאר רשום בלי מאזין.
  static Future<void> waitUntilReleased({
    Duration poll = const Duration(seconds: 5),
    Duration cap = const Duration(minutes: 20),
  }) async {
    if (_port != null) return;
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < cap) {
      final target = IsolateNameServer.lookupPortByName(_name);
      if (target == null) return;
      final reply = ReceivePort();
      try {
        target.send(reply.sendPort);
        await reply.first.timeout(poll);
      } on TimeoutException {
        // הסימון עדיין רשום; בודקים שוב.
      } finally {
        reply.close();
      }
    }
    debugPrint(
      '[LibrarySuspensionMarker] gave up waiting after '
      '${cap.inSeconds}s; opening the library anyway',
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    release();
    IsolateNameServer.removePortNameMapping(_name);
  }
}
