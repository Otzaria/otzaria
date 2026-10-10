import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// סימון תהליכי לכך שמסד הספרייה מושעה לכתיבה חיצונית.
///
/// חלון שנפתח בזמן החלפת המסד עדיין לא קיבל `library.suspend`, ולכן הוא
/// ממתין כאן לפני שהוא פותח את הספרייה. [IsolateNameServer] הוא הרישום
/// היחיד שמשותף לכל ה-isolates בתהליך, ובדיקת השם סינכרונית וזולה.
class LibrarySuspensionMarker {
  LibrarySuspensionMarker._();

  static String get _name => WindowBus.sharedName('librarySuspended');
  static String get _reaperName => '$_name.reaper';
  static String _tokenName(String token) => '$_name.$token';

  static ReceivePort? _port;
  static String? _token;
  static final List<SendPort> _waiters = [];
  static final Set<SendPort> _exitObservers = {};

  /// האם isolate כלשהו בתהליך (כולל זה) מחזיק את הסימון.
  static bool get isRegistered =>
      IsolateNameServer.lookupPortByName(_name) != null;

  /// מבקש מה-VM לשלוח [notice] ל-[observers] כשה-isolate הזה מסתיים.
  ///
  /// חוזר רק כשהבקשות כבר עובדו: ping אחריהן מאותו isolate מעובד אחריהן.
  static Future<void> notifyOnExit(
    Iterable<SendPort> observers,
    Object notice,
  ) async {
    final self = Isolate.current;
    for (final observer in observers) {
      self.addOnExitListener(observer, response: notice);
      _exitObservers.add(observer);
    }
    final armed = ReceivePort();
    try {
      self.ping(armed.sendPort, priority: Isolate.immediate);
      await armed.first;
    } finally {
      armed.close();
    }
  }

  /// רושם את הסימון בשם [token]. false כשהוא כבר רשום, כאן או ב-isolate אחר.
  ///
  /// [observers] מקבלים [notice] אם ה-isolate הזה מת, ונדרכים לפני הרישום
  /// כדי שלא תהיה נעילה בלי מי שיראה את מות בעליה.
  static Future<bool> acquire(
    String token, {
    Iterable<SendPort> observers = const [],
    Object? notice,
  }) async {
    if (_port != null || isRegistered) return false;
    await notifyOnExit(observers, notice ?? token);
    if (_port != null) return false;
    final port = ReceivePort();
    // קודם שם הזיהוי: מי שקיבל הודעת סיום מסיר רק נעילה שהשם הזה מצביע עליה.
    if (!IsolateNameServer.registerPortWithName(
      port.sendPort,
      _tokenName(token),
    )) {
      port.close();
      _cancelExitNotices();
      return false;
    }
    if (!IsolateNameServer.registerPortWithName(port.sendPort, _name)) {
      IsolateNameServer.removePortNameMapping(_tokenName(token));
      port.close();
      _cancelExitNotices();
      return false;
    }
    port.listen((message) {
      if (message is! SendPort || _waiters.contains(message)) return;
      _waiters.add(message);
      Isolate.current.addOnExitListener(message, response: notice ?? token);
      _exitObservers.add(message);
    });
    _port = port;
    _token = token;
    return true;
  }

  /// מסיר את הסימון ומעיר את כל הממתינים.
  static void release() {
    final port = _port;
    if (port == null) return;
    IsolateNameServer.removePortNameMapping(_name);
    IsolateNameServer.removePortNameMapping(_tokenName(_token!));
    _cancelExitNotices();
    for (final waiter in _waiters) {
      waiter.send(true);
    }
    _waiters.clear();
    port.close();
    _port = null;
    _token = null;
  }

  static void _cancelExitNotices() {
    for (final observer in _exitObservers) {
      Isolate.current.removeOnExitListener(observer);
    }
    _exitObservers.clear();
  }

  /// משחזר החלפה שנקטעה לפני הסרת הנעילה; נקרא רק מהודעת יציאה של ה-VM.
  static Future<void> recoverExitedOwner(Map<String, dynamic> notice) async {
    final token = notice['operationId'] as String;
    final guard = RawReceivePort();
    while (!IsolateNameServer.registerPortWithName(
      guard.sendPort,
      _reaperName,
    )) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    try {
      WindowBus.removeExitedWindow(
        notice['ownerSlot'] as int?,
        notice['ownerPort'] as SendPort?,
      );
      final owned = IsolateNameServer.lookupPortByName(_tokenName(token));
      if (owned == null) return;
      if (IsolateNameServer.lookupPortByName(_name) == owned) {
        final dbPath = notice['dbPath'] as String?;
        if (dbPath != null) {
          await const LibraryDbRecoveryService().recoverIfNeeded(dbPath);
          if (!File(dbPath).existsSync()) {
            throw StateError('מסד הספרייה חסר אחרי התאוששות: $dbPath');
          }
        }
        IsolateNameServer.removePortNameMapping(_name);
      }
      IsolateNameServer.removePortNameMapping(_tokenName(token));
    } finally {
      IsolateNameServer.removePortNameMapping(_reaperName);
      guard.close();
    }
  }

  /// ממתין עד שהסימון יוסר. חוזר מיד כשאין סימון או כשהוא שלנו.
  ///
  /// [cap] מגביל המתנה לתגובה בודדת; סימון רשום לעולם אינו מתיר פתיחה.
  static Future<void> waitUntilReleased({
    Duration poll = const Duration(seconds: 5),
    Duration cap = const Duration(minutes: 20),
  }) async {
    if (_port != null) return;
    // port אחד לכל ההמתנה, כדי שהודעת הסיום של הבעלים לא תיפול בין סבבים.
    final reply = ReceivePort();
    final messages = reply.asBroadcastStream();
    try {
      while (true) {
        final target = IsolateNameServer.lookupPortByName(_name);
        if (target == null) return;
        target.send(reply.sendPort);
        try {
          final message = await messages.first.timeout(
            poll < cap ? poll : cap,
          );
          if (message is Map && message['body'] is Map) {
            await recoverExitedOwner(
              Map<String, dynamic>.from(message['body'] as Map),
            );
          } else if (message is String) {
            await recoverExitedOwner({'operationId': message});
          }
        } on TimeoutException {
          // הסימון עדיין רשום; בודקים שוב.
        }
      }
    } finally {
      reply.close();
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    release();
    IsolateNameServer.removePortNameMapping(_name);
    IsolateNameServer.removePortNameMapping(_reaperName);
  }
}
